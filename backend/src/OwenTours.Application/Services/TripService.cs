using Microsoft.EntityFrameworkCore;
using OwenTours.Application.Abstractions;
using OwenTours.Application.Common;
using OwenTours.Application.Dtos;
using OwenTours.Domain.Common;
using OwenTours.Domain.Entities;
using OwenTours.Domain.Rules;

namespace OwenTours.Application.Services;

public sealed class TripService(IAppDbContext db, IClock clock, AuditLogger audit, IFileStorage storage, IImageProcessor images)
{
    public const string TripMediaBucket = "trip-media";

    // ---------------- Public ----------------

    public async Task<PagedResult<TripSummaryDto>> SearchAsync(TripQuery q, bool includeUnpublished, CancellationToken ct)
    {
        var now = clock.UtcNow;
        var (page, size) = Paging.Normalise(q.Page, q.PageSize, 50);

        var trips = db.Trips.AsNoTracking().AsQueryable();
        if (!includeUnpublished) trips = trips.Where(t => t.IsPublished);
        if (!string.IsNullOrWhiteSpace(q.Search))
        {
            var term = $"%{q.Search.Trim()}%";
            trips = trips.Where(t => EF.Functions.ILike(t.Title, term) || EF.Functions.ILike(t.Destination, term));
        }
        if (!string.IsNullOrWhiteSpace(q.Destination))
            trips = trips.Where(t => EF.Functions.ILike(t.Destination, $"%{q.Destination.Trim()}%"));
        if (!string.IsNullOrWhiteSpace(q.Category))
            trips = trips.Where(t => t.Category == q.Category);

        // Departure filters: a trip matches if at least one upcoming departure matches.
        var fromUtc = q.From is null ? (DateTimeOffset?)null : SaTime.StartOfDayUtc(q.From.Value);
        var toUtc = q.To is null ? (DateTimeOffset?)null : SaTime.EndOfDayUtc(q.To.Value);
        var departureFilterUsed = fromUtc is not null || toUtc is not null || q.MaxPriceCents is not null
                                  || !string.IsNullOrWhiteSpace(q.DepartureProvince) || !string.IsNullOrWhiteSpace(q.DepartureArea);
        if (departureFilterUsed)
        {
            trips = trips.Where(t => t.Departures.Any(d =>
                d.DepartureAt > now && !d.IsCancelledByCompany
                && (fromUtc == null || d.DepartureAt >= fromUtc)
                && (toUtc == null || d.DepartureAt <= toUtc)
                && (q.MaxPriceCents == null || d.AdultPriceCents <= q.MaxPriceCents)
                && (q.DepartureProvince == null || d.DepartureProvince == q.DepartureProvince)
                && (q.DepartureArea == null || d.DepartureArea == q.DepartureArea)));
        }

        var total = await trips.CountAsync(ct);
        var pageItems = await trips
            .Include(t => t.Images)
            .Include(t => t.Departures.Where(d => d.DepartureAt > now && !d.IsCancelledByCompany))
            .OrderBy(t => t.Departures.Where(d => d.DepartureAt > now && !d.IsCancelledByCompany).Min(d => (DateTimeOffset?)d.DepartureAt) ?? DateTimeOffset.MaxValue)
            .ThenBy(t => t.Title)
            .Skip((page - 1) * size).Take(size)
            .ToListAsync(ct);

        var specials = await LiveSpecialsAsync(ct);
        var items = pageItems.Select(t => Mapping.ToSummary(t, t.Departures, BestPublicSpecial(specials, t.Id))).ToList();
        return new PagedResult<TripSummaryDto>(items, page, size, total);
    }

