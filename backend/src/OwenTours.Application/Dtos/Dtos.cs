using System.ComponentModel.DataAnnotations;

namespace OwenTours.Application.Dtos;

// All money is in cents (integers). All timestamps are ISO-8601 UTC; dates are yyyy-MM-dd.

// ============================ Trips ============================

public sealed record WhatsIncludedDto(
    bool TransportIncluded,
    string? TransportType,
    string? TransportNotes,
    bool Breakfast,
    bool Lunch,
    bool Dinner,
    bool Snacks,
    string? MealsNotes,
    string MealsSummary,
    bool AccommodationIncluded,
    string? AccommodationType,
    string? AccommodationNotes,
    IReadOnlyList<string> OtherIncludes,
    IReadOnlyList<string> Excludes);

public sealed record TripSummaryDto(
    Guid Id,
    string Title,
    string Destination,
    string DestinationCountry,
    bool IsCrossBorder,
    string Category,
    string Audience,
    string? Tagline,
    string? CoverImageUrl,
    int? FromPriceCents,
    DateTimeOffset? NextDepartureAt,
    int? SeatsLeftNext,
    IReadOnlyList<string> DepartsFrom,
    bool TransportIncluded,
    string MealsSummary,
    bool AccommodationIncluded,
    string? CancellationBadge,
    string? SpecialBadge,
    bool IsPublished);

public sealed record TripImageDto(Guid Id, string Url, string? ThumbnailUrl, int SortOrder);

public sealed record ItineraryDayDto(int DayNumber, string Title, string Description);

public sealed record DepartureDto(
    Guid Id,
    Guid TripId,
    string DepartureProvince,
    string DepartureArea,
    string MeetingPlace,
    DateTimeOffset DepartureAt,
    DateOnly ReturnDate,
    int Capacity,
    int SeatsBooked,
    int SeatsLeft,
    int AdultPriceCents,
    int ChildPriceCents,
    DateTimeOffset BookingDeadline,
    bool BookingOpen,
    bool AllowInstalments,
    int DepositCents,
    DateOnly? FinalPaymentDue,
    bool IsCancellable,
    DateTimeOffset? CancellationDeadline,
    string RefundType,
    int? RefundPercent,
    bool DepositRefundable,
    string? CancellationNotes,
    string PolicyText,
    string PolicyBadge,
    bool IsCancelledByCompany);

public sealed record SpecialBadgeDto(Guid Id, string Name, string Type, int PercentOff, int? MinTravellers, string? Description);

public sealed record TripDetailDto(
    Guid Id,
    string Title,
    string Destination,
    string DestinationCountry,
    bool IsCrossBorder,
    string Category,
    string Audience,
    int? MinGrade,
    int? MaxGrade,
    IReadOnlyList<string> Activities,
    string? Tagline,
    string Description,
    string? CoverImageUrl,
    WhatsIncludedDto Included,
    IReadOnlyList<TripImageDto> Images,
    IReadOnlyList<ItineraryDayDto> Itinerary,
    IReadOnlyList<DepartureDto> Departures,
    IReadOnlyList<SpecialBadgeDto> Specials,
    double? AverageRating,
    int ReviewCount,
    bool IsPublished);

public sealed record TripQuery(
    string? Search,
    string? Destination,
    string? Category,
    DateOnly? From,
    DateOnly? To,
    int? MaxPriceCents,
    string? DepartureProvince,
    string? DepartureArea,
    int? Page,
    int? PageSize);

public sealed class TripUpsertRequest
{
    [Required, MaxLength(150)] public string Title { get; set; } = "";
    [Required, MaxLength(150)] public string Destination { get; set; } = "";
    [Required, MaxLength(80)] public string DestinationCountry { get; set; } = "South Africa";
    [Required] public string Category { get; set; } = "other";
    [Required] public string Audience { get; set; } = "everyone";
    [Range(1, 12)] public int? MinGrade { get; set; }
    [Range(1, 12)] public int? MaxGrade { get; set; }
    public List<string> Activities { get; set; } = [];
    [MaxLength(200)] public string? Tagline { get; set; }
    public string Description { get; set; } = "";
    public string? CoverImageUrl { get; set; }

