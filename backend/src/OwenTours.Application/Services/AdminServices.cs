using Microsoft.EntityFrameworkCore;
using OwenTours.Application.Abstractions;
using OwenTours.Application.Common;
using OwenTours.Application.Dtos;
using OwenTours.Domain.Common;
using OwenTours.Domain.Entities;
using OwenTours.Domain.Rules;

namespace OwenTours.Application.Services;

// ============================ Specials ============================

public sealed class SpecialService(IAppDbContext db, IClock clock, AuditLogger audit)
{
    public async Task<IReadOnlyList<SpecialDto>> ActivePublicAsync(CancellationToken ct)
    {
        var now = clock.UtcNow;
        var list = await db.Specials.AsNoTracking().Include(s => s.SpecialTrips)
            .Where(s => s.IsActive && s.StartsAt <= now && s.EndsAt >= now && (s.Type != SpecialType.PromoCode || s.IsPublic))
            .OrderByDescending(s => s.PercentOff)
            .ToListAsync(ct);
        // Never show promo codes in public lists, even public ones: people type them.
        return list.Select(s => Mapping.ToDto(s) with { PromoCode = null, MaxUses = null, TimesUsed = 0 }).ToList();
    }

    public async Task<IReadOnlyList<SpecialDto>> AllAsync(CancellationToken ct) =>
        (await db.Specials.AsNoTracking().Include(s => s.SpecialTrips).OrderByDescending(s => s.StartsAt).ToListAsync(ct))
        .Select(Mapping.ToDto).ToList();

    public async Task<SpecialDto> CreateAsync(SpecialUpsertRequest req, CancellationToken ct)
    {
        var s = new Special { Id = Guid.NewGuid(), CreatedAt = clock.UtcNow };
        await ApplyAsync(s, req, ct);
        db.Specials.Add(s);
        audit.Log("special.created", "special", s.Id, new { s.Name, s.Type, s.PercentOff });
        await db.SaveChangesAsync(ct);
        return Mapping.ToDto(s);
    }

    public async Task<SpecialDto> UpdateAsync(Guid id, SpecialUpsertRequest req, CancellationToken ct)
    {
        var s = await db.Specials.Include(x => x.SpecialTrips).FirstOrDefaultAsync(x => x.Id == id, ct) ?? throw new NotFoundException("Special");
        // Existing bookings keep the discount they got (it's saved on each booking).
        await ApplyAsync(s, req, ct);
        audit.Log("special.updated", "special", s.Id, new { s.Name, s.Type, s.PercentOff, s.IsActive });
        await db.SaveChangesAsync(ct);
        return Mapping.ToDto(s);
    }

    public async Task DeleteAsync(Guid id, CancellationToken ct)
    {
        var s = await db.Specials.FirstOrDefaultAsync(x => x.Id == id, ct) ?? throw new NotFoundException("Special");
        if (await db.BookingDiscounts.AnyAsync(d => d.SpecialId == id, ct))
        {
            s.IsActive = false;   // used by bookings: switch it off instead of deleting
            audit.Log("special.deactivated", "special", id, new { s.Name });
        }
        else
        {
            db.Specials.Remove(s);
            audit.Log("special.deleted", "special", id, new { s.Name });
        }
        await db.SaveChangesAsync(ct);
    }

