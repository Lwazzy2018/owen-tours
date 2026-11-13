using OwenTours.Application.Dtos;
using OwenTours.Domain.Common;
using OwenTours.Domain.Entities;
using OwenTours.Domain.Rules;

namespace OwenTours.Application.Services;

public static class Mapping
{
    public static string MealsSummary(Trip t)
    {
        var meals = new List<string>();
        if (t.MealsBreakfast) meals.Add("Breakfast");
        if (t.MealsLunch) meals.Add("Lunch");
        if (t.MealsDinner) meals.Add("Dinner");
        if (t.MealsSnacks) meals.Add("Snacks");
        if (meals.Count == 0) return "No meals included";
        if (meals.Count == 1) return meals[0];
        return string.Join(", ", meals.Take(meals.Count - 1)) + " & " + meals[^1];
    }

    public static WhatsIncludedDto Included(Trip t) => new(
        t.TransportIncluded, t.TransportType, t.TransportNotes,
        t.MealsBreakfast, t.MealsLunch, t.MealsDinner, t.MealsSnacks, t.MealsNotes, MealsSummary(t),
        t.AccommodationIncluded, t.AccommodationType, t.AccommodationNotes,
        t.Includes, t.Excludes);

    public static DepartureDto ToDto(Departure d, DateTimeOffset now)
    {
        var policy = PolicySnapshot.FromDeparture(d);
        return new DepartureDto(
            d.Id, d.TripId, d.DepartureProvince, d.DepartureArea, d.MeetingPlace, d.DepartureAt, d.ReturnDate,
            d.Capacity, d.SeatsBooked, d.SeatsLeft, d.AdultPriceCents, d.ChildPriceCents, d.BookingDeadline,
            BookingOpen: !d.IsCancelledByCompany && now <= d.BookingDeadline && d.SeatsLeft > 0,
            d.AllowInstalments, d.DepositCents, d.FinalPaymentDue,
            d.IsCancellable, d.CancellationDeadline, d.RefundType, d.RefundPercent, d.DepositRefundable, d.CancellationNotes,
            CancellationRules.Describe(policy), CancellationRules.Badge(policy), d.IsCancelledByCompany);
    }

    public static string DepartsFrom(Departure d) => $"{d.DepartureArea}, {d.DepartureProvince}";

    public static TripSummaryDto ToSummary(Trip t, IReadOnlyList<Departure> upcoming, Special? bestSpecial)
    {
        var next = upcoming.OrderBy(d => d.DepartureAt).FirstOrDefault();
        return new TripSummaryDto(
            t.Id, t.Title, t.Destination, t.DestinationCountry, t.IsCrossBorderTrip, t.Category, t.Audience, t.Tagline,
            t.CoverImageUrl ?? t.Images.OrderBy(i => i.SortOrder).Select(i => i.ThumbnailUrl ?? i.Url).FirstOrDefault(),
            FromPriceCents: upcoming.Count == 0 ? null : upcoming.Min(d => d.AdultPriceCents),
            NextDepartureAt: next?.DepartureAt,
            SeatsLeftNext: next?.SeatsLeft,
            DepartsFrom: upcoming.Select(DepartsFrom).Distinct().ToList(),
            t.TransportIncluded, MealsSummary(t), t.AccommodationIncluded,
            CancellationBadge: next is null ? null : CancellationRules.Badge(PolicySnapshot.FromDeparture(next)),
            SpecialBadge: bestSpecial is null ? null : $"{bestSpecial.PercentOff}% off – {bestSpecial.Name}",
            t.IsPublished);
    }

    public static string? Mask(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var v = value.Trim();
        return v.Length <= 4 ? new string('•', v.Length) : new string('•', v.Length - 4) + v[^4..];
    }

    public static string WhatsappLink(string? phone, string? text = null)
    {
        var digits = new string((phone ?? "").Where(char.IsAsciiDigit).ToArray());
        if (digits.StartsWith('0')) digits = "27" + digits[1..];
        var link = $"https://wa.me/{digits}";
        return string.IsNullOrEmpty(text) ? link : $"{link}?text={Uri.EscapeDataString(text)}";
    }