    public bool TransportIncluded { get; set; }
    public string? TransportType { get; set; }
    public string? TransportNotes { get; set; }
    public bool MealsBreakfast { get; set; }
    public bool MealsLunch { get; set; }
    public bool MealsDinner { get; set; }
    public bool MealsSnacks { get; set; }
    public string? MealsNotes { get; set; }
    public bool AccommodationIncluded { get; set; }
    public string? AccommodationType { get; set; }
    public string? AccommodationNotes { get; set; }
    public List<string> Includes { get; set; } = [];
    public List<string> Excludes { get; set; } = [];
    public bool IsPublished { get; set; }
    public List<ItineraryDayDto> Itinerary { get; set; } = [];
}

public sealed class DepartureUpsertRequest
{
    [Required] public string DepartureProvince { get; set; } = "Mpumalanga";
    [Required, MaxLength(100)] public string DepartureArea { get; set; } = "";
    [Required, MaxLength(200)] public string MeetingPlace { get; set; } = "";
    public DateTimeOffset DepartureAt { get; set; }
    public DateOnly ReturnDate { get; set; }
    [Range(1, 1000)] public int Capacity { get; set; }
    [Range(0, int.MaxValue)] public int AdultPriceCents { get; set; }
    [Range(0, int.MaxValue)] public int ChildPriceCents { get; set; }
    public DateTimeOffset BookingDeadline { get; set; }
    public bool AllowInstalments { get; set; }
    [Range(0, int.MaxValue)] public int DepositCents { get; set; }
    public DateOnly? FinalPaymentDue { get; set; }

    public bool IsCancellable { get; set; } = true;
    /// <summary>Either a specific deadline...</summary>
    public DateTimeOffset? CancellationDeadline { get; set; }
    /// <summary>...or "X days before departure" (converted to an exact date and stored as that date).</summary>
    [Range(0, 365)] public int? CancellationDaysBefore { get; set; }
    public string RefundType { get; set; } = "none";
    public int? RefundPercent { get; set; }
    public bool DepositRefundable { get; set; }
    [MaxLength(500)] public string? CancellationNotes { get; set; }
    public bool IsCancelledByCompany { get; set; }
}

public sealed record ImageOrderRequest(IReadOnlyList<Guid> ImageIdsInOrder);

// ============================ Bookings ============================

public sealed class TravellerRequest
{
    [Required, MaxLength(150)] public string FullName { get; set; } = "";
    [MaxLength(20)] public string? IdNumber { get; set; }
    [MaxLength(30)] public string? PassportNumber { get; set; }
    public DateOnly? PassportExpiry { get; set; }
    [MaxLength(30)] public string? Phone { get; set; }
    public bool IsChild { get; set; }
    public DateOnly? DateOfBirth { get; set; }
    [Range(1, 12)] public int? SchoolGrade { get; set; }
    [MaxLength(1000)] public string? MedicalNotes { get; set; }
    [MaxLength(1000)] public string? Allergies { get; set; }
}

public sealed class GuardianRequest
{
    [Required, MaxLength(150)] public string GuardianName { get; set; } = "";
    [Required, MaxLength(30)] public string GuardianPhone { get; set; } = "";
    [Required, MaxLength(50)] public string GuardianRelationship { get; set; } = "";
    [Required, MaxLength(150)] public string EmergencyContactName { get; set; } = "";
    [Required, MaxLength(30)] public string EmergencyContactPhone { get; set; } = "";
    public bool ConsentGiven { get; set; }
}

public sealed class PricePreviewRequest
{
    public Guid DepartureId { get; set; }
    [Range(0, 100)] public int Adults { get; set; }
    [Range(0, 100)] public int Children { get; set; }
    [MaxLength(40)] public string? PromoCode { get; set; }
    public bool WantsStudentDiscount { get; set; }
}

public sealed record PlannedInstalmentDto(int Sequence, DateOnly DueDate, int AmountCents);

public sealed record PricePreviewDto(
    int Adults,
    int Children,
    int AdultPriceCents,
    int ChildPriceCents,
    int SubtotalCents,
    string? DiscountName,
    int? DiscountPercent,
    int DiscountCents,
    bool DiscountPendingVerification,
    int TotalCents,
    int DepositCents,
    int BalanceAfterDepositCents,
    bool InstalmentsAvailable,
    IReadOnlyList<PlannedInstalmentDto> InstalmentPlan,
    string? PromoCodeError,
    string PolicyText,
    int SeatsLeft);

