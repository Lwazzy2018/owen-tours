using Microsoft.EntityFrameworkCore;
using OwenTours.Application.Abstractions;
using OwenTours.Application.Common;
using OwenTours.Application.Dtos;
using OwenTours.Domain.Entities;
using OwenTours.Domain.Rules;

namespace OwenTours.Application.Services;

public sealed class PastTripService(IAppDbContext db, IClock clock, AuditLogger audit, IFileStorage storage, IImageProcessor images)
{
    public const string Bucket = "past-trip-media";
    public const long MaxVideoBytes = 50L * 1024 * 1024;
    public static readonly string[] VideoTypes = ["video/mp4", "video/quicktime", "video/webm"];

    // ---------------- Public ----------------

    public async Task<PagedResult<PastTripSummaryDto>> ListAsync(string? destination, bool? featured, bool includeUnpublished,
        int? page, int? pageSize, CancellationToken ct)
    {
        var (p, size) = Paging.Normalise(page, pageSize, 50);
        var q = db.PastTrips.AsNoTracking().AsQueryable();
        if (!includeUnpublished) q = q.Where(x => x.IsPublished);
        if (!string.IsNullOrWhiteSpace(destination)) q = q.Where(x => EF.Functions.ILike(x.Destination, $"%{destination.Trim()}%"));
        if (featured == true) q = q.Where(x => x.IsFeatured);

        var total = await q.CountAsync(ct);
        var items = await q
            .OrderByDescending(x => x.IsFeatured).ThenBy(x => x.SortOrder).ThenByDescending(x => x.TravelledOn)
            .Skip((p - 1) * size).Take(size)
            .Select(x => new PastTripSummaryDto(x.Id, x.TripId, x.Title, x.Destination, x.TravelledOn, x.TravellerCount,
                x.CoverUrl, x.IsFeatured, x.IsPublished, x.Media.Count))
            .ToListAsync(ct);
        return new PagedResult<PastTripSummaryDto>(items, p, size, total);
    }

    public async Task<PastTripDetailDto> GetAsync(Guid id, bool includeUnpublished, CancellationToken ct)
    {
        var x = await db.PastTrips.AsNoTracking()
            .Include(p => p.Media)
            .Include(p => p.Testimonials)
            .FirstOrDefaultAsync(p => p.Id == id && (includeUnpublished || p.IsPublished), ct)
            ?? throw new NotFoundException("Past trip");

        var now = clock.UtcNow;
        var hasUpcoming = x.TripId is not null && await db.Departures.AnyAsync(d =>
            d.TripId == x.TripId && d.DepartureAt > now && !d.IsCancelledByCompany && d.Trip!.IsPublished, ct);

        return ToDetail(x, includeUnpublished, hasUpcoming);
    }

    public async Task<IReadOnlyList<PastTripSummaryDto>> ForTripAsync(Guid tripId, CancellationToken ct) =>
        await db.PastTrips.AsNoTracking()
            .Where(x => x.TripId == tripId && x.IsPublished)
            .OrderByDescending(x => x.TravelledOn)
            .Select(x => new PastTripSummaryDto(x.Id, x.TripId, x.Title, x.Destination, x.TravelledOn, x.TravellerCount,
                x.CoverUrl, x.IsFeatured, x.IsPublished, x.Media.Count))
            .ToListAsync(ct);

    // ---------------- Admin ----------------

    public async Task<PastTripDetailDto> CreateAsync(PastTripUpsertRequest req, CancellationToken ct)
    {
        var x = new PastTrip { CreatedAt = clock.UtcNow };
        await ApplyAsync(x, req, ct);
        db.PastTrips.Add(x);
        audit.Log("past_trip.created", "past_trip", x.Id, new { x.Title });
        await db.SaveChangesAsync(ct);
        return await GetAsync(x.Id, true, ct);
    }

    public async Task<PastTripDetailDto> UpdateAsync(Guid id, PastTripUpsertRequest req, CancellationToken ct)
    {
        var x = await db.PastTrips.FirstOrDefaultAsync(p => p.Id == id, ct) ?? throw new NotFoundException("Past trip");
        await ApplyAsync(x, req, ct);
        audit.Log("past_trip.updated", "past_trip", x.Id, new { x.Title, x.IsPublished });
        await db.SaveChangesAsync(ct);
        return await GetAsync(id, true, ct);
    }