    public async Task<TripDetailDto> GetAsync(Guid id, bool includeUnpublished, CancellationToken ct)
    {
        var now = clock.UtcNow;
        var trip = await db.Trips.AsNoTracking()
            .Include(t => t.Images)
            .Include(t => t.ItineraryDays)
            .Include(t => t.Departures)
            .FirstOrDefaultAsync(t => t.Id == id && (includeUnpublished || t.IsPublished), ct)
            ?? throw new NotFoundException("Trip");

        var departures = trip.Departures
            .Where(d => includeUnpublished || (d.DepartureAt > now && !d.IsCancelledByCompany))
            .OrderBy(d => d.DepartureAt)
            .Select(d => Mapping.ToDto(d, now))
            .ToList();

        var specials = (await LiveSpecialsAsync(ct))
            .Where(s => s.SpecialTrips.Any(x => x.TripId == id) && (s.Type != SpecialType.PromoCode || s.IsPublic))
            .Select(s => new SpecialBadgeDto(s.Id, s.Name, s.Type, s.PercentOff, s.MinTravellers, s.Description))
            .ToList();

        var ratings = await db.Reviews.Where(r => r.TripId == id).Select(r => r.Rating).ToListAsync(ct);

        return new TripDetailDto(
            trip.Id, trip.Title, trip.Destination, trip.DestinationCountry, trip.IsCrossBorderTrip, trip.Category, trip.Audience,
            trip.MinGrade, trip.MaxGrade, trip.Activities, trip.Tagline, trip.Description, trip.CoverImageUrl,
            Mapping.Included(trip),
            trip.Images.OrderBy(i => i.SortOrder).Select(i => new TripImageDto(i.Id, i.Url, i.ThumbnailUrl, i.SortOrder)).ToList(),
            trip.ItineraryDays.OrderBy(d => d.DayNumber).Select(d => new ItineraryDayDto(d.DayNumber, d.Title, d.Description)).ToList(),
            departures, specials,
            ratings.Count == 0 ? null : Math.Round(ratings.Average(), 1), ratings.Count,
            trip.IsPublished);
    }

    public async Task<IReadOnlyList<DepartureDto>> DeparturesAsync(Guid tripId, bool includePast, CancellationToken ct)
    {
        var now = clock.UtcNow;
        var list = await db.Departures.AsNoTracking()
            .Where(d => d.TripId == tripId && (includePast || (d.DepartureAt > now && !d.IsCancelledByCompany)))
            .Where(d => includePast || d.Trip!.IsPublished)
            .OrderBy(d => d.DepartureAt)
            .ToListAsync(ct);
        return list.Select(d => Mapping.ToDto(d, now)).ToList();
    }

    public async Task<IReadOnlyList<object>> DepartureLocationsAsync(CancellationToken ct)
    {
        var now = clock.UtcNow;
        var rows = await db.Departures.AsNoTracking()
            .Where(d => d.DepartureAt > now && !d.IsCancelledByCompany && d.Trip!.IsPublished)
            .Select(d => new { d.DepartureProvince, d.DepartureArea })
            .Distinct()
            .ToListAsync(ct);
        return rows
            .GroupBy(r => r.DepartureProvince)
            .OrderBy(g => g.Key)
            .Select(g => (object)new { province = g.Key, areas = g.Select(x => x.DepartureArea).OrderBy(a => a).ToList() })
            .ToList();
    }

    // ---------------- Admin ----------------

    public async Task<TripDetailDto> CreateAsync(TripUpsertRequest req, CancellationToken ct)
    {
        var trip = new Trip { CreatedAt = clock.UtcNow, UpdatedAt = clock.UtcNow };
        Apply(trip, req);
        db.Trips.Add(trip);
        SetItinerary(trip, req.Itinerary);
        audit.Log("trip.created", "trip", trip.Id, new { trip.Title });
        await db.SaveChangesAsync(ct);
        return await GetAsync(trip.Id, includeUnpublished: true, ct);
    }