public sealed class CreateBookingRequest
{
    public Guid DepartureId { get; set; }
    [Required] public string PaymentPlan { get; set; } = "full";   // "full" | "instalments"
    [MinLength(1), MaxLength(60)] public List<TravellerRequest> Travellers { get; set; } = [];
    public GuardianRequest? Guardian { get; set; }
    [MaxLength(40)] public string? PromoCode { get; set; }
    public bool WantsStudentDiscount { get; set; }
    public bool AcceptedCancellationPolicy { get; set; }
}

public sealed record TravellerDto(
    Guid Id,
    string FullName,
    string? IdNumberMasked,
    string? PassportNumberMasked,
    DateOnly? PassportExpiry,
    string? Phone,
    bool IsChild,
    DateOnly? DateOfBirth,
    int? SchoolGrade,
    string? MedicalNotes,
    string? Allergies);

public sealed record GuardianDto(
    string GuardianName,
    string GuardianPhone,
    string GuardianRelationship,
    string EmergencyContactName,
    string EmergencyContactPhone,
    DateTimeOffset ConsentGivenAt);

public sealed record InstalmentDto(Guid Id, int Sequence, DateOnly DueDate, int AmountCents, string Status, DateTimeOffset? PaidAt);

public sealed record PaymentDto(Guid Id, string Purpose, int AmountCents, string Status, DateTimeOffset CreatedAt, DateTimeOffset? PaidAt);

public sealed record BookingDiscountDto(Guid Id, string Name, int PercentOff, int DiscountCents, string Status, string? ReviewNote, bool HasStudentId);

public sealed record BookingSummaryDto(
    Guid Id,
    string Reference,
    string Status,
    string TripTitle,
    Guid TripId,
    string? CoverImageUrl,
    DateTimeOffset DepartureAt,
    string DepartsFrom,
    int Travellers,
    int TotalCents,
    int AmountPaidCents,
    DateOnly? NextDueDate,
    int? NextDueCents,
    string CustomerName,
    DateTimeOffset CreatedAt,
    string RefundStatus);

public sealed record BookingDto(
    Guid Id,
    string Reference,
    string Status,
    string PaymentPlan,
    Guid TripId,
    string TripTitle,
    string? CoverImageUrl,
    bool IsCrossBorder,
    string Audience,
    WhatsIncludedDto Included,
    DepartureDto Departure,
    int Adults,
    int Children,
    int SubtotalCents,
    int DiscountCents,
    int TotalCents,
    int DepositCents,
    int AmountPaidCents,
    int BalanceCents,
    DateTimeOffset? ExpiresAt,
    string PolicyText,
    bool CanCancel,
    string? CannotCancelReason,
    DateTimeOffset? CancellationDeadline,
    DateTimeOffset? CancelledAt,
    string? CancellationReason,
    int RefundCents,
    string RefundStatus,
    IReadOnlyList<TravellerDto> Travellers,
    GuardianDto? Guardian,
    BookingDiscountDto? Discount,
    IReadOnlyList<InstalmentDto> Instalments,
    IReadOnlyList<PaymentDto> Payments,
    string CustomerName,
    string? CustomerPhone,
    bool CanReview,
    DateTimeOffset CreatedAt);

public sealed record CreateBookingResponse(BookingDto Booking, IReadOnlyList<string> Warnings);

public sealed record CancelPreviewDto(bool Allowed, string? Reason, DateTimeOffset? Deadline, int AmountPaidCents, int RefundCents, string PolicyText);

public sealed class CancelRequest
{
    [MaxLength(500)] public string? Reason { get; set; }
}

public sealed class AdminCancelRequest
{
    [Required, MinLength(3), MaxLength(500)] public string Reason { get; set; } = "";
    /// <summary>Leave empty to use the policy's refund amount.</summary>
    [Range(0, int.MaxValue)] public int? RefundCentsOverride { get; set; }
}

