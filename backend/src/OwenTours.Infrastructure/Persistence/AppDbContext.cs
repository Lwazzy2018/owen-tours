using Microsoft.EntityFrameworkCore;
using OwenTours.Application.Abstractions;
using OwenTours.Domain.Entities;

namespace OwenTours.Infrastructure.Persistence;

/// <summary>Read-only view of Supabase's auth.users, for email addresses.</summary>
public sealed class AuthUser
{
    public Guid Id { get; set; }
    public string? Email { get; set; }
    public string? Phone { get; set; }
}

/// <summary>
/// The schema is owned by the SQL files in /supabase/migrations (not EF migrations).
/// This context only maps to it. Columns are snake_case via UseSnakeCaseNamingConvention().
/// </summary>
public sealed class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options), IAppDbContext
{
    public DbSet<Profile> Profiles => Set<Profile>();
    public DbSet<CompanySettings> CompanySettings => Set<CompanySettings>();
    public DbSet<Trip> Trips => Set<Trip>();
    public DbSet<TripImage> TripImages => Set<TripImage>();
    public DbSet<ItineraryDay> ItineraryDays => Set<ItineraryDay>();
    public DbSet<Departure> Departures => Set<Departure>();
    public DbSet<Special> Specials => Set<Special>();
    public DbSet<SpecialTrip> SpecialTrips => Set<SpecialTrip>();
    public DbSet<Booking> Bookings => Set<Booking>();
    public DbSet<Traveller> Travellers => Set<Traveller>();
    public DbSet<GuardianDetails> GuardianDetails => Set<GuardianDetails>();
    public DbSet<BookingDiscount> BookingDiscounts => Set<BookingDiscount>();
    public DbSet<Instalment> Instalments => Set<Instalment>();
    public DbSet<Payment> Payments => Set<Payment>();
    public DbSet<Review> Reviews => Set<Review>();
    public DbSet<PastTrip> PastTrips => Set<PastTrip>();
    public DbSet<PastTripMedia> PastTripMedia => Set<PastTripMedia>();
    public DbSet<Testimonial> Testimonials => Set<Testimonial>();
    public DbSet<Enquiry> Enquiries => Set<Enquiry>();
    public DbSet<Notification> Notifications => Set<Notification>();
    public DbSet<AuditLog> AuditLogs => Set<AuditLog>();
    public DbSet<AuthUser> AuthUsers => Set<AuthUser>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.HasDefaultSchema("public");

        b.Entity<AuthUser>(e =>
        {
            e.ToTable("users", "auth", t => t.ExcludeFromMigrations());
            e.HasKey(x => x.Id);
        });

        b.Entity<Profile>(e =>
        {
            e.ToTable("profiles");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).ValueGeneratedNever();
        });

        b.Entity<CompanySettings>(e =>
        {
            e.ToTable("company_settings");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).ValueGeneratedNever();
        });

        b.Entity<Trip>(e =>
        {
            e.ToTable("trips");
            e.Property(x => x.IsCrossBorder)
                .HasComputedColumnSql("destination_country <> 'South Africa'", stored: true)
                .ValueGeneratedOnAddOrUpdate();
            e.HasMany(x => x.Images).WithOne().HasForeignKey(x => x.TripId).OnDelete(DeleteBehavior.Cascade);
            e.HasMany(x => x.ItineraryDays).WithOne().HasForeignKey(x => x.TripId).OnDelete(DeleteBehavior.Cascade);
            e.HasMany(x => x.Departures).WithOne(x => x.Trip).HasForeignKey(x => x.TripId).OnDelete(DeleteBehavior.Restrict);
        });

        b.Entity<TripImage>().ToTable("trip_images");
        b.Entity<ItineraryDay>().ToTable("itinerary_days");
        b.Entity<Departure>().ToTable("departures");

        b.Entity<Special>(e =>
        {
            e.ToTable("specials");
            e.HasMany(x => x.SpecialTrips).WithOne().HasForeignKey(x => x.SpecialId).OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<SpecialTrip>(e =>
        {
            e.ToTable("special_trips");
            e.HasKey(x => new { x.SpecialId, x.TripId });
        });

        b.Entity<Booking>(e =>
        {
            e.ToTable("bookings");
            e.Property(x => x.Reference)
                .HasDefaultValueSql("('OT' || lpad(nextval('public.booking_reference_seq')::text, 6, '0'))")
                .ValueGeneratedOnAdd();
            e.Property(x => x.CancellationPolicySnapshot).HasColumnType("jsonb");
            e.HasOne(x => x.Departure).WithMany().HasForeignKey(x => x.DepartureId).OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Customer).WithMany().HasForeignKey(x => x.CustomerId).OnDelete(DeleteBehavior.Restrict);
            e.HasMany(x => x.Travellers).WithOne().HasForeignKey(x => x.BookingId).OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Guardian).WithOne().HasForeignKey<GuardianDetails>(x => x.BookingId).OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Discount).WithOne().HasForeignKey<BookingDiscount>(x => x.BookingId).OnDelete(DeleteBehavior.Cascade);
            e.HasMany(x => x.Instalments).WithOne().HasForeignKey(x => x.BookingId).OnDelete(DeleteBehavior.Cascade);
            e.HasMany(x => x.Payments).WithOne().HasForeignKey(x => x.BookingId).OnDelete(DeleteBehavior.Restrict);
        });

        b.Entity<Traveller>().ToTable("travellers");
        b.Entity<GuardianDetails>().ToTable("guardian_details");
        b.Entity<BookingDiscount>().ToTable("booking_discounts");
        b.Entity<Instalment>().ToTable("instalments");

        b.Entity<Payment>(e =>
        {
            e.ToTable("payments");
            e.Property(x => x.RawPayload).HasColumnType("jsonb");
        });

        b.Entity<Review>(e =>
        {
            e.ToTable("reviews");
            e.HasOne(x => x.Customer).WithMany().HasForeignKey(x => x.CustomerId);
        });

        b.Entity<PastTrip>(e =>
        {
            e.ToTable("past_trips");
            e.HasMany(x => x.Media).WithOne().HasForeignKey(x => x.PastTripId).OnDelete(DeleteBehavior.Cascade);
            e.HasMany(x => x.Testimonials).WithOne().HasForeignKey(x => x.PastTripId).OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<PastTripMedia>().ToTable("past_trip_media");
        b.Entity<Testimonial>().ToTable("testimonials");
        b.Entity<Enquiry>().ToTable("enquiries");
        b.Entity<Notification>().ToTable("notifications");

        b.Entity<AuditLog>(e =>
        {
            e.ToTable("audit_log");
            e.Property(x => x.Id).UseIdentityAlwaysColumn();
            e.Property(x => x.Data).HasColumnType("jsonb");
        });
    }
}
