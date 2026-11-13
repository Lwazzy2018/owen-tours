using Microsoft.EntityFrameworkCore;
using OwenTours.Application.Abstractions;
using OwenTours.Application.Common;
using OwenTours.Application.Dtos;
using OwenTours.Domain.Common;
using OwenTours.Domain.Entities;
using OwenTours.Domain.Rules;

namespace OwenTours.Application.Services;

public sealed class DepartureService(IAppDbContext db, IClock clock, AuditLogger audit)
{
    public async Task<DepartureDto> CreateAsync(Guid tripId, DepartureUpsertRequest req, CancellationToken ct)
    {
        if (!await db.Trips.AnyAsync(t => t.Id == tripId, ct)) throw new NotFoundException("Trip");
        var d = new Departure { TripId = tripId, CreatedAt = clock.UtcNow, UpdatedAt = clock.UtcNow };
        Apply(d, req);

        var result = DepartureRules.ValidateAndNormalise(d, clock.UtcNow, isNew: true);
        if (!result.IsValid) throw BusinessRuleException.From(result);

        db.Departures.Add(d);
        audit.Log("departure.created", "departure", d.Id, Snapshot(d));
        await db.SaveChangesAsync(ct);
        return Mapping.ToDto(d, clock.UtcNow);
    }

    public async Task<DepartureDto> UpdateAsync(Guid tripId, Guid departureId, DepartureUpsertRequest req, CancellationToken ct)
    {
        var d = await db.Departures.FirstOrDefaultAsync(x => x.Id == departureId && x.TripId == tripId, ct)
                ?? throw new NotFoundException("Departure");
        var before = Snapshot(d);
        Apply(d, req);
        d.UpdatedAt = clock.UtcNow;

        var result = DepartureRules.ValidateAndNormalise(d, clock.UtcNow, isNew: false);
        if (!result.IsValid) throw BusinessRuleException.From(result);

        // Existing bookings keep the cancellation policy they agreed to (it's saved on each booking).
        audit.Log("departure.updated", "departure", d.Id, new { before, after = Snapshot(d) });
        await db.SaveChangesAsync(ct);
        return Mapping.ToDto(d, clock.UtcNow);
    }

    /// <summary>Copies the cancellation policy from another departure into a request, for the admin form.</summary>
    public async Task<object> PolicyFromAsync(Guid departureId, CancellationToken ct)
    {
        var d = await db.Departures.AsNoTracking().FirstOrDefaultAsync(x => x.Id == departureId, ct)
                ?? throw new NotFoundException("Departure");
        var days = d.CancellationDeadline is null
            ? (int?)null
            : SaTime.DateInSa(d.DepartureAt).DayNumber - SaTime.DateInSa(d.CancellationDeadline.Value).DayNumber;
        return new
        {
            d.IsCancellable,
            cancellationDaysBefore = days,
            d.RefundType,
            d.RefundPercent,
            d.DepositRefundable,
            d.CancellationNotes,
        };
    }

    private static void Apply(Departure d, DepartureUpsertRequest r)
    {
        d.DepartureProvince = r.DepartureProvince.Trim();
        d.DepartureArea = r.DepartureArea.Trim();
        d.MeetingPlace = r.MeetingPlace.Trim();
        d.DepartureAt = r.DepartureAt.ToUniversalTime();
        d.ReturnDate = r.ReturnDate;
        d.Capacity = r.Capacity;
        d.AdultPriceCents = r.AdultPriceCents;
        d.ChildPriceCents = r.ChildPriceCents;
        d.BookingDeadline = r.BookingDeadline.ToUniversalTime();
        d.AllowInstalments = r.AllowInstalments;
        d.DepositCents = r.DepositCents;
        d.FinalPaymentDue = r.FinalPaymentDue;
        d.IsCancellable = r.IsCancellable;
        d.CancellationDeadline = r.CancellationDaysBefore is not null
            ? DepartureRules.DeadlineFromDaysBefore(d.DepartureAt, r.CancellationDaysBefore.Value)
            : r.CancellationDeadline?.ToUniversalTime();
        d.RefundType = r.RefundType;
        d.RefundPercent = r.RefundPercent;
        d.DepositRefundable = r.DepositRefundable;
        d.CancellationNotes = string.IsNullOrWhiteSpace(r.CancellationNotes) ? null : r.CancellationNotes.Trim();
        d.IsCancelledByCompany = r.IsCancelledByCompany;
    }

    private static object Snapshot(Departure d) => new
    {
        d.DepartureProvince, d.DepartureArea, d.MeetingPlace, d.DepartureAt, d.Capacity,
        d.AdultPriceCents, d.ChildPriceCents, d.DepositCents, d.AllowInstalments,
        d.IsCancellable, d.CancellationDeadline, d.RefundType, d.RefundPercent, d.DepositRefundable,
        d.IsCancelledByCompany,
    };
}