    public static string FirstName(string fullName)
    {
        var first = fullName.Trim().Split(' ', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
        return string.IsNullOrEmpty(first) ? "Traveller" : first;
    }

    public static TravellerDto ToDto(Traveller t, bool showFullDocuments) => new(
        t.Id, t.FullName,
        showFullDocuments ? t.IdNumber : Mask(t.IdNumber),
        showFullDocuments ? t.PassportNumber : Mask(t.PassportNumber),
        t.PassportExpiry, t.Phone, t.IsChild, t.DateOfBirth, t.SchoolGrade, t.MedicalNotes, t.Allergies);

    public static BookingDto ToDto(Booking b, DateTimeOffset now, bool isAdmin, bool canReview)
    {
        var d = b.Departure ?? throw new InvalidOperationException("Departure not loaded.");
        var t = d.Trip ?? throw new InvalidOperationException("Trip not loaded.");
        var policy = PolicySnapshot.FromJson(b.CancellationPolicySnapshot);
        var check = CancellationRules.CanCustomerCancel(policy, b.Status, now);

        return new BookingDto(
            b.Id, b.Reference, b.Status, b.PaymentPlan, t.Id, t.Title, t.CoverImageUrl, t.IsCrossBorderTrip, t.Audience,
            Included(t), ToDto(d, now),
            b.Adults, b.Children, b.SubtotalCents, b.DiscountCents, b.TotalCents, b.DepositCents, b.AmountPaidCents, b.BalanceCents,
            b.ExpiresAt, CancellationRules.Describe(policy), check.Allowed, check.Allowed ? null : check.Reason,
            policy.CancellationDeadline, b.CancelledAt, b.CancellationReason, b.RefundCents, b.RefundStatus,
            b.Travellers.OrderBy(x => x.CreatedAt).ThenBy(x => x.FullName).Select(x => ToDto(x, isAdmin)).ToList(),
            b.Guardian is null ? null : new GuardianDto(b.Guardian.GuardianName, b.Guardian.GuardianPhone,
                b.Guardian.GuardianRelationship, b.Guardian.EmergencyContactName, b.Guardian.EmergencyContactPhone,
                b.Guardian.ConsentGivenAt),
            b.Discount is null ? null : new BookingDiscountDto(b.Discount.Id, b.Discount.SpecialName, b.Discount.PercentOff,
                b.Discount.DiscountCents, b.Discount.Status, b.Discount.ReviewNote, b.Discount.StudentIdImagePath is not null),
            b.Instalments.OrderBy(i => i.Sequence)
                .Select(i => new InstalmentDto(i.Id, i.Sequence, i.DueDate, i.AmountCents, i.Status, i.PaidAt)).ToList(),
            b.Payments.Where(p => isAdmin || p.Status != PaymentStatus.Pending).OrderBy(p => p.CreatedAt)
                .Select(p => new PaymentDto(p.Id, p.Purpose, p.AmountCents, p.Status, p.CreatedAt, p.PaidAt)).ToList(),
            b.Customer?.FullName ?? "", b.Customer?.Phone, canReview, b.CreatedAt);
    }

    public static BookingSummaryDto ToSummary(Booking b)
    {
        var d = b.Departure!;
        var next = b.Instalments
            .Where(i => i.Status is InstalmentStatus.Due or InstalmentStatus.Overdue)
            .OrderBy(i => i.Sequence)
            .FirstOrDefault();
        return new BookingSummaryDto(
            b.Id, b.Reference, b.Status, d.Trip?.Title ?? "", d.TripId, d.Trip?.CoverImageUrl, d.DepartureAt, DepartsFrom(d),
            b.TravellerCount, b.TotalCents, b.AmountPaidCents, next?.DueDate, next?.AmountCents,
            b.Customer?.FullName ?? "", b.CreatedAt, b.RefundStatus);
    }

    public static SpecialDto ToDto(Special s) => new(
        s.Id, s.Name, s.Description, s.Type, s.PercentOff, s.MinTravellers, s.PromoCode, s.IsPublic, s.MaxUses,
        s.TimesUsed, s.StartsAt, s.EndsAt, s.IsActive, s.BannerImageUrl, s.SpecialTrips.Select(x => x.TripId).ToList());

    public static DiscountCandidate ToCandidate(Special s) => new(
        s.Id, s.Name, s.Type, s.PercentOff, s.MinTravellers, s.PromoCode, s.MaxUses, s.TimesUsed,
        s.StartsAt, s.EndsAt, s.IsActive, s.SpecialTrips.Select(x => x.TripId).ToList());
}
