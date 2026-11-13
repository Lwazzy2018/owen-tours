namespace OwenTours.Domain.Entities;

// Plain classes that map 1:1 to the Supabase tables (snake_case columns via EF naming convention).
// All DateTimeOffset values must be UTC when saved (Npgsql requirement).

public class Profile
{
    public Guid Id { get; set; }
    public string FullName { get; set; } = "";
    public string? Phone { get; set; }
    public string Role { get; set; } = Common.Roles.Customer;
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
}

public class CompanySettings
{
    public int Id { get; set; } = 1;
    public string CompanyName { get; set; } = "";
    public string? RegisteredName { get; set; }
    public string? Tagline { get; set; }
    public string? Phone { get; set; }
    public string? Whatsapp { get; set; }
    public string? Email { get; set; }
    public string? Address { get; set; }
    public string? FacebookUrl { get; set; }
    public string? InstagramUrl { get; set; }
    public string? TiktokUrl { get; set; }
    public string? AboutText { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
}

public class Trip
{
    public Guid Id { get; set; }
    public string Title { get; set; } = "";
    public string Destination { get; set; } = "";
    public string DestinationCountry { get; set; } = "South Africa";
    public bool IsCrossBorder { get; set; }                       // computed by the database
    public string Category { get; set; } = "other";
    public string Audience { get; set; } = Common.Audience.Everyone;
    public int? MinGrade { get; set; }
    public int? MaxGrade { get; set; }
    public List<string> Activities { get; set; } = [];
    public string? Tagline { get; set; }
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
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public List<TripImage> Images { get; set; } = [];
    public List<ItineraryDay> ItineraryDays { get; set; } = [];
    public List<Departure> Departures { get; set; } = [];

    public bool IsCrossBorderTrip => !string.Equals(DestinationCountry, "South Africa", StringComparison.OrdinalIgnoreCase);
}

public class TripImage
{
    public Guid Id { get; set; }
    public Guid TripId { get; set; }
    public string Url { get; set; } = "";
    public string? ThumbnailUrl { get; set; }
    public string? StoragePath { get; set; }
    public int SortOrder { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
}

public class ItineraryDay
{
    public Guid Id { get; set; }
    public Guid TripId { get; set; }
    public int DayNumber { get; set; }
    public string Title { get; set; } = "";
    public string Description { get; set; } = "";
}

public class Departure
{
    public Guid Id { get; set; }
    public Guid TripId { get; set; }
    public Trip? Trip { get; set; }
    public string DepartureProvince { get; set; } = "Mpumalanga";
    public string DepartureArea { get; set; } = "";
    public string MeetingPlace { get; set; } = "";
    public DateTimeOffset DepartureAt { get; set; }
    public DateOnly ReturnDate { get; set; }
    public int Capacity { get; set; }
    public int SeatsBooked { get; set; }
    public int AdultPriceCents { get; set; }
    public int ChildPriceCents { get; set; }
    public DateTimeOffset BookingDeadline { get; set; }
    public bool AllowInstalments { get; set; }
    /// <summary>Deposit PER TRAVELLER, in cents.</summary>
    public int DepositCents { get; set; }
    public DateOnly? FinalPaymentDue { get; set; }

    public bool IsCancellable { get; set; } = true;
    public DateTimeOffset? CancellationDeadline { get; set; }
    public string RefundType { get; set; } = Common.RefundType.None;
    public int? RefundPercent { get; set; }
    public bool DepositRefundable { get; set; }
    public string? CancellationNotes { get; set; }

    public bool IsCancelledByCompany { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public int SeatsLeft => Math.Max(Capacity - SeatsBooked, 0);
}

public class Special
{
    public Guid Id { get; set; }
    public string Name { get; set; } = "";
    public string? Description { get; set; }
    public string Type { get; set; } = Common.SpecialType.Percentage;
    public int PercentOff { get; set; }
    public int? MinTravellers { get; set; }
    public string? PromoCode { get; set; }
    public bool IsPublic { get; set; } = true;
    public int? MaxUses { get; set; }
    public int TimesUsed { get; set; }
    public DateTimeOffset StartsAt { get; set; }
    public DateTimeOffset EndsAt { get; set; }
    public bool IsActive { get; set; } = true;
    public string? BannerImageUrl { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public List<SpecialTrip> SpecialTrips { get; set; } = [];
}

public class SpecialTrip
{
    public Guid SpecialId { get; set; }
    public Guid TripId { get; set; }
}

public class Booking
{
    public Guid Id { get; set; }
    public string Reference { get; set; } = null!;               // generated by the database, e.g. OT001234
    public Guid DepartureId { get; set; }
    public Departure? Departure { get; set; }
    public Guid CustomerId { get; set; }
    public Profile? Customer { get; set; }
    public string Status { get; set; } = Common.BookingStatus.Pending;
    public string PaymentPlan { get; set; } = Common.PaymentPlan.Full;
    public int Adults { get; set; }
    public int Children { get; set; }
    public int SubtotalCents { get; set; }
    public int DiscountCents { get; set; }
    public int TotalCents { get; set; }
    /// <summary>Total deposit for the whole booking (per-traveller deposit × travellers, capped at the total).</summary>
    public int DepositCents { get; set; }
    public int AmountPaidCents { get; set; }
    public DateTimeOffset? ExpiresAt { get; set; }
    public string CancellationPolicySnapshot { get; set; } = "{}";   // jsonb
    public DateTimeOffset PolicyAcceptedAt { get; set; }
    public DateTimeOffset? CancelledAt { get; set; }
    public Guid? CancelledBy { get; set; }
    public string? CancellationReason { get; set; }
    public int RefundCents { get; set; }
    public string RefundStatus { get; set; } = Common.RefundStatus.None;
    public DateTimeOffset? RefundedAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public List<Traveller> Travellers { get; set; } = [];
    public GuardianDetails? Guardian { get; set; }
    public BookingDiscount? Discount { get; set; }
    public List<Instalment> Instalments { get; set; } = [];
    public List<Payment> Payments { get; set; } = [];