    public async Task DeleteAsync(Guid id, CancellationToken ct)
    {
        var x = await db.PastTrips.Include(p => p.Media).FirstOrDefaultAsync(p => p.Id == id, ct) ?? throw new NotFoundException("Past trip");
        var paths = x.Media.Where(m => m.StoragePath is not null).Select(m => m.StoragePath!).ToList();
        db.PastTrips.Remove(x);
        audit.Log("past_trip.deleted", "past_trip", id, new { x.Title });
        await db.SaveChangesAsync(ct);
        foreach (var path in paths) await DeleteFilesAsync(path, ct);
    }

    public async Task<PastTripMediaDto> AddMediaAsync(Guid id, Stream file, string contentType, long length, string? caption, CancellationToken ct)
    {
        var x = await db.PastTrips.Include(p => p.Media).FirstOrDefaultAsync(p => p.Id == id, ct) ?? throw new NotFoundException("Past trip");
        var key = $"{id}/{Guid.NewGuid():N}";
        PastTripMedia media;

        if (contentType.StartsWith("image/", StringComparison.OrdinalIgnoreCase))
        {
            var processed = await images.ProcessAsync(file, ct);
            var full = await storage.UploadAsync(Bucket, key + processed.Extension, new MemoryStream(processed.Full), processed.ContentType, ct);
            var thumb = await storage.UploadAsync(Bucket, key + "_thumb" + processed.Extension, new MemoryStream(processed.Thumbnail), processed.ContentType, ct);
            media = new PastTripMedia { MediaType = "image", Url = full.PublicUrl ?? "", ThumbnailUrl = thumb.PublicUrl, StoragePath = full.Path };
        }
        else if (VideoTypes.Contains(contentType.ToLowerInvariant()))
        {
            if (length > MaxVideoBytes)
                throw new BusinessRuleException($"Videos can be at most {MaxVideoBytes / 1024 / 1024} MB. Please trim or compress it first.", 413);
            var ext = contentType.ToLowerInvariant() switch { "video/quicktime" => ".mov", "video/webm" => ".webm", _ => ".mp4" };
            var stored = await storage.UploadAsync(Bucket, key + ext, file, contentType, ct);
            media = new PastTripMedia { MediaType = "video", Url = stored.PublicUrl ?? "", ThumbnailUrl = x.CoverUrl, StoragePath = stored.Path };
        }
        else
        {
            throw new BusinessRuleException("Upload a photo (JPG, PNG, WEBP) or a video (MP4, MOV, WEBM).", 415);
        }

        media.PastTripId = id;
        media.Caption = caption;
        media.SortOrder = x.Media.Count == 0 ? 0 : x.Media.Max(m => m.SortOrder) + 1;
        media.CreatedAt = clock.UtcNow;
        db.PastTripMedia.Add(media);
        if (x.CoverUrl is null && media.MediaType == "image") x.CoverUrl = media.Url;
        await db.SaveChangesAsync(ct);
        return ToDto(media);
    }

    public async Task ReorderMediaAsync(Guid id, IReadOnlyList<MediaOrderItem> items, CancellationToken ct)
    {
        var media = await db.PastTripMedia.Where(m => m.PastTripId == id).ToListAsync(ct);
        foreach (var item in items)
        {
            var m = media.FirstOrDefault(x => x.Id == item.Id);
            if (m is null) continue;
            m.SortOrder = item.SortOrder;
            m.Caption = item.Caption;
        }
        await db.SaveChangesAsync(ct);
    }

    public async Task DeleteMediaAsync(Guid id, Guid mediaId, CancellationToken ct)
    {
        var m = await db.PastTripMedia.FirstOrDefaultAsync(x => x.Id == mediaId && x.PastTripId == id, ct) ?? throw new NotFoundException("Media");
        db.PastTripMedia.Remove(m);
        var trip = await db.PastTrips.FirstAsync(p => p.Id == id, ct);
        if (trip.CoverUrl == m.Url) trip.CoverUrl = null;
        await db.SaveChangesAsync(ct);
        if (m.StoragePath is not null) await DeleteFilesAsync(m.StoragePath, ct);
    }

