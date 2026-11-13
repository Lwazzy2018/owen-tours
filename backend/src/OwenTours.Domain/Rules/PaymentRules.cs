using OwenTours.Domain.Common;
using OwenTours.Domain.Entities;

namespace OwenTours.Domain.Rules;

public sealed record PaymentRequestPlan(string Purpose, int AmountCents, Guid? InstalmentId);

public static class PaymentRules
{
    /// <summary>
    /// What the customer is paying now. Types the customer can choose:
    /// "full" (whole amount), "deposit", "next_instalment" or "balance" (pay off everything left).
    /// </summary>
    public static PaymentRequestPlan Resolve(Booking booking, IReadOnlyList<Instalment> instalments, string requestedType)
    {
        if (booking.Status is BookingStatus.Cancelled or BookingStatus.Expired)
            throw new BusinessRuleException("This booking is cancelled or expired and can't be paid.", 409);

        var owed = booking.TotalCents - booking.AmountPaidCents;
        if (owed <= 0)
            throw new BusinessRuleException("This booking is already fully paid.", 409);

        switch (requestedType)
        {
            case "full":
                if (booking.AmountPaidCents > 0)
                    throw new BusinessRuleException("Part of this booking is already paid. Choose \"balance\" to pay the rest.");
                return new PaymentRequestPlan(PaymentPurpose.Full, owed, null);

            case "deposit":
                if (booking.PaymentPlan != PaymentPlan.Instalments)
                    throw new BusinessRuleException("This booking is set to be paid in full.");
                if (booking.AmountPaidCents >= booking.DepositCents)
                    throw new BusinessRuleException("The deposit is already paid. Pay the next instalment instead.", 409);
                return new PaymentRequestPlan(PaymentPurpose.Deposit, booking.DepositCents - booking.AmountPaidCents, null);

            case "next_instalment":
            {
                if (booking.PaymentPlan != PaymentPlan.Instalments)
                    throw new BusinessRuleException("This booking doesn't use instalments.");
                if (booking.AmountPaidCents < booking.DepositCents)
                    throw new BusinessRuleException("Please pay the deposit first.");
                var next = instalments
                    .Where(i => i.Status is InstalmentStatus.Due or InstalmentStatus.Overdue)
                    .OrderBy(i => i.Sequence)
                    .FirstOrDefault()
                    ?? throw new BusinessRuleException("There is no instalment left to pay.", 409);
                return new PaymentRequestPlan(PaymentPurpose.Instalment, Math.Min(next.AmountCents, owed), next.Id);
            }

            case "balance":
                if (booking.PaymentPlan == PaymentPlan.Instalments && booking.AmountPaidCents < booking.DepositCents)
                    throw new BusinessRuleException("Please pay the deposit first, or choose to pay in full.");
                return new PaymentRequestPlan(PaymentPurpose.Balance, owed, null);

            default:
                throw new BusinessRuleException("Unknown payment type. Use full, deposit, next_instalment or balance.", 400);
        }
    }

    /// <summary>
    /// Applies a confirmed payment to the booking and its instalments, then updates the status:
    /// 'confirmed' once the deposit is paid, 'paid' once everything is paid.
    /// </summary>
    public static void ApplyPayment(Booking booking, IReadOnlyList<Instalment> instalments, Payment payment, DateTimeOffset paidAt)
    {
        booking.AmountPaidCents += payment.AmountCents;

        switch (payment.Purpose)
        {
            case PaymentPurpose.Instalment:
                var inst = instalments.FirstOrDefault(i => i.Id == payment.InstalmentId);
                if (inst is not null)
                {
                    inst.Status = InstalmentStatus.Paid;
                    inst.PaidAt = paidAt;
                }
                break;
            case PaymentPurpose.Balance:
            case PaymentPurpose.Full:
                foreach (var i in instalments.Where(i => i.Status is InstalmentStatus.Due or InstalmentStatus.Overdue))
                {
                    i.Status = InstalmentStatus.Paid;
                    i.PaidAt = paidAt;
                }
                break;
        }

        booking.Status = StatusFor(booking);
        if (booking.Status != BookingStatus.Pending) booking.ExpiresAt = null;
    }

    /// <summary>
    /// Decides what to do with a payment notification from the provider. Notifications can arrive
    /// more than once, so a payment that is already complete is never applied again.
    /// </summary>
    public static NotificationDecision CheckNotification(Payment payment, int notifiedAmountCents, string notifiedStatus)
    {
        if (payment.Status == PaymentStatus.Complete) return NotificationDecision.AlreadyProcessed;
        if (!string.Equals(notifiedStatus, "COMPLETE", StringComparison.OrdinalIgnoreCase)) return NotificationDecision.NotSuccessful;
        if (notifiedAmountCents != payment.AmountCents) return NotificationDecision.AmountMismatch;
        return NotificationDecision.Apply;
    }

    public static string StatusFor(Booking booking)
    {
        if (booking.Status is BookingStatus.Cancelled or BookingStatus.Expired) return booking.Status;
        if (booking.AmountPaidCents >= booking.TotalCents) return BookingStatus.Paid;
        if (booking.DepositCents > 0 && booking.AmountPaidCents >= booking.DepositCents) return BookingStatus.Confirmed;
        return BookingStatus.Pending;
    }
}

public enum NotificationDecision
{
    Apply,
    AlreadyProcessed,
    AmountMismatch,
    NotSuccessful,
}