    public int TravellerCount => Adults + Children;
    public int BalanceCents => Math.Max(TotalCents - AmountPaidCents, 0);
}

public class Traveller
{
    public Guid Id { get; set; }
    public Guid BookingId { get; set; }
    public string FullName { get; set; } = "";
    public string? IdNumber { get; set; }
    public string? PassportNumber { get; set; }
    public DateOnly? PassportExpiry { get; set; }
    public string? Phone { get; set; }
    public bool IsChild { get; set; }
    public DateOnly? DateOfBirth { get; set; }
    public int? SchoolGrade { get; set; }
    public string? MedicalNotes { get; set; }
    public string? Allergies { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
}

public class GuardianDetails
{
    public Guid Id { get; set; }
    public Guid BookingId { get; set; }
    public string GuardianName { get; set; } = "";
    public string GuardianPhone { get; set; } = "";
    public string GuardianRelationship { get; set; } = "";
    public string EmergencyContactName { get; set; } = "";
    public string EmergencyContactPhone { get; set; } = "";
    public DateTimeOffset ConsentGivenAt { get; set; }
}

public class BookingDiscount
{
    public Guid Id { get; set; }
    public Guid BookingId { get; set; }
    public Guid SpecialId { get; set; }
    public string SpecialName { get; set; } = "";
    public int PercentOff { get; set; }
    public int DiscountCents { get; set; }
    public string Status { get; set; } = Common.DiscountStatus.Applied;
    public string? StudentIdImagePath { get; set; }
    public Guid? ReviewedBy { get; set; }
    public DateTimeOffset? ReviewedAt { get; set; }
    public string? ReviewNote { get; set; }
    public bool PromoUseReleased { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
}

public class Instalment
{
    public Guid Id { get; set; }
    public Guid BookingId { get; set; }
    public int Sequence { get; set; }
    public DateOnly DueDate { get; set; }
    public int AmountCents { get; set; }
    public string Status { get; set; } = Common.InstalmentStatus.Due;
    public DateTimeOffset? PaidAt { get; set; }
}

public class Payment
{
    public Guid Id { get; set; }
    public Guid BookingId { get; set; }
    public string Purpose { get; set; } = Common.PaymentPurpose.Full;
    public Guid? InstalmentId { get; set; }
    public int AmountCents { get; set; }
    public string Provider { get; set; } = "payfast";
    public string? ProviderReference { get; set; }
    public string Status { get; set; } = Common.PaymentStatus.Pending;
    public DateTimeOffset? PaidAt { get; set; }
    public string? RawPayload { get; set; }                          // jsonb
    public DateTimeOffset CreatedAt { get; set; }
}

public class Review
{
    public Guid Id { get; set; }
    public Guid TripId { get; set; }
    public Guid CustomerId { get; set; }
    public Profile? Customer { get; set; }
    public int Rating { get; set; }
    public string? Comment { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
}

public class PastTrip
{
    public Guid Id { get; set; }
    public Guid? TripId { get; set; }
    public string Title { get; set; } = "";
    public string Destination { get; set; } = "";
    public DateOnly TravelledOn { get; set; }
    public int? TravellerCount { get; set; }
    public string? Story { get; set; }
    public string? CoverUrl { get; set; }
    public bool IsFeatured { get; set; }
    public bool IsPublished { get; set; }
    public int SortOrder { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public List<PastTripMedia> Media { get; set; } = [];
    public List<Testimonial> Testimonials { get; set; } = [];
}

public class PastTripMedia
{
    public Guid Id { get; set; }
    public Guid PastTripId { get; set; }
    public string MediaType { get; set; } = "image";
    public string Url { get; set; } = "";
    public string? ThumbnailUrl { get; set; }
    public string? StoragePath { get; set; }
    public string? Caption { get; set; }
    public int SortOrder { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
}

public class Testimonial
{
    public Guid Id { get; set; }
    public Guid PastTripId { get; set; }
    public string CustomerName { get; set; } = "";
    public string Quote { get; set; } = "";
    public int? Rating { get; set; }
    public string? PhotoUrl { get; set; }
    public bool IsPublished { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
}

public class Enquiry
{
    public Guid Id { get; set; }
    public Guid? CustomerId { get; set; }
    public string Name { get; set; } = "";
    public string Phone { get; set; } = "";
    public string? Email { get; set; }
    public List<string> Services { get; set; } = [];
    public string? Destination { get; set; }
    public DateOnly? TravelFrom { get; set; }
    public DateOnly? TravelTo { get; set; }
    public int? People { get; set; }
    public int? BudgetCents { get; set; }
    public string? Message { get; set; }
    public string Status { get; set; } = Common.EnquiryStatus.New;
    public string? StaffNotes { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
}

public class Notification
{
    public Guid Id { get; set; }
    public Guid? UserId { get; set; }
    public Guid? BookingId { get; set; }
    public string Channel { get; set; } = "email";
    public string Template { get; set; } = "";
    public string? Subject { get; set; }
    public string Body { get; set; } = "";
    public string? DedupeKey { get; set; }
    public DateTimeOffset SentAt { get; set; }
}

public class AuditLog
{
    public long Id { get; set; }
    public Guid? ActorId { get; set; }
    public string Action { get; set; } = "";
    public string Entity { get; set; } = "";
    public string? EntityId { get; set; }
    public string? Data { get; set; }                                // jsonb
    public DateTimeOffset CreatedAt { get; set; }
}
