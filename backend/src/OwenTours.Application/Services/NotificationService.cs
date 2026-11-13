using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using OwenTours.Application.Abstractions;
using OwenTours.Domain.Entities;

namespace OwenTours.Application.Services;

public sealed record UserContact(Guid UserId, string FullName, string? Email, string? Phone);

public interface IUserDirectory
{
    Task<UserContact?> GetAsync(Guid userId, CancellationToken ct);
    Task<IReadOnlyList<UserContact>> AdminsAsync(CancellationToken ct);
}

/// <summary>
/// Sends messages and records them in the notifications table. A dedupe key guarantees that the
/// same reminder is never sent twice, even if a job runs again.
/// </summary>
public sealed class NotificationService(
    IAppDbContext db,
    IEnumerable<INotificationSender> senders,
    IUserDirectory users,
    IClock clock,
    ILogger<NotificationService> logger)
{
    public async Task<bool> NotifyUserAsync(
        Guid userId, Guid? bookingId, string template, string subject, string body, string? dedupeKey, CancellationToken ct)
    {
        if (dedupeKey is not null && await db.Notifications.AnyAsync(n => n.DedupeKey == dedupeKey, ct))
            return false;

        var contact = await users.GetAsync(userId, ct);
        var sender = senders.FirstOrDefault(s => s.Channel == "email" && contact?.Email is not null)
                     ?? senders.First(s => s.Channel == "log");

        var notification = new Notification
        {
            UserId = userId,
            BookingId = bookingId,
            Channel = sender.Channel,
            Template = template,
            Subject = subject,
            Body = body,
            DedupeKey = dedupeKey,
            SentAt = clock.UtcNow,
        };
        db.Notifications.Add(notification);

        try
        {
            // Save first: if another job instance already sent it, the unique dedupe key stops us here.
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException) when (dedupeKey is not null)
        {
            db.Entry(notification).State = EntityState.Detached;
            logger.LogInformation("Notification {DedupeKey} was already sent; skipping", dedupeKey);
            return false;
        }

        try
        {
            await sender.SendAsync(new OutgoingMessage(contact?.Email, contact?.Phone, subject, body, template), ct);
        }
        catch (Exception ex)
        {
            // The message is logged in the table; a failed email must never break a booking or payment.
            logger.LogError(ex, "Failed to send {Template} to user {UserId}", template, userId);
        }
        return true;
    }

    public async Task NotifyAdminsAsync(string template, string subject, string body, CancellationToken ct)
    {
        foreach (var admin in await users.AdminsAsync(ct))
            await NotifyUserAsync(admin.UserId, null, template, subject, body, null, ct);
    }
}
