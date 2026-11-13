namespace OwenTours.Domain.Common;

// String values match the CHECK constraints in the database exactly.

public static class Roles
{
    public const string Admin = "admin";
    public const string Customer = "customer";
}

public static class BookingStatus
{
    public const string Pending = "pending";
    public const string Confirmed = "confirmed";
    public const string Paid = "paid";
    public const string Cancelled = "cancelled";
    public const string Expired = "expired";

    public static bool IsActive(string status) => status is Pending or Confirmed or Paid;
}

public static class PaymentPlan
{
    public const string Full = "full";
    public const string Instalments = "instalments";
}

public static class PaymentPurpose
{
    public const string Full = "full";
    public const string Deposit = "deposit";
    public const string Instalment = "instalment";
    public const string Balance = "balance";
}

public static class PaymentStatus
{
    public const string Pending = "pending";
    public const string Complete = "complete";
    public const string Failed = "failed";
    public const string Cancelled = "cancelled";
}

public static class InstalmentStatus
{
    public const string Due = "due";
    public const string Paid = "paid";
    public const string Overdue = "overdue";
    public const string Cancelled = "cancelled";
}

public static class RefundType
{
    public const string Full = "full";
    public const string Partial = "partial";
    public const string None = "none";
}

public static class RefundStatus
{
    public const string None = "none";
    public const string Pending = "pending";
    public const string Refunded = "refunded";
}

public static class Audience
{
    public const string Everyone = "everyone";
    public const string AdultsOnly = "adults_only";
    public const string HighSchool = "high_school";
}

public static class SpecialType
{
    public const string Percentage = "percentage";
    public const string Student = "student";
    public const string Group = "group";
    public const string PromoCode = "promo_code";
}

public static class DiscountStatus
{
    public const string Applied = "applied";
    public const string PendingVerification = "pending_verification";
    public const string Rejected = "rejected";
}

public static class EnquiryStatus
{
    public const string New = "new";
    public const string Contacted = "contacted";
    public const string Quoted = "quoted";
    public const string Closed = "closed";

    public static readonly string[] All = [New, Contacted, Quoted, Closed];
}

public static class EnquiryServices
{
    public static readonly string[] All =
        ["flights", "accommodation", "tour_package", "visa", "travel_insurance", "consultation"];
}

public static class Provinces
{
    public static readonly string[] All =
    [
        "Eastern Cape", "Free State", "Gauteng", "KwaZulu-Natal", "Limpopo",
        "Mpumalanga", "North West", "Northern Cape", "Western Cape",
    ];
}

public static class TripCategories
{
    public static readonly string[] All =
        ["beach", "weekend_getaway", "hiking", "snow", "city", "safari", "cross_border", "youth_camp", "day_trip", "other"];
}

public static class BookingRules
{
    /// <summary>How long a pending booking holds its seats while the customer pays.</summary>
    public static readonly TimeSpan SeatHold = TimeSpan.FromMinutes(20);

    /// <summary>Most instalments a booking can be split into (after the deposit).</summary>
    public const int MaxInstalments = 12;

    /// <summary>Passports expiring within this many months of the return date get a warning.</summary>
    public const int PassportWarningMonths = 6;

    public const int AdultAge = 18;
}
