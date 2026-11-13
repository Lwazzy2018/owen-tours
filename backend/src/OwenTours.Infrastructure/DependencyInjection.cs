using Hangfire;
using Hangfire.PostgreSql;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using OwenTours.Application.Abstractions;
using OwenTours.Application.Services;
using OwenTours.Infrastructure.Images;
using OwenTours.Infrastructure.Jobs;
using OwenTours.Infrastructure.Notifications;
using OwenTours.Infrastructure.Payments;
using OwenTours.Infrastructure.Pdf;
using OwenTours.Infrastructure.Persistence;
using OwenTours.Infrastructure.Storage;

namespace OwenTours.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration config, bool runJobs = true)
    {
        var connectionString = config.GetConnectionString("Database")
            ?? throw new InvalidOperationException("ConnectionStrings:Database is missing. See backend/.env.example.");

        services.AddDbContext<AppDbContext>(o => o
            .UseNpgsql(connectionString)
            .UseSnakeCaseNamingConvention());
        services.AddScoped<IAppDbContext>(sp => sp.GetRequiredService<AppDbContext>());
        services.AddScoped<UserDirectory>();
        services.AddScoped<IUserDirectory>(sp => sp.GetRequiredService<UserDirectory>());

        services.Configure<SupabaseOptions>(config.GetSection(SupabaseOptions.Section));
        services.Configure<PayFastOptions>(config.GetSection(PayFastOptions.Section));
        services.Configure<SmtpOptions>(config.GetSection(SmtpOptions.Section));

        services.AddHttpClient<IFileStorage, SupabaseStorage>(c => c.Timeout = TimeSpan.FromMinutes(5));
        services.AddHttpClient<IAuthAdmin, SupabaseAuthAdmin>();
        services.AddHttpClient<IPaymentGateway, PayFastGateway>(c => c.Timeout = TimeSpan.FromSeconds(20));

        services.AddSingleton<IImageProcessor, MagickImageProcessor>();
        services.AddSingleton<IPdfGenerator, QuestPdfGenerator>();

        services.AddSingleton<INotificationSender, LogNotificationSender>();
        if (config.GetSection(SmtpOptions.Section).Get<SmtpOptions>()?.IsConfigured == true)
            services.AddSingleton<INotificationSender, SmtpNotificationSender>();

        services.AddScoped<BookingJobs>();
        services.AddHangfire(h => h
            .SetDataCompatibilityLevel(CompatibilityLevel.Version_180)
            .UseSimpleAssemblyNameTypeSerializer()
            .UseRecommendedSerializerSettings()
            .UsePostgreSqlStorage(o => o.UseNpgsqlConnection(connectionString), new PostgreSqlStorageOptions
            {
                SchemaName = "hangfire",
                PrepareSchemaIfNecessary = true,
            }));
        if (runJobs) services.AddHangfireServer(o => o.WorkerCount = 2);

        return services;
    }
}
