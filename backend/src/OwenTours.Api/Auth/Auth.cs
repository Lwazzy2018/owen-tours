using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using OwenTours.Application.Abstractions;
using OwenTours.Domain.Common;
using OwenTours.Infrastructure.Persistence;

namespace OwenTours.Api.Auth;

public static class AppClaims
{
    /// <summary>Added by <see cref="RoleClaimsTransformation"/> from the profiles table.</summary>
    public const string Role = "app_role";
    public const string AdminPolicy = "Admin";
}

/// <summary>The signed-in user, read from the Supabase JWT ("sub" = user id).</summary>
public sealed class CurrentUser(IHttpContextAccessor accessor) : ICurrentUser
{
    private ClaimsPrincipal? Principal => accessor.HttpContext?.User;

    public Guid? UserId =>
        Guid.TryParse(Principal?.FindFirstValue("sub") ?? Principal?.FindFirstValue(ClaimTypes.NameIdentifier), out var id) ? id : null;

    public string? Email => Principal?.FindFirstValue("email") ?? Principal?.FindFirstValue(ClaimTypes.Email);

    public bool IsAdmin => Principal?.HasClaim(AppClaims.Role, Roles.Admin) == true;

    public Guid RequireUserId() => UserId ?? throw new UnauthorizedAccessException("Please sign in.");
}

/// <summary>
/// Looks up the user's role in public.profiles (never trusted from the token) and adds it as a claim.
/// Cached for one minute so a promoted/demoted admin takes effect quickly.
/// </summary>
public sealed class RoleClaimsTransformation(AppDbContext db, IMemoryCache cache) : IClaimsTransformation
{
    public async Task<ClaimsPrincipal> TransformAsync(ClaimsPrincipal principal)
    {
        if (principal.Identity?.IsAuthenticated != true || principal.HasClaim(c => c.Type == AppClaims.Role))
            return principal;
        if (!Guid.TryParse(principal.FindFirstValue("sub"), out var userId))
            return principal;

        var role = await cache.GetOrCreateAsync($"role:{userId}", async entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(1);
            return await db.Profiles.AsNoTracking().Where(p => p.Id == userId).Select(p => p.Role).FirstOrDefaultAsync();
        });

        var identity = new ClaimsIdentity();
        identity.AddClaim(new Claim(AppClaims.Role, role ?? Roles.Customer));
        principal.AddIdentity(identity);
        return principal;
    }
}
