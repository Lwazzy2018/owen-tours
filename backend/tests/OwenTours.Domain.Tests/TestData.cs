using OwenTours.Domain.Common;
using OwenTours.Domain.Entities;
using OwenTours.Domain.Rules;

namespace OwenTours.Domain.Tests;

internal static class TestData
{
    public static readonly Guid LesothoTripId = Guid.Parse("11111111-0000-4000-8000-000000000001");
    public static readonly Guid OtherTripId = Guid.Parse("11111111-0000-4000-8000-000000000099");

    /// <summary>10 Nov 2026, 12:00 SAST</summary>
    public static readonly DateTimeOffset Now = new(2026, 11, 10, 12, 0, 0, SaTime.Offset);

    public static DateTimeOffset Sast(int y, int m, int d, int h = 0, int min = 0, int s = 0) =>
        new DateTimeOffset(y, m, d, h, min, s, SaTime.Offset).ToUniversalTime();

    public static Departure Lesotho() => new()
    {
        Id = Guid.NewGuid(),
        TripId = LesothoTripId,
        DepartureProvince = "Mpumalanga",
        DepartureArea = "Mbombela",
        MeetingPlace = "Riverside Mall, main entrance",
        DepartureAt = Sast(2027, 7, 9, 4),
        ReturnDate = new DateOnly(2027, 7, 11),
        Capacity = 30,
        AdultPriceCents = 460000,
        ChildPriceCents = 460000,
        BookingDeadline = Sast(2027, 6, 25, 23, 59),
        AllowInstalments = true,
        DepositCents = 100000,
        FinalPaymentDue = new DateOnly(2027, 6, 30),
        IsCancellable = true,
        CancellationDeadline = Sast(2027, 6, 25, 23, 59),
        RefundType = RefundType.Full,
        DepositRefundable = false,
    };

    public static PolicySnapshot Policy(bool cancellable = true, string refund = RefundType.Full, int? percent = null,
        bool depositRefundable = false, DateTimeOffset? deadline = null) => new()
    {
        IsCancellable = cancellable,
        CancellationDeadline = cancellable ? deadline ?? Sast(2026, 12, 1, 23, 59) : null,
        RefundType = refund,
        RefundPercent = percent,
        DepositRefundable = depositRefundable,
    };

    public static DiscountCandidate Special(string type, int percent, Guid? tripId = null, int? minTravellers = null,
        string? code = null, int? maxUses = null, int used = 0, bool active = true,
        DateTimeOffset? starts = null, DateTimeOffset? ends = null, Guid? id = null) =>
        new(id ?? Guid.NewGuid(), type + " special", type, percent, minTravellers, code, maxUses, used,
            starts ?? Sast(2026, 11, 1), ends ?? Sast(2026, 12, 31, 23, 59), active,
            [tripId ?? LesothoTripId]);

    public static TravellerInput Adult(string name = "Thandi Mokoena", string? id = "8001015009087",
        string? passport = null, DateOnly? expiry = null, DateOnly? dob = null) =>
        new(name, id, passport, expiry, "0820000000", false, dob, null, null, null);

    public static TravellerInput Learner(string name = "Lwazi Learner", int grade = 10, string? medical = "None",
        string? allergies = "None", DateOnly? dob = null) =>
        new(name, null, "A12345678", null, null, true, dob ?? new DateOnly(2011, 3, 4), grade, medical, allergies);

    public static GuardianInput Guardian(bool consent = true) =>
        new("Nomsa Learner", "0821111111", "Mother", "Sipho Learner", "0822222222", consent);
}