    public async Task<TripDetailDto> UpdateAsync(Guid id, TripUpsertRequest req, CancellationToken ct)
    {
        var trip = await db.Trips.Include(t => t.ItineraryDays).FirstOrDefaultAsync(t => t.Id == id, ct)
                   ?? throw new NotFoundException("Trip");
        Apply(trip, req);
        db.ItineraryDays.RemoveRange(trip.ItineraryDays);
        trip.ItineraryDays.Clear();
        SetItinerary(trip, req.Itinerary);
        audit.Log("trip.updated", "trip", trip.Id, new { trip.Title, trip.IsPublished });
        await db.SaveChangesAsync(ct);
        return await GetAsync(trip.Id, includeUnpublished: true, ct);
    }

    public async Task DeleteAsync(Guid id, CancellationToken ct)
    {
        var trip = await db.Trips.FirstOrDefaultAsync(t => t.Id == id, ct) ?? throw new NotFoundException("Trip");
        if (await db.Departures.AnyAsync(d => d.TripId == id, ct))
            throw new BusinessRuleException("This trip has departures. Unpublish it instead of deleting it, so booking history is kept.", 409);
        db.Trips.Remove(trip);
        audit.Log("trip.deleted", "trip", id, new { trip.Title });
        await db.SaveChangesAsync(ct);
    }

    public async Task<TripImageDto> AddImageAsync(Guid tripId, Stream file, CancellationToken ct)
    {
        var trip = await db.Trips.Include(t => t.Images).FirstOrDefaultAsync(t => t.Id == tripId, ct)
                   ?? throw new NotFoundException("Trip");

        var processed = await images.ProcessAsync(file, ct);
        var key = $"trips/{tripId}/{Guid.NewGuid():N}";
        var full = await storage.UploadAsync(TripMediaBucket, $"{key}{processed.Extension}", new MemoryStream(processed.Full), processed.ContentType, ct);
        var thumb = await storage.UploadAsync(TripMediaBucket, $"{key}_thumb{processed.Extension}", new MemoryStream(processed.Thumbnail), processed.ContentType, ct);

        var image = new TripImage
        {
            TripId = tripId,
            Url = full.PublicUrl ?? "",
            ThumbnailUrl = thumb.PublicUrl,
            StoragePath = full.Path,
            SortOrder = trip.Images.Count == 0 ? 0 : trip.Images.Max(i => i.SortOrder) + 1,
            CreatedAt = clock.UtcNow,
        };
        db.TripImages.Add(image);
        trip.CoverImageUrl ??= image.Url;
        audit.Log("trip.image_added", "trip", tripId, new { image.StoragePath });
        await db.SaveChangesAsync(ct);
        return new TripImageDto(image.Id, image.Url, image.ThumbnailUrl, image.SortOrder);
    }

    public async Task DeleteImageAsync(Guid tripId, Guid imageId, CancellationToken ct)
    {
        var image = await db.TripImages.FirstOrDefaultAsync(i => i.Id == imageId && i.TripId == tripId, ct)
                    ?? throw new NotFoundException("Image");
        db.TripImages.Remove(image);
        var trip = await db.Trips.FirstAsync(t => t.Id == tripId, ct);
        if (trip.CoverImageUrl == image.Url) trip.CoverImageUrl = null;
        audit.Log("trip.image_deleted", "trip", tripId, new { image.StoragePath });
        await db.SaveChangesAsync(ct);
        if (image.StoragePath is not null)
        {
            await storage.DeleteAsync(TripMediaBucket, image.StoragePath, ct);
            await storage.DeleteAsync(TripMediaBucket, ThumbPath(image.StoragePath), ct);
        }
    }

    public async Task ReorderImagesAsync(Guid tripId, ImageOrderRequest req, CancellationToken ct)
    {
        var imagesForTrip = await db.TripImages.Where(i => i.TripId == tripId).ToListAsync(ct);
        for (var i = 0; i < req.ImageIdsInOrder.Count; i++)
        {
            var image = imagesForTrip.FirstOrDefault(x => x.Id == req.ImageIdsInOrder[i]);
            if (image is not null) image.SortOrder = i;
        }
        await db.SaveChangesAsync(ct);
    }

    // ---------------- Helpers ----------------