    private async Task ApplyAsync(Special s, SpecialUpsertRequest r, CancellationToken ct)
    {
        var errors = new RuleResult();
        if (r.Type is not (SpecialType.Percentage or SpecialType.Student or SpecialType.Group or SpecialType.PromoCode))
            errors.Error("type", "Type must be percentage, student, group or promo_code.");
        if (r.EndsAt <= r.StartsAt) errors.Error("endsAt", "The end date must be after the start date.");
        if (r.Type == SpecialType.Group && r.MinTravellers is null) errors.Error("minTravellers", "Group discounts need a minimum number of travellers.");
        if (r.Type == SpecialType.PromoCode && string.IsNullOrWhiteSpace(r.PromoCode)) errors.Error("promoCode", "Enter the promo code.");
        if (r.TripIds.Count == 0) errors.Error("tripIds", "Choose at least one trip this special applies to.");

        var code = r.Type == SpecialType.PromoCode ? r.PromoCode!.Trim().ToUpperInvariant() : null;
        if (code is not null && await db.Specials.AnyAsync(x => x.Id != s.Id && x.PromoCode != null && x.PromoCode.ToUpper() == code, ct))
            errors.Error("promoCode", "Another special already uses this code.");
        if (!errors.IsValid) throw BusinessRuleException.From(errors);

        s.Name = r.Name.Trim();
        s.Description = r.Description?.Trim();
        s.Type = r.Type;
        s.PercentOff = r.PercentOff;
        s.MinTravellers = r.Type == SpecialType.Group ? r.MinTravellers : null;
        s.PromoCode = code;
        s.IsPublic = r.IsPublic;
        s.MaxUses = r.MaxUses;
        s.StartsAt = r.StartsAt.ToUniversalTime();
        s.EndsAt = r.EndsAt.ToUniversalTime();
        s.IsActive = r.IsActive;
        s.BannerImageUrl = r.BannerImageUrl;
        s.UpdatedAt = clock.UtcNow;

        var wanted = r.TripIds.Distinct().ToHashSet();
        foreach (var link in s.SpecialTrips.Where(l => !wanted.Contains(l.TripId)).ToList())
        {
            s.SpecialTrips.Remove(link);
            db.SpecialTrips.Remove(link);
        }
        foreach (var tripId in wanted.Where(t => s.SpecialTrips.All(l => l.TripId != t)))
            s.SpecialTrips.Add(new SpecialTrip { SpecialId = s.Id, TripId = tripId });
    }
}

// ============================ Enquiries ============================

public sealed class EnquiryService(IAppDbContext db, IClock clock, ICurrentUser currentUser, AuditLogger audit, NotificationService notifications)
{
    public async Task<Guid> CreateAsync(EnquiryRequest req, CancellationToken ct)
    {
        var services = req.Services.Select(s => s.Trim().ToLowerInvariant()).Distinct().ToList();
        var unknown = services.Except(EnquiryServices.All).ToList();
        if (unknown.Count > 0) throw new BusinessRuleException($"Unknown service: {string.Join(", ", unknown)}", 400);
        if (req.TravelFrom is not null && req.TravelTo is not null && req.TravelTo < req.TravelFrom)
            throw new BusinessRuleException("The return date can't be before the travel date.", 422);

        var e = new Enquiry
        {
            CustomerId = currentUser.UserId,
            Name = req.Name.Trim(),
            Phone = req.Phone.Trim(),
            Email = req.Email?.Trim(),
            Services = services,
            Destination = req.Destination?.Trim(),
            TravelFrom = req.TravelFrom,
            TravelTo = req.TravelTo,
            People = req.People,
            BudgetCents = req.BudgetCents,
            Message = req.Message?.Trim(),
            Status = EnquiryStatus.New,
            CreatedAt = clock.UtcNow,
            UpdatedAt = clock.UtcNow,
        };
        db.Enquiries.Add(e);
        await db.SaveChangesAsync(ct);

        await notifications.NotifyAdminsAsync("new_enquiry", $"New enquiry from {e.Name}",
            $"{e.Name} ({e.Phone}) asked about: {string.Join(", ", e.Services)}. Destination: {e.Destination ?? "-"}. Open the admin panel to reply.", ct);
        return e.Id;
    }