public sealed class AdminBookingStatusRequest
{
    /// <summary>"confirm" (e.g. cash/EFT received outside the app) is the only manual change; cancel has its own endpoint.</summary>
    [Required] public string Action { get; set; } = "";
    [Range(1, int.MaxValue)] public int? AmountReceivedCents { get; set; }
    [MaxLength(500)] public string? Note { get; set; }
}

public sealed class PayRequest
{
    [Required] public string Type { get; set; } = "full";   // full | deposit | next_instalment | balance
}

public sealed record PaymentRedirectDto(Guid PaymentId, int AmountCents, string Url, IReadOnlyDictionary<string, string> FormFields)
{
    /// <summary>Open this in a WebView/browser: it forwards to the payment page.</summary>
    public string? CheckoutUrl { get; init; }
}

public sealed class DiscountReviewRequest
{
    public bool Approve { get; set; }
    [MaxLength(500)] public string? Note { get; set; }
}

public sealed record PendingDiscountDto(
    Guid Id,
    Guid BookingId,
    string BookingReference,
    string CustomerName,
    string SpecialName,
    int PercentOff,
    int DiscountCents,
    string? StudentIdUrl,
    DateTimeOffset CreatedAt);

public sealed record BookingQuery(Guid? TripId, Guid? DepartureId, string? Status, string? DepartureProvince, string? DepartureArea,
    string? Search, int? Page, int? PageSize);

// ============================ Reviews ============================

public sealed class ReviewRequest
{
    [Range(1, 5)] public int Rating { get; set; }
    [MaxLength(1000)] public string? Comment { get; set; }
}

public sealed record ReviewDto(Guid Id, int Rating, string? Comment, string CustomerFirstName, DateTimeOffset CreatedAt);

// ============================ Past trips ============================

public sealed record PastTripMediaDto(Guid Id, string MediaType, string Url, string? ThumbnailUrl, string? Caption, int SortOrder);

public sealed record TestimonialDto(Guid Id, string CustomerName, string Quote, int? Rating, string? PhotoUrl, bool IsPublished);

public sealed record PastTripSummaryDto(Guid Id, Guid? TripId, string Title, string Destination, DateOnly TravelledOn,
    int? TravellerCount, string? CoverUrl, bool IsFeatured, bool IsPublished, int MediaCount);

public sealed record PastTripDetailDto(Guid Id, Guid? TripId, string Title, string Destination, DateOnly TravelledOn,
    int? TravellerCount, string? Story, string? CoverUrl, bool IsFeatured, bool IsPublished, int SortOrder,
    IReadOnlyList<PastTripMediaDto> Media, IReadOnlyList<TestimonialDto> Testimonials, bool HasUpcomingTrip);

public sealed class PastTripUpsertRequest
{
    public Guid? TripId { get; set; }
    [Required, MaxLength(150)] public string Title { get; set; } = "";
    [Required, MaxLength(150)] public string Destination { get; set; } = "";
    public DateOnly TravelledOn { get; set; }
    [Range(0, 10000)] public int? TravellerCount { get; set; }
    [MaxLength(5000)] public string? Story { get; set; }
    public string? CoverUrl { get; set; }
    public bool IsFeatured { get; set; }
    public bool IsPublished { get; set; }
    public int SortOrder { get; set; }
}

public sealed record MediaOrderItem(Guid Id, int SortOrder, string? Caption);

public sealed class TestimonialRequest
{
    [Required, MaxLength(100)] public string CustomerName { get; set; } = "";
    [Required, MaxLength(1000)] public string Quote { get; set; } = "";
    [Range(1, 5)] public int? Rating { get; set; }
    public string? PhotoUrl { get; set; }
    public bool IsPublished { get; set; }
}

// ============================ Specials ============================

public sealed record SpecialDto(Guid Id, string Name, string? Description, string Type, int PercentOff, int? MinTravellers,
    string? PromoCode, bool IsPublic, int? MaxUses, int TimesUsed, DateTimeOffset StartsAt, DateTimeOffset EndsAt,
    bool IsActive, string? BannerImageUrl, IReadOnlyList<Guid> TripIds);

