using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Infrastructure;
using OwenTours.Domain.Entities;

namespace OwenTours.Application.Abstractions;

public interface IAppDbContext
{
    DbSet<Profile> Profiles { get; }
    DbSet<CompanySettings> CompanySettings { get; }
    DbSet<Trip> Trips { get; }
    DbSet<TripImage> TripImages { get; }
    DbSet<ItineraryDay> ItineraryDays { get; }
    DbSet<Departure> Departures { get; }
    DbSet<Special> Specials { get; }
    DbSet<SpecialTrip> SpecialTrips { get; }
    DbSet<Booking> Bookings { get; }
    DbSet<Traveller> Travellers { get; }
    DbSet<GuardianDetails> GuardianDetails { get; }
    DbSet<BookingDiscount> BookingDiscounts { get; }
    DbSet<Instalment> Instalments { get; }
    DbSet<Payment> Payments { get; }
    DbSet<Review> Reviews { get; }
    DbSet<PastTrip> PastTrips { get; }
    DbSet<PastTripMedia> PastTripMedia { get; }
    DbSet<Testimonial> Testimonials { get; }
    DbSet<Enquiry> Enquiries { get; }
    DbSet<Notification> Notifications { get; }
    DbSet<AuditLog> AuditLogs { get; }

    DatabaseFacade Database { get; }
    EntityEntry<TEntity> Entry<TEntity>(TEntity entity) where TEntity : class;
    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}

public interface IClock
{
    DateTimeOffset UtcNow { get; }
}

public interface ICurrentUser
{
    Guid? UserId { get; }
    string? Email { get; }
    bool IsAdmin { get; }

    Guid RequireUserId();
}

// ---------------- Payments ----------------

public sealed record PaymentCheckout(
    Guid PaymentId,
    string BookingReference,
    int AmountCents,
    string ItemName,
    string? CustomerName,
    string? CustomerEmail);

/// <summary>What the app needs to send the customer to the payment page (an HTML form POST).</summary>
public sealed record PaymentRedirect(string Url, IReadOnlyDictionary<string, string> FormFields);

public sealed record PaymentNotification(
    bool IsValid,
    string? InvalidReason,
    Guid PaymentId,
    string ProviderReference,
    int AmountCents,
    string Status,
    string RawJson);

public interface IPaymentGateway
{
    string Name { get; }
    PaymentRedirect CreateCheckout(PaymentCheckout checkout);

    /// <summary>Verifies signature, source and (with the provider) validity of a payment notification.</summary>
    Task<PaymentNotification> VerifyNotificationAsync(
        IReadOnlyList<KeyValuePair<string, string>> postedFields,
        string? remoteIp,
        CancellationToken ct);
}

// ---------------- Files ----------------

public sealed record StoredFile(string Bucket, string Path, string? PublicUrl);

public interface IFileStorage
{
    Task<StoredFile> UploadAsync(string bucket, string path, Stream content, string contentType, CancellationToken ct);
    Task DeleteAsync(string bucket, string path, CancellationToken ct);
    Task<string> CreateSignedUrlAsync(string bucket, string path, TimeSpan validFor, CancellationToken ct);
}

public sealed record ProcessedImage(byte[] Full, byte[] Thumbnail, string ContentType, string Extension);

public interface IImageProcessor
{
    /// <summary>Resizes to a sensible full size and a small thumbnail, re-encoded as JPEG (strips EXIF/GPS data).</summary>
    Task<ProcessedImage> ProcessAsync(Stream input, CancellationToken ct);
}

// ---------------- Notifications ----------------

public sealed record OutgoingMessage(
    string? ToEmail,
    string? ToPhone,
    string Subject,
    string Body,
    string Template);

public interface INotificationSender
{
    /// <summary>"email", "sms", "whatsapp" or "log".</summary>
    string Channel { get; }
    Task SendAsync(OutgoingMessage message, CancellationToken ct);
}

// ---------------- Documents ----------------

public sealed record InvoiceLine(string Description, int Quantity, int UnitCents, int TotalCents);

public sealed record InvoiceModel(
    string CompanyName,
    string? RegisteredName,
    string? CompanyEmail,
    string? CompanyPhone,
    string BookingReference,
    DateTimeOffset IssuedAt,
    string CustomerName,
    string TripTitle,
    string DepartureSummary,
    IReadOnlyList<InvoiceLine> Lines,
    int SubtotalCents,
    string? DiscountName,
    int DiscountCents,
    int TotalCents,
    int PaidCents,
    int BalanceCents,
    IReadOnlyList<(DateOnly Due, int AmountCents, string Status)> Instalments,
    string CancellationPolicy);

public sealed record ManifestTraveller(
    string FullName,
    string? Document,
    string? Phone,
    bool IsChild,
    string BookingReference,
    string BookingStatus,
    string? Notes);

public sealed record ManifestModel(
    string CompanyName,
    string TripTitle,
    string DepartureProvince,
    string DepartureArea,
    string MeetingPlace,
    DateTimeOffset DepartureAt,
    DateOnly ReturnDate,
    int Capacity,
    IReadOnlyList<ManifestTraveller> Travellers);

public interface IPdfGenerator
{
    byte[] Invoice(InvoiceModel model);
    byte[] Manifest(ManifestModel model);
}

// ---------------- Auth admin (Supabase) ----------------

public interface IAuthAdmin
{
    /// <summary>Sends a Supabase invite email and returns the new (or existing) user's id.</summary>
    Task<Guid> InviteUserAsync(string email, string fullName, CancellationToken ct);
}
