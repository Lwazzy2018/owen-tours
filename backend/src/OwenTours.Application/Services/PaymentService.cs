using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using OwenTours.Application.Abstractions;
using OwenTours.Application.Common;
using OwenTours.Application.Dtos;
using OwenTours.Domain.Common;
using OwenTours.Domain.Entities;
using OwenTours.Domain.Rules;

namespace OwenTours.Application.Services;

public sealed class PaymentService(
    IAppDbContext db,
    IClock clock,
    ICurrentUser currentUser,
    IPaymentGateway gateway,
    IUserDirectory users,
    AuditLogger audit,
    NotificationService notifications,
    ILogger<PaymentService> logger)
{
    /// <summary>Creates a pending payment and returns where to send the customer to pay.</summary>
    public async Task<PaymentRedirectDto> StartAsync(Guid bookingId, PayRequest req, CancellationToken ct)
    {
        var userId = currentUser.RequireUserId();
        var booking = await db.Bookings.AsNoTracking()
            .Include(b => b.Departure).ThenInclude(d => d!.Trip)
            .Include(b => b.Instalments)
            .FirstOrDefaultAsync(b => b.Id == bookingId, ct)
            ?? throw new NotFoundException("Booking");
        if (booking.CustomerId != userId) throw new NotFoundException("Booking");

        if (booking.Status == BookingStatus.Pending && booking.ExpiresAt < clock.UtcNow)
            throw new BusinessRuleException("Your seat hold has expired. Please book again – the seats may still be available.", 409);

        var plan = PaymentRules.Resolve(booking, booking.Instalments, req.Type);
        var payment = new Payment
        {
            BookingId = booking.Id,
            Purpose = plan.Purpose,
            InstalmentId = plan.InstalmentId,
            AmountCents = plan.AmountCents,
            Provider = gateway.Name,
            Status = PaymentStatus.Pending,
            CreatedAt = clock.UtcNow,
        };
        db.Payments.Add(payment);
        await db.SaveChangesAsync(ct);

        var contact = await users.GetAsync(userId, ct);
        var purposeText = plan.Purpose switch
        {
            PaymentPurpose.Deposit => "deposit",
            PaymentPurpose.Instalment => "instalment",
            PaymentPurpose.Balance => "balance",
            _ => "full payment",
        };
        var redirect = gateway.CreateCheckout(new PaymentCheckout(
            payment.Id, booking.Reference, payment.AmountCents,
            $"{booking.Reference} – {booking.Departure!.Trip!.Title} ({purposeText})",
            contact?.FullName, contact?.Email));

        return new PaymentRedirectDto(payment.Id, payment.AmountCents, redirect.Url, redirect.FormFields);
    }

    /// <summary>
    /// An auto-submitting HTML form that sends the customer to the payment page. The app opens this URL
    /// (in a WebView on phones, in the browser on the web). The payment id is a random GUID, and the form
    /// only holds what PayFast's own checkout page shows the customer anyway.
    /// </summary>
    public async Task<string> CheckoutHtmlAsync(Guid paymentId, CancellationToken ct)
    {
        var payment = await db.Payments.AsNoTracking().FirstOrDefaultAsync(p => p.Id == paymentId, ct)
                      ?? throw new NotFoundException("Payment");
        if (payment.Status != PaymentStatus.Pending)
            throw new BusinessRuleException("This payment has already been completed or cancelled.", 409);
        if (clock.UtcNow - payment.CreatedAt > TimeSpan.FromHours(2))
            throw new BusinessRuleException("This payment link has expired. Please start the payment again from My Trips.", 410);

        var booking = await db.Bookings.AsNoTracking().Include(b => b.Departure).ThenInclude(d => d!.Trip)
            .FirstAsync(b => b.Id == payment.BookingId, ct);
        var contact = await users.GetAsync(booking.CustomerId, ct);
        var redirect = gateway.CreateCheckout(new PaymentCheckout(payment.Id, booking.Reference, payment.AmountCents,
            $"{booking.Reference} – {booking.Departure!.Trip!.Title}", contact?.FullName, contact?.Email));

        var inputs = string.Concat(redirect.FormFields.Select(f =>
            $"<input type=\"hidden\" name=\"{System.Net.WebUtility.HtmlEncode(f.Key)}\" value=\"{System.Net.WebUtility.HtmlEncode(f.Value)}\">"));
        return "<!doctype html><html><head><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>Redirecting to payment…</title></head>" +
               "<body style=\"font-family:sans-serif;color:#063B4C;text-align:center;padding-top:80px\" onload=\"document.forms[0].submit()\">" +
               $"<p>Taking you to the secure payment page…</p><form method=\"post\" action=\"{System.Net.WebUtility.HtmlEncode(redirect.Url)}\">{inputs}" +
               "<noscript><button type=\"submit\">Continue to payment</button></noscript></form></body></html>";
    }

    /// <summary>
    /// Handles a payment notification (PayFast ITN). Payments are marked paid ONLY here, after the
    /// signature, source and amount are verified. Safe to receive the same notification many times.
    /// </summary>
    public async Task HandleNotificationAsync(IReadOnlyList<KeyValuePair<string, string>> fields, string? remoteIp, CancellationToken ct)
    {
        var n = await gateway.VerifyNotificationAsync(fields, remoteIp, ct);
        if (!n.IsValid)
        {
            logger.LogWarning("Rejected payment notification from {Ip}: {Reason}", remoteIp, n.InvalidReason);
            audit.Log("payment.notification_rejected", "payment", n.PaymentId == Guid.Empty ? null : n.PaymentId,
                new { reason = n.InvalidReason, ip = remoteIp });
            await db.SaveChangesAsync(ct);
            return;
        }

        var payment = await db.Payments.AsNoTracking().FirstOrDefaultAsync(p => p.Id == n.PaymentId, ct);
        if (payment is null)
        {
            logger.LogWarning("Payment notification for unknown payment {PaymentId}", n.PaymentId);
            return;
        }

        switch (PaymentRules.CheckNotification(payment, n.AmountCents, n.Status))
        {
            case NotificationDecision.AlreadyProcessed:
                logger.LogInformation("Payment {PaymentId} already processed; ignoring repeat notification", payment.Id);
                return;

            case NotificationDecision.AmountMismatch:
                logger.LogError("Payment {PaymentId} amount mismatch: expected {Expected}, got {Got}", payment.Id, payment.AmountCents, n.AmountCents);
                audit.Log("payment.amount_mismatch", "payment", payment.Id, new { expected = payment.AmountCents, got = n.AmountCents });
                await db.SaveChangesAsync(ct);
                await notifications.NotifyAdminsAsync("payment_problem", "Payment amount mismatch",
                    $"A payment notification for payment {payment.Id} had the wrong amount. It was NOT applied. Please check PayFast.", ct);
                return;

            case NotificationDecision.NotSuccessful:
                await db.Payments.Where(p => p.Id == payment.Id && p.Status == PaymentStatus.Pending)
                    .ExecuteUpdateAsync(s => s
                        .SetProperty(p => p.Status, n.Status.Equals("CANCELLED", StringComparison.OrdinalIgnoreCase) ? PaymentStatus.Cancelled : PaymentStatus.Failed)
                        .SetProperty(p => p.RawPayload, n.RawJson), ct);
                return;
        }

        await ApplyAsync(payment.Id, n.ProviderReference, n.RawJson, ct);
    }

    private async Task ApplyAsync(Guid paymentId, string providerReference, string rawJson, CancellationToken ct)
    {
        var now = clock.UtcNow;
        await using var tx = await db.Database.BeginTransactionAsync(ct);

        // Idempotency: only the first notification can move the payment to 'complete'.
        var claimed = await db.Payments
            .Where(p => p.Id == paymentId && p.Status != PaymentStatus.Complete)
            .ExecuteUpdateAsync(s => s
                .SetProperty(p => p.Status, PaymentStatus.Complete)
                .SetProperty(p => p.ProviderReference, providerReference)
                .SetProperty(p => p.PaidAt, now)
                .SetProperty(p => p.RawPayload, rawJson), ct);
        if (claimed == 0)
        {
            await tx.RollbackAsync(ct);
            return;
        }

        var payment = await db.Payments.FirstAsync(p => p.Id == paymentId, ct);
        var booking = await db.Bookings.Include(b => b.Instalments).FirstAsync(b => b.Id == payment.BookingId, ct);
        var lateNoSeats = false;

        if (booking.Status == BookingStatus.Expired)
        {
            // The customer paid after the seat hold ran out. Try to get the seats back.
            var seats = booking.TravellerCount;
            var departureId = booking.DepartureId;
            var reserved = await db.Departures
                .Where(d => d.Id == departureId && !d.IsCancelledByCompany && d.SeatsBooked + seats <= d.Capacity)
                .ExecuteUpdateAsync(s => s.SetProperty(d => d.SeatsBooked, d => d.SeatsBooked + seats), ct);
            if (reserved == 1)
            {
                booking.Status = BookingStatus.Pending;
                booking.ExpiresAt = now;
                // Instalments were cancelled when it expired; bring the unpaid ones back.
                foreach (var i in booking.Instalments.Where(i => i.Status == InstalmentStatus.Cancelled))
                    i.Status = InstalmentStatus.Due;
                audit.Log("booking.revived_by_late_payment", "booking", booking.Id, new { payment.AmountCents });
            }
            else
            {
                lateNoSeats = true;
            }
        }

        if (booking.Status == BookingStatus.Cancelled || lateNoSeats)
        {
            // Money arrived for a booking that can't go ahead: record it and refund it.
            booking.AmountPaidCents += payment.AmountCents;
            booking.RefundCents += payment.AmountCents;
            booking.RefundStatus = RefundStatus.Pending;
            booking.UpdatedAt = now;
            audit.Log("payment.received_for_inactive_booking", "booking", booking.Id,
                new { payment.AmountCents, booking.Status, refund = payment.AmountCents });
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            await notifications.NotifyAdminsAsync("payment_needs_refund", $"Refund needed – {booking.Reference}",
                $"A payment of {Money.FormatRand(payment.AmountCents)} arrived for booking {booking.Reference}, " +
                "but the booking is no longer active (the seats were taken). Please refund the customer.", ct);
            return;
        }

        PaymentRules.ApplyPayment(booking, booking.Instalments, payment, now);
        booking.UpdatedAt = now;
        audit.Log("payment.completed", "booking", booking.Id, new { payment.Id, payment.AmountCents, payment.Purpose, booking.Status });
        await db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);

        var message = booking.Status == BookingStatus.Paid
            ? $"Thank you! Booking {booking.Reference} is fully paid. We can't wait to travel with you."
            : $"Thank you! We received {Money.FormatRand(payment.AmountCents)} for booking {booking.Reference}. " +
              $"Your seat is confirmed. Balance: {Money.FormatRand(booking.BalanceCents)}.";
        await notifications.NotifyUserAsync(booking.CustomerId, booking.Id, "payment_received",
            $"Payment received – {booking.Reference}", message, $"payment-received:{payment.Id}", ct);
    }
}