    public async Task<PagedResult<EnquiryDto>> ListAsync(string? status, string? service, int? page, int? pageSize, CancellationToken ct)
    {
        var (p, size) = Paging.Normalise(page, pageSize);
        var q = db.Enquiries.AsNoTracking().AsQueryable();
        if (!string.IsNullOrWhiteSpace(status)) q = q.Where(e => e.Status == status);
        if (!string.IsNullOrWhiteSpace(service)) q = q.Where(e => e.Services.Contains(service));
        var total = await q.CountAsync(ct);
        var items = await q.OrderByDescending(e => e.CreatedAt).Skip((p - 1) * size).Take(size).ToListAsync(ct);
        return new PagedResult<EnquiryDto>(items.Select(ToDto).ToList(), p, size, total);
    }

    public async Task<EnquiryDto> UpdateAsync(Guid id, EnquiryUpdateRequest req, CancellationToken ct)
    {
        if (!EnquiryStatus.All.Contains(req.Status)) throw new BusinessRuleException("Status must be new, contacted, quoted or closed.", 400);
        var e = await db.Enquiries.FirstOrDefaultAsync(x => x.Id == id, ct) ?? throw new NotFoundException("Enquiry");
        e.Status = req.Status;
        e.StaffNotes = req.StaffNotes;
        e.UpdatedAt = clock.UtcNow;
        audit.Log("enquiry.updated", "enquiry", id, new { e.Status });
        await db.SaveChangesAsync(ct);
        return ToDto(e);
    }

    private static EnquiryDto ToDto(Enquiry e) => new(e.Id, e.Name, e.Phone, e.Email, e.Services, e.Destination, e.TravelFrom,
        e.TravelTo, e.People, e.BudgetCents, e.Message, e.Status, e.StaffNotes, e.CreatedAt,
        Mapping.WhatsappLink(e.Phone, $"Hi {Mapping.FirstName(e.Name)}, this is Owen Tours and Travel following up on your enquiry."));
}

// ============================ Company, profile and staff ============================

public sealed class CompanyService(IAppDbContext db, IClock clock, ICurrentUser currentUser, AuditLogger audit, IAuthAdmin authAdmin)
{
    public async Task<CompanyDto> GetAsync(CancellationToken ct)
    {
        var c = await db.CompanySettings.AsNoTracking().FirstOrDefaultAsync(ct) ?? new CompanySettings { CompanyName = "Owen Tours and Travel" };
        return ToDto(c);
    }

    public async Task<CompanyDto> UpdateAsync(CompanyUpdateRequest r, CancellationToken ct)
    {
        var c = await db.CompanySettings.FirstOrDefaultAsync(ct);
        if (c is null)
        {
            c = new CompanySettings { Id = 1 };
            db.CompanySettings.Add(c);
        }
        c.CompanyName = r.CompanyName.Trim();
        c.RegisteredName = r.RegisteredName?.Trim();
        c.Tagline = r.Tagline?.Trim();
        c.Phone = r.Phone?.Trim();
        c.Whatsapp = r.Whatsapp?.Trim();
        c.Email = r.Email?.Trim();
        c.Address = r.Address?.Trim();
        c.FacebookUrl = r.FacebookUrl;
        c.InstagramUrl = r.InstagramUrl;
        c.TiktokUrl = r.TiktokUrl;
        c.AboutText = r.AboutText?.Trim();
        c.UpdatedAt = clock.UtcNow;
        audit.Log("company.updated", "company_settings", 1, new { c.CompanyName, c.Phone, c.Email });
        await db.SaveChangesAsync(ct);
        return ToDto(c);
    }

