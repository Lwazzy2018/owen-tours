using Microsoft.Extensions.DependencyInjection;
using OwenTours.Application.Abstractions;
using OwenTours.Application.Common;
using OwenTours.Application.Services;

namespace OwenTours.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        services.AddSingleton<IClock, SystemClock>();
        services.AddScoped<AuditLogger>();
        services.AddScoped<NotificationService>();
        services.AddScoped<TripService>();
        services.AddScoped<DepartureService>();
        services.AddScoped<BookingService>();
        services.AddScoped<PaymentService>();
        services.AddScoped<ReminderService>();
        services.AddScoped<PastTripService>();
        services.AddScoped<SpecialService>();
        services.AddScoped<EnquiryService>();
        services.AddScoped<CompanyService>();
        services.AddScoped<ReviewService>();
        services.AddScoped<DashboardService>();
        services.AddScoped<DocumentService>();
        return services;
    }
}