public sealed class SpecialUpsertRequest
{
    [Required, MaxLength(120)] public string Name { get; set; } = "";
    [MaxLength(500)] public string? Description { get; set; }
    [Required] public string Type { get; set; } = "percentage";
    [Range(1, 100)] public int PercentOff { get; set; }
    [Range(2, 100)] public int? MinTravellers { get; set; }
    [MaxLength(40)] public string? PromoCode { get; set; }
    public bool IsPublic { get; set; } = true;
    [Range(1, 100000)] public int? MaxUses { get; set; }
    public DateTimeOffset StartsAt { get; set; }
    public DateTimeOffset EndsAt { get; set; }
    public bool IsActive { get; set; } = true;
    public string? BannerImageUrl { get; set; }
    public List<Guid> TripIds { get; set; } = [];
}

// ============================ Enquiries ============================

public sealed class EnquiryRequest
{
    [Required, MaxLength(120)] public string Name { get; set; } = "";
    [Required, MaxLength(30)] public string Phone { get; set; } = "";
    [EmailAddress, MaxLength(200)] public string? Email { get; set; }
    public List<string> Services { get; set; } = [];
    [MaxLength(150)] public string? Destination { get; set; }
    public DateOnly? TravelFrom { get; set; }
    public DateOnly? TravelTo { get; set; }
    [Range(1, 500)] public int? People { get; set; }
    [Range(0, int.MaxValue)] public int? BudgetCents { get; set; }
    [MaxLength(2000)] public string? Message { get; set; }
}

public sealed record EnquiryDto(Guid Id, string Name, string Phone, string? Email, IReadOnlyList<string> Services,
    string? Destination, DateOnly? TravelFrom, DateOnly? TravelTo, int? People, int? BudgetCents, string? Message,
    string Status, string? StaffNotes, DateTimeOffset CreatedAt, string WhatsappLink);

public sealed class EnquiryUpdateRequest
{
    [Required] public string Status { get; set; } = "new";
    [MaxLength(2000)] public string? StaffNotes { get; set; }
}

// ============================ Company & staff ============================

public sealed record CompanyDto(string CompanyName, string? RegisteredName, string? Tagline, string? Phone, string? Whatsapp,
    string? Email, string? Address, string? FacebookUrl, string? InstagramUrl, string? TiktokUrl, string? AboutText,
    string? WhatsappLink, string? CallLink);

public sealed class CompanyUpdateRequest
{
    [Required, MaxLength(120)] public string CompanyName { get; set; } = "";
    [MaxLength(120)] public string? RegisteredName { get; set; }
    [MaxLength(120)] public string? Tagline { get; set; }
    [MaxLength(30)] public string? Phone { get; set; }
    [MaxLength(30)] public string? Whatsapp { get; set; }
    [EmailAddress] public string? Email { get; set; }
    [MaxLength(300)] public string? Address { get; set; }
    [Url] public string? FacebookUrl { get; set; }
    [Url] public string? InstagramUrl { get; set; }
    [Url] public string? TiktokUrl { get; set; }
    [MaxLength(3000)] public string? AboutText { get; set; }
}

public sealed class StaffInviteRequest
{
    [Required, EmailAddress] public string Email { get; set; } = "";
    [Required, MaxLength(120)] public string FullName { get; set; } = "";
}

public sealed record StaffDto(Guid Id, string FullName, string? Phone, DateTimeOffset CreatedAt);

public sealed record MeDto(Guid Id, string FullName, string? Phone, string Role, string? Email);

public sealed class UpdateMeRequest
{
    [Required, MaxLength(120)] public string FullName { get; set; } = "";
    [MaxLength(30)] public string? Phone { get; set; }
}

// ============================ Dashboard ============================

public sealed record DepartureStatDto(Guid DepartureId, string TripTitle, DateTimeOffset DepartureAt, string DepartsFrom,
    int Capacity, int SeatsBooked, int SeatsLeft, int Bookings);

public sealed record DashboardDto(
    int RevenueThisMonthCents,
    int BookingsThisMonth,
    int ActiveBookings,
    int OverdueInstalments,
    int OverdueAmountCents,
    int NewEnquiries,
    int PendingStudentIds,
    int PendingRefunds,
    IReadOnlyList<DepartureStatDto> UpcomingDepartures);