    public async Task<MeDto> MeAsync(CancellationToken ct)
    {
        var id = currentUser.RequireUserId();
        var p = await db.Profiles.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct) ?? throw new NotFoundException("Profile");
        return new MeDto(p.Id, p.FullName, p.Phone, p.Role, currentUser.Email);
    }

    public async Task<MeDto> UpdateMeAsync(UpdateMeRequest r, CancellationToken ct)
    {
        var id = currentUser.RequireUserId();
        var p = await db.Profiles.FirstOrDefaultAsync(x => x.Id == id, ct) ?? throw new NotFoundException("Profile");
        p.FullName = r.FullName.Trim();
        p.Phone = r.Phone?.Trim();
        p.UpdatedAt = clock.UtcNow;
        await db.SaveChangesAsync(ct);
        return new MeDto(p.Id, p.FullName, p.Phone, p.Role, currentUser.Email);
    }

    public async Task<IReadOnlyList<StaffDto>> StaffAsync(CancellationToken ct) =>
        await db.Profiles.AsNoTracking().Where(p => p.Role == Roles.Admin).OrderBy(p => p.FullName)
            .Select(p => new StaffDto(p.Id, p.FullName, p.Phone, p.CreatedAt)).ToListAsync(ct);

    /// <summary>Only an existing admin can create another admin. Nobody can sign up as admin.</summary>
    public async Task<StaffDto> InviteStaffAsync(StaffInviteRequest r, CancellationToken ct)
    {
        var userId = await authAdmin.InviteUserAsync(r.Email.Trim().ToLowerInvariant(), r.FullName.Trim(), ct);
        var p = await db.Profiles.FirstOrDefaultAsync(x => x.Id == userId, ct);
        if (p is null)
        {
            p = new Profile { Id = userId, FullName = r.FullName.Trim(), CreatedAt = clock.UtcNow };
            db.Profiles.Add(p);
        }
        p.Role = Roles.Admin;
        p.UpdatedAt = clock.UtcNow;
        audit.Log("staff.invited", "profile", userId, new { email = r.Email });
        await db.SaveChangesAsync(ct);
        return new StaffDto(p.Id, p.FullName, p.Phone, p.CreatedAt);
    }

    public async Task RemoveStaffAsync(Guid id, CancellationToken ct)
    {
        if (id == currentUser.UserId) throw new BusinessRuleException("You can't remove your own admin access.", 409);
        var p = await db.Profiles.FirstOrDefaultAsync(x => x.Id == id, ct) ?? throw new NotFoundException("Staff member");
        if (await db.Profiles.CountAsync(x => x.Role == Roles.Admin, ct) <= 1)
            throw new BusinessRuleException("There must always be at least one admin.", 409);
        p.Role = Roles.Customer;
        p.UpdatedAt = clock.UtcNow;
        audit.Log("staff.removed", "profile", id);
        await db.SaveChangesAsync(ct);
    }

    private static CompanyDto ToDto(CompanySettings c) => new(c.CompanyName, c.RegisteredName, c.Tagline, c.Phone, c.Whatsapp,
        c.Email, c.Address, c.FacebookUrl, c.InstagramUrl, c.TiktokUrl, c.AboutText,
        string.IsNullOrWhiteSpace(c.Whatsapp) ? null : Mapping.WhatsappLink(c.Whatsapp, "Hi Owen Tours, I'd like to know more about your trips."),
        string.IsNullOrWhiteSpace(c.Phone) ? null : $"tel:{c.Phone}");
}

// ============================ Reviews ============================

public sealed class ReviewService(IAppDbContext db, IClock clock, ICurrentUser currentUser)
{
    public async Task<IReadOnlyList<ReviewDto>> ForTripAsync(Guid tripId, CancellationToken ct)
    {
        var list = await db.Reviews.AsNoTracking().Include(r => r.Customer)
            .Where(r => r.TripId == tripId).OrderByDescending(r => r.CreatedAt).Take(50).ToListAsync(ct);
        return list.Select(r => new ReviewDto(r.Id, r.Rating, r.Comment, Mapping.FirstName(r.Customer?.FullName ?? ""), r.CreatedAt)).ToList();
    }