    internal async Task<List<Special>> LiveSpecialsAsync(CancellationToken ct)
    {
        var now = clock.UtcNow;
        return await db.Specials.AsNoTracking().Include(s => s.SpecialTrips)
            .Where(s => s.IsActive && s.StartsAt <= now && s.EndsAt >= now)
            .ToListAsync(ct);
    }

    private static Special? BestPublicSpecial(IEnumerable<Special> specials, Guid tripId) =>
        specials
            .Where(s => s.Type is SpecialType.Percentage or SpecialType.Group or SpecialType.Student)
            .Where(s => s.SpecialTrips.Any(x => x.TripId == tripId))
            .OrderByDescending(s => s.PercentOff)
            .FirstOrDefault();

    private static string ThumbPath(string path)
    {
        var dot = path.LastIndexOf('.');
        return dot < 0 ? path + "_thumb" : path[..dot] + "_thumb" + path[dot..];
    }

    private static void Apply(Trip t, TripUpsertRequest r)
    {
        if (!TripCategories.All.Contains(r.Category))
            throw new BusinessRuleException($"Unknown category \"{r.Category}\".", 400);
        if (r.Audience is not (Audience.Everyone or Audience.AdultsOnly or Audience.HighSchool))
            throw new BusinessRuleException("Audience must be everyone, adults_only or high_school.", 400);
        if (r.Audience == Audience.HighSchool && (r.MinGrade is null || r.MaxGrade is null || r.MinGrade > r.MaxGrade))
            throw new BusinessRuleException("Youth camps need a grade range, e.g. Grade 8 to 12.");

        t.Title = r.Title.Trim();
        t.Destination = r.Destination.Trim();
        t.DestinationCountry = string.IsNullOrWhiteSpace(r.DestinationCountry) ? "South Africa" : r.DestinationCountry.Trim();
        t.Category = r.Category;
        t.Audience = r.Audience;
        t.MinGrade = r.Audience == Audience.HighSchool ? r.MinGrade : null;
        t.MaxGrade = r.Audience == Audience.HighSchool ? r.MaxGrade : null;
        t.Activities = Clean(r.Activities);
        t.Tagline = r.Tagline?.Trim();
        t.Description = r.Description.Trim();
        t.CoverImageUrl = string.IsNullOrWhiteSpace(r.CoverImageUrl) ? t.CoverImageUrl : r.CoverImageUrl;
        t.TransportIncluded = r.TransportIncluded;
        t.TransportType = r.TransportIncluded ? r.TransportType : null;
        t.TransportNotes = r.TransportNotes;
        t.MealsBreakfast = r.MealsBreakfast;
        t.MealsLunch = r.MealsLunch;
        t.MealsDinner = r.MealsDinner;
        t.MealsSnacks = r.MealsSnacks;
        t.MealsNotes = r.MealsNotes;
        t.AccommodationIncluded = r.AccommodationIncluded;
        t.AccommodationType = r.AccommodationIncluded ? r.AccommodationType : null;
        t.AccommodationNotes = r.AccommodationNotes;
        t.Includes = Clean(r.Includes);
        t.Excludes = Clean(r.Excludes);
        t.IsPublished = r.IsPublished;
        t.UpdatedAt = DateTimeOffset.UtcNow;
    }

    private void SetItinerary(Trip trip, IEnumerable<ItineraryDayDto> days)
    {
        foreach (var d in days.Where(d => !string.IsNullOrWhiteSpace(d.Title)).GroupBy(d => d.DayNumber).Select(g => g.First()))
        {
            var day = new ItineraryDay { TripId = trip.Id, DayNumber = d.DayNumber, Title = d.Title.Trim(), Description = d.Description.Trim() };
            trip.ItineraryDays.Add(day);
        }
    }

    private static List<string> Clean(IEnumerable<string>? items) =>
        (items ?? []).Select(s => s.Trim()).Where(s => s.Length > 0).Distinct().ToList();
}
