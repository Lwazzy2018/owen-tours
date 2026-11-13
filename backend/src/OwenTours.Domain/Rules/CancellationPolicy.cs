using System.Text.Json;
using System.Text.Json.Serialization;
using OwenTours.Domain.Common;
using OwenTours.Domain.Entities;

namespace OwenTours.Domain.Rules;

/// <summary>
/// The cancellation policy a customer agreed to. A copy is saved on every booking, so later
/// changes to the departure's policy never change the rules for existing bookings.
/// </summary>
public sealed record PolicySnapshot
{
    public bool IsCancellable { get; init; }
    public DateTimeOffset? CancellationDeadline { get; init; }
    public string RefundType { get; init; } = Common.RefundType.None;
    public int? RefundPercent { get; init; }
    public bool DepositRefundable { get; init; }
    public string? Notes { get; init; }
    /// <summary>Deposit per traveller at the time of booking (cents), for display.</summary>
    public int DepositPerTravellerCents { get; init; }

    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
    };

    public static PolicySnapshot FromDeparture(Departure d) => new()
    {
        IsCancellable = d.IsCancellable,
        CancellationDeadline = d.IsCancellable ? d.CancellationDeadline : null,
        RefundType = d.IsCancellable ? d.RefundType : Common.RefundType.None,
        RefundPercent = d.IsCancellable && d.RefundType == Common.RefundType.Partial ? d.RefundPercent : null,
        DepositRefundable = d.IsCancellable && d.DepositRefundable,
        Notes = d.CancellationNotes,
        DepositPerTravellerCents = d.DepositCents,
    };

    public string ToJson() => JsonSerializer.Serialize(this, Json);

    public static PolicySnapshot FromJson(string json) =>
        JsonSerializer.Deserialize<PolicySnapshot>(json, Json)
        ?? throw new InvalidOperationException("Invalid cancellation policy snapshot.");
}

public sealed record CancellationCheck(bool Allowed, string Reason);

public static class CancellationRules
{
    /// <summary>
    /// Customers may cancel only if the policy allows it and the deadline has not passed.
    /// The deadline is inclusive and exact to the minute: cancelling AT the deadline is allowed.
    /// </summary>
    public static CancellationCheck CanCustomerCancel(PolicySnapshot policy, string bookingStatus, DateTimeOffset now)
    {
        if (!BookingStatus.IsActive(bookingStatus))
            return new(false, "This booking is already cancelled or expired.");

        if (!policy.IsCancellable)
            return new(false, "This trip is non-refundable and can't be cancelled. Please contact us if something has come up.");

        if (policy.CancellationDeadline is null)
            return new(false, "This booking has no cancellation deadline. Please contact us.");

        if (now > policy.CancellationDeadline.Value)
            return new(false,
                $"This booking can no longer be cancelled. The cancellation deadline was {SaTime.FormatDateTime(policy.CancellationDeadline.Value)}.");

        return new(true, "");
    }

    /// <summary>
    /// Refund (in cents) for a cancellation. Server-side only.
    /// Refundable base = amount paid, minus the deposit if the deposit is not refundable.
    /// Full = 100% of the base, partial = base × percent / 100 (rounded down), none = 0.
    /// </summary>
    public static int CalculateRefund(PolicySnapshot policy, int amountPaidCents, int bookingDepositCents)
    {
        if (amountPaidCents < 0) throw new ArgumentOutOfRangeException(nameof(amountPaidCents));
        if (bookingDepositCents < 0) throw new ArgumentOutOfRangeException(nameof(bookingDepositCents));
        if (!policy.IsCancellable || amountPaidCents == 0) return 0;

        var nonRefundable = policy.DepositRefundable ? 0 : Math.Min(bookingDepositCents, amountPaidCents);
        var refundableBase = amountPaidCents - nonRefundable;

        return policy.RefundType switch
        {
            RefundType.Full => refundableBase,
            RefundType.Partial => Money.PercentOf(refundableBase, policy.RefundPercent ?? 0),
            _ => 0,
        };
    }

    /// <summary>The policy in plain words, as customers see it.</summary>
    public static string Describe(PolicySnapshot policy)
    {
        if (!policy.IsCancellable || policy.CancellationDeadline is null)
            return AppendNotes("Non-refundable. This booking can't be cancelled.", policy.Notes);

        var until = SaTime.FormatDate(policy.CancellationDeadline.Value);
        var depositPart = policy.DepositRefundable ? "" : ", deposit not refundable";
        var text = policy.RefundType switch
        {
            RefundType.Full => $"Free cancellation until {until} – 100% refund{depositPart}",
            RefundType.Partial => $"Cancel until {until} for a {policy.RefundPercent}% refund{depositPart}",
            _ => $"You can cancel until {until} to free your seat, but no refund is given",
        };
        return AppendNotes(text + ".", policy.Notes);
    }

    /// <summary>Short label for trip cards: "Free cancellation", "Partial refund" or "Non-refundable".</summary>
    public static string Badge(PolicySnapshot policy) =>
        !policy.IsCancellable ? "Non-refundable"
        : policy.RefundType == RefundType.Full ? "Free cancellation"
        : policy.RefundType == RefundType.Partial ? "Partial refund"
        : "Non-refundable";

    private static string AppendNotes(string text, string? notes) =>
        string.IsNullOrWhiteSpace(notes) ? text : $"{text} {notes.Trim()}";
}