    /// <summary>Only travellers who went on the trip (paid or confirmed booking, trip already ended) can review it, once.</summary>
    public async Task<ReviewDto> CreateAsync(Guid tripId, ReviewRequest req, CancellationToken ct)
    {
        var userId = currentUser.RequireUserId();
        var today = SaTime.DateInSa(clock.UtcNow);
        var travelled = await db.Bookings.AnyAsync(b =>
            b.CustomerId == userId && b.Departure!.TripId == tripId
            && (b.Status == BookingStatus.Paid || b.Status == BookingStatus.Confirmed)
            && b.Departure.ReturnDate < today, ct);
        if (!travelled) throw new BusinessRuleException("You can review a trip after you've travelled with us.", 403);
        if (await db.Reviews.AnyAsync(r => r.TripId == tripId && r.CustomerId == userId, ct))
            throw new BusinessRuleException("You've already reviewed this trip. Thank you!", 409);

        var review = new Review { TripId = tripId, CustomerId = userId, Rating = req.Rating, Comment = req.Comment?.Trim(), CreatedAt = clock.UtcNow };
        db.Reviews.Add(review);
        await db.SaveChangesAsync(ct);
        var name = await db.Profiles.Where(p => p.Id == userId).Select(p => p.FullName).FirstOrDefaultAsync(ct) ?? "";
        return new ReviewDto(review.Id, review.Rating, review.Comment, Mapping.FirstName(name), review.CreatedAt);
    }
}

// ============================ Dashboard ============================

public sealed class DashboardService(IAppDbContext db, IClock clock)
{
    public async Task<DashboardDto> GetAsync(CancellationToken ct)
    {
        var now = clock.UtcNow;
        var today = SaTime.DateInSa(now);
        var monthStart = SaTime.StartOfDayUtc(new DateOnly(today.Year, today.Month, 1));

        var revenue = await db.Payments
            .Where(p => p.Status == PaymentStatus.Complete && p.PaidAt >= monthStart)
            .SumAsync(p => (int?)p.AmountCents, ct) ?? 0;
        var bookingsThisMonth = await db.Bookings.CountAsync(b => b.CreatedAt >= monthStart
            && (b.Status == BookingStatus.Confirmed || b.Status == BookingStatus.Paid), ct);
        var active = await db.Bookings.CountAsync(b => b.Status == BookingStatus.Confirmed || b.Status == BookingStatus.Paid, ct);
        var overdueCount = await db.Instalments.CountAsync(i => i.Status == InstalmentStatus.Overdue, ct);
        var overdueAmount = await db.Instalments.Where(i => i.Status == InstalmentStatus.Overdue).SumAsync(i => (int?)i.AmountCents, ct) ?? 0;
        var newEnquiries = await db.Enquiries.CountAsync(e => e.Status == EnquiryStatus.New, ct);
        var pendingIds = await db.BookingDiscounts.CountAsync(d => d.Status == DiscountStatus.PendingVerification && d.StudentIdImagePath != null, ct);
        var pendingRefunds = await db.Bookings.CountAsync(b => b.RefundStatus == RefundStatus.Pending, ct);

        var upcoming = await db.Departures.AsNoTracking()
            .Where(d => d.DepartureAt > now && !d.IsCancelledByCompany)
            .OrderBy(d => d.DepartureAt)
            .Take(12)
            .Select(d => new
            {
                d.Id, d.Trip!.Title, d.DepartureAt, d.DepartureArea, d.DepartureProvince, d.Capacity, d.SeatsBooked,
                Bookings = db.Bookings.Count(b => b.DepartureId == d.Id && (b.Status == BookingStatus.Confirmed || b.Status == BookingStatus.Paid)),
            })
            .ToListAsync(ct);

        return new DashboardDto(revenue, bookingsThisMonth, active, overdueCount, overdueAmount, newEnquiries, pendingIds, pendingRefunds,
            upcoming.Select(u => new DepartureStatDto(u.Id, u.Title, u.DepartureAt, $"{u.DepartureArea}, {u.DepartureProvince}",
                u.Capacity, u.SeatsBooked, Math.Max(u.Capacity - u.SeatsBooked, 0), u.Bookings)).ToList());
    }
}
