using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.RateLimiting;
using Hangfire;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using OwenTours.Api.Auth;
using OwenTours.Api.Infrastructure;
using OwenTours.Application;
using OwenTours.Application.Abstractions;
using OwenTours.Domain.Common;
using OwenTours.Infrastructure;
using OwenTours.Infrastructure.Jobs;
using OwenTours.Infrastructure.Storage;
using Serilog;

var builder = WebApplication.CreateBuilder(args);

builder.Host.UseSerilog((ctx, cfg) => cfg
    .ReadFrom.Configuration(ctx.Configuration)
    .Enrich.FromLogContext()
    .WriteTo.Console());

var config = builder.Configuration;
var jobsEnabled = config.GetValue("Jobs:Enabled", true);

// ---------------- Application services ----------------
builder.Services.AddApplication();
builder.Services.AddInfrastructure(config, runJobs: jobsEnabled);
builder.Services.AddHttpContextAccessor();
builder.Services.AddMemoryCache();
builder.Services.AddScoped<ICurrentUser, CurrentUser>();
builder.Services.AddScoped<IClaimsTransformation, RoleClaimsTransformation>();

// ---------------- Authentication: Supabase JWTs ----------------
var supabase = config.GetSection(SupabaseOptions.Section).Get<SupabaseOptions>() ?? new SupabaseOptions();
if (string.IsNullOrWhiteSpace(supabase.Url))
    throw new InvalidOperationException("Supabase:Url is missing. See backend/.env.example.");
var jwks = new SupabaseJwks($"{supabase.BaseUrl}/auth/v1/.well-known/jwks.json");

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(o =>
    {
        o.MapInboundClaims = false; // keep "sub", "email", "role" as Supabase sends them
        o.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = $"{supabase.BaseUrl}/auth/v1",
            ValidateAudience = true,
            ValidAudience = "authenticated",
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromSeconds(30),
            ValidateIssuerSigningKey = true,
            // New Supabase projects sign with asymmetric keys (JWKS); older ones with a shared secret.
            IssuerSigningKeyResolver = (_, _, kid, _) =>
            {
                var keys = new List<SecurityKey>(jwks.GetKeys(kid));
                if (!string.IsNullOrWhiteSpace(supabase.JwtSecret))
                    keys.Add(new SymmetricSecurityKey(System.Text.Encoding.UTF8.GetBytes(supabase.JwtSecret)));
                return keys;
            },
        };
    });

builder.Services.AddAuthorizationBuilder()
    .AddPolicy(AppClaims.AdminPolicy, p => p.RequireAuthenticatedUser().RequireClaim(AppClaims.Role, Roles.Admin));

// ---------------- API ----------------
builder.Services.AddControllers().AddJsonOptions(o =>
{
    o.JsonSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
    o.JsonSerializerOptions.DefaultIgnoreCondition = JsonIgnoreCondition.Never;
});
builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<ProblemExceptionHandler>();

builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    o.AddPolicy("enquiries", ctx => RateLimitPartition.GetFixedWindowLimiter(
        ctx.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = 5, Window = TimeSpan.FromMinutes(10) }));
    o.AddPolicy("bookings", ctx => RateLimitPartition.GetFixedWindowLimiter(
        ctx.User.FindFirst("sub")?.Value ?? ctx.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = 20, Window = TimeSpan.FromMinutes(10) }));
});

var allowedOrigins = config.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];
builder.Services.AddCors(o => o.AddDefaultPolicy(p => p
    .WithOrigins(allowedOrigins)
    .AllowAnyHeader()
    .AllowAnyMethod()));

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "Owen Tours and Travel API", Version = "v1" });
    var scheme = new OpenApiSecurityScheme
    {
        Name = "Authorization",
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        In = ParameterLocation.Header,
        Description = "Paste a Supabase access token (from the app after signing in).",
        Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" },
    };
    c.AddSecurityDefinition("Bearer", scheme);
    c.AddSecurityRequirement(new OpenApiSecurityRequirement { [scheme] = [] });
    var xml = Path.Combine(AppContext.BaseDirectory, "OwenTours.Api.xml");
    if (File.Exists(xml)) c.IncludeXmlComments(xml);
});

builder.Services.AddHealthChecks();

var app = builder.Build();

// Behind a reverse proxy (Render, Railway, Azure, nginx) the real client IP is in X-Forwarded-For.
// PayFast's source-IP check needs it. Only enable when the proxy is trusted.
if (config.GetValue("ForwardedHeaders:Enabled", false))
{
    var fwd = new ForwardedHeadersOptions { ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto };
    fwd.KnownNetworks.Clear();
    fwd.KnownProxies.Clear();
    app.UseForwardedHeaders(fwd);
}

app.UseExceptionHandler();
app.UseSerilogRequestLogging();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
    if (jobsEnabled) app.UseHangfireDashboard("/hangfire"); // local requests only by default
}

app.UseCors();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.MapHealthChecks("/health");

if (jobsEnabled)
    BookingJobs.Schedule(app.Services.GetRequiredService<IRecurringJobManager>());

app.Run();

/// <summary>Fetches and caches Supabase's public signing keys.</summary>
internal sealed class SupabaseJwks(string url)
{
    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(10) };
    private readonly object _lock = new();
    private IReadOnlyList<SecurityKey> _keys = [];
    private DateTimeOffset _fetchedAt = DateTimeOffset.MinValue;

    public IEnumerable<SecurityKey> GetKeys(string? kid)
    {
        var keys = Current(forceRefresh: false);
        var match = keys.Where(k => kid is null || k.KeyId == kid).ToList();
        if (match.Count == 0 && kid is not null)
        {
            // Key rotation: refresh once (at most every 5 minutes) when an unknown key id appears.
            keys = Current(forceRefresh: DateTimeOffset.UtcNow - _fetchedAt > TimeSpan.FromMinutes(5));
            match = keys.Where(k => k.KeyId == kid).ToList();
        }
        return match;
    }

    private IReadOnlyList<SecurityKey> Current(bool forceRefresh)
    {
        lock (_lock)
        {
            if (!forceRefresh && _keys.Count > 0 && DateTimeOffset.UtcNow - _fetchedAt < TimeSpan.FromHours(1)) return _keys;
            try
            {
                var json = _http.GetStringAsync(url).GetAwaiter().GetResult();
                _keys = new JsonWebKeySet(json).GetSigningKeys().ToList();
                _fetchedAt = DateTimeOffset.UtcNow;
            }
            catch (Exception)
            {
                // Legacy projects (shared secret only) have no keys here; keep what we have.
                _fetchedAt = DateTimeOffset.UtcNow;
            }
            return _keys;
        }
    }
}

public partial class Program { }
