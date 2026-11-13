using System.Text.Json;
using OwenTours.Application.Abstractions;
using OwenTours.Domain.Entities;

namespace OwenTours.Application.Common;

public class NotFoundException(string what) : Exception($"{what} was not found.");

public class ForbiddenException(string message = "You don't have access to this.") : Exception(message);

public sealed record PagedResult<T>(IReadOnlyList<T> Items, int Page, int PageSize, int TotalCount)
{
    public int TotalPages => PageSize == 0 ? 0 : (int)Math.Ceiling(TotalCount / (double)PageSize);
}

public static class Paging
{
    public static (int Page, int PageSize) Normalise(int? page, int? pageSize, int max = 100) =>
        (Math.Max(page ?? 1, 1), Math.Clamp(pageSize ?? 20, 1, max));
}

public sealed class SystemClock : IClock
{
    public DateTimeOffset UtcNow => DateTimeOffset.UtcNow;
}

/// <summary>Writes to the audit_log table. Call before SaveChangesAsync so it saves in the same transaction.</summary>
public sealed class AuditLogger(IAppDbContext db, ICurrentUser user, IClock clock)
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower };

    public void Log(string action, string entity, object? entityId, object? data = null, Guid? actorId = null)
    {
        db.AuditLogs.Add(new AuditLog
        {
            ActorId = actorId ?? user.UserId,
            Action = action,
            Entity = entity,
            EntityId = entityId?.ToString(),
            Data = data is null ? null : JsonSerializer.Serialize(data, Json),
            CreatedAt = clock.UtcNow,
        });
    }
}
