using OwenTours.Domain.Common;

namespace OwenTours.Domain.Rules;

public sealed record PlannedInstalment(int Sequence, DateOnly DueDate, int AmountCents);

public sealed record InstalmentChange(Guid InstalmentId, int NewAmountCents, bool Cancel);

public static class InstalmentRules
{
    /// <summary>
    /// After the deposit, the rest is split into equal monthly instalments. The first is due one month
    /// after booking, and the last on the final payment due date. Any rounding remainder goes on the last one.
    /// </summary>
    public static IReadOnlyList<PlannedInstalment> Schedule(int totalCents, int depositCents, DateOnly bookingDate, DateOnly finalPaymentDue)
    {
        if (totalCents < 0 || depositCents < 0) throw new ArgumentOutOfRangeException(nameof(totalCents));
        if (depositCents > totalCents) throw new BusinessRuleException("The deposit can't be more than the total.");

        var remaining = totalCents - depositCents;
        if (remaining == 0) return [];

        if (finalPaymentDue <= bookingDate)
            throw new BusinessRuleException("It's too late to pay in instalments for this trip. Please pay in full.");

        var dates = new List<DateOnly>();
        for (var i = 1; i < BookingRules.MaxInstalments; i++)
        {
            var d = bookingDate.AddMonths(i);
            if (d >= finalPaymentDue) break;
            dates.Add(d);
        }
        dates.Add(finalPaymentDue);

        return Split(remaining, dates.Count)
            .Select((amount, i) => new PlannedInstalment(i + 1, dates[i], amount))
            .ToList();
    }

    /// <summary>
    /// Re-spreads what is still owed over the unpaid instalments (e.g. after a student discount is approved).
    /// Paid instalments are never touched. If nothing is owed any more, the unpaid instalments are cancelled.
    /// </summary>
    public static IReadOnlyList<InstalmentChange> Rebalance(IReadOnlyList<(Guid Id, int Sequence)> unpaid, int stillOwedCents)
    {
        if (unpaid.Count == 0) return [];
        var ordered = unpaid.OrderBy(u => u.Sequence).ToList();

        if (stillOwedCents <= 0)
            return ordered.Select(u => new InstalmentChange(u.Id, 0, Cancel: true)).ToList();

        var amounts = Split(stillOwedCents, ordered.Count);
        return ordered.Select((u, i) => amounts[i] == 0
                ? new InstalmentChange(u.Id, 0, Cancel: true)
                : new InstalmentChange(u.Id, amounts[i], Cancel: false))
            .ToList();
    }

    /// <summary>Equal parts with the remainder on the last part. Parts always add up exactly to the amount.</summary>
    public static int[] Split(int amountCents, int parts)
    {
        if (parts < 1) throw new ArgumentOutOfRangeException(nameof(parts));
        if (amountCents < 0) throw new ArgumentOutOfRangeException(nameof(amountCents));
        var each = amountCents / parts;
        var result = Enumerable.Repeat(each, parts).ToArray();
        result[^1] += amountCents - each * parts;
        return result;
    }
}