    public async Task<TestimonialDto> AddTestimonialAsync(Guid id, TestimonialRequest req, CancellationToken ct)
    {
        if (!await db.PastTrips.AnyAsync(p => p.Id == id, ct)) throw new NotFoundException("Past trip");
        var t = new Testimonial { PastTripId = id, CreatedAt = clock.UtcNow };
        Apply(t, req);
        db.Testimonials.Add(t);
        audit.Log("testimonial.created", "past_trip", id, new { t.CustomerName, t.IsPublished });
        await db.SaveChangesAsync(ct);
        return ToDto(t);
    }

    public async Task<TestimonialDto> UpdateTestimonialAsync(Guid id, Guid testimonialId, TestimonialRequest req, CancellationToken ct)
    {
        var t = await db.Testimonials.FirstOrDefaultAsync(x => x.Id == testimonialId && x.PastTripId == id, ct)
                ?? throw new NotFoundException("Testimonial");
        Apply(t, req);
        await db.SaveChangesAsync(ct);
        return ToDto(t);
    }

    public async Task DeleteTestimonialAsync(Guid id, Guid testimonialId, CancellationToken ct)
    {
        var t = await db.Testimonials.FirstOrDefaultAsync(x => x.Id == testimonialId && x.PastTripId == id, ct)
                ?? throw new NotFoundException("Testimonial");
        db.Testimonials.Remove(t);
        await db.SaveChangesAsync(ct);
    }

    // ---------------- Helpers ----------------

    private async Task ApplyAsync(PastTrip x, PastTripUpsertRequest r, CancellationToken ct)
    {
        if (r.TripId is not null && !await db.Trips.AnyAsync(t => t.Id == r.TripId, ct))
            throw new BusinessRuleException("The linked trip doesn't exist.", 422);
        x.TripId = r.TripId;
        x.Title = r.Title.Trim();
        x.Destination = r.Destination.Trim();
        x.TravelledOn = r.TravelledOn;
        x.TravellerCount = r.TravellerCount;
        x.Story = r.Story?.Trim();
        if (!string.IsNullOrWhiteSpace(r.CoverUrl)) x.CoverUrl = r.CoverUrl;
        x.IsFeatured = r.IsFeatured;
        x.IsPublished = r.IsPublished;
        x.SortOrder = r.SortOrder;
        x.UpdatedAt = clock.UtcNow;
    }

    private static void Apply(Testimonial t, TestimonialRequest r)
    {
        t.CustomerName = r.CustomerName.Trim();
        t.Quote = r.Quote.Trim();
        t.Rating = r.Rating;
        t.PhotoUrl = r.PhotoUrl;
        t.IsPublished = r.IsPublished;
    }

    private async Task DeleteFilesAsync(string path, CancellationToken ct)
    {
        await storage.DeleteAsync(Bucket, path, ct);
        var dot = path.LastIndexOf('.');
        if (dot > 0) await storage.DeleteAsync(Bucket, path[..dot] + "_thumb" + path[dot..], ct);
    }

    private static PastTripMediaDto ToDto(PastTripMedia m) => new(m.Id, m.MediaType, m.Url, m.ThumbnailUrl, m.Caption, m.SortOrder);

    private static TestimonialDto ToDto(Testimonial t) => new(t.Id, t.CustomerName, t.Quote, t.Rating, t.PhotoUrl, t.IsPublished);

    private static PastTripDetailDto ToDetail(PastTrip x, bool includeUnpublished, bool hasUpcoming) => new(
        x.Id, x.TripId, x.Title, x.Destination, x.TravelledOn, x.TravellerCount, x.Story, x.CoverUrl, x.IsFeatured, x.IsPublished,
        x.SortOrder,
        x.Media.OrderBy(m => m.SortOrder).Select(ToDto).ToList(),
        x.Testimonials.Where(t => includeUnpublished || t.IsPublished).OrderBy(t => t.CreatedAt).Select(ToDto).ToList(),
        hasUpcoming);
}
