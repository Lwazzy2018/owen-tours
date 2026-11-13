using OwenTours.Domain.Common;

namespace OwenTours.Domain.Rules;

/// <summary>A special that could apply to a booking (loaded from the database).</summary>
public sealed record DiscountCandidate(
    Guid Id,
    string Name,
    string Type,
    int PercentOff,
    int? MinTravellers,
    string? PromoCode,
    int? MaxUses,
    int TimesUsed,
    DateTimeOffset StartsAt,
    DateTimeOffset EndsAt,
    bool IsActive,
    IReadOnlyCollection<Guid> TripIds);

public sealed record DiscountRequest(
    Guid TripId,
    int TravellerCount,
    int SubtotalCents,
    DateTimeOffset Now,
    string? PromoCode,
    bool WantsStudentDiscount);

public sealed record DiscountChoice(DiscountCandidate Special, int DiscountCents, string Status)
{
    public bool IsPending => Status == DiscountStatus.PendingVerification;
}

public sealed record DiscountOutcome(DiscountChoice? Choice, string? PromoCodeError);

public sealed record PriceQuote(
    int Adults,
    int Children,
    int AdultPriceCents,
    int ChildPriceCents,
    int SubtotalCents,
    DiscountChoice? Discount,
    // Discount taken off now (0 while a student discount waits for approval).
    int DiscountAppliedCents,
    int TotalCents,
    int DepositCents,
    bool InstalmentsAvailable)
{
    public int BalanceAfterDepositCents => TotalCents - DepositCents;
}

public static class Pricing
{
    public static int Subtotal(int adults, int children, int adultPriceCents, int childPriceCents)
    {
        if (adults < 0 || children < 0) throw new ArgumentOutOfRangeException(nameof(adults), "Traveller counts can't be negative.");
        if (adults + children < 1) throw new BusinessRuleException("A booking needs at least one traveller.");
        checked
        {
            return adults * adultPriceCents + children * childPriceCents;
        }
    }

    /// <summary>
    /// Picks the ONE discount that saves the most. Specials can't be combined.
    /// A student discount only counts if the customer asked for it (by uploading a student ID);
    /// it stays "pending verification" until staff approve it.
    /// </summary>
    public static DiscountOutcome ChooseDiscount(IEnumerable<DiscountCandidate> candidates, DiscountRequest req)
    {
        var enteredCode = string.IsNullOrWhiteSpace(req.PromoCode) ? null : req.PromoCode.Trim();
        var options = new List<DiscountChoice>();
        var promoMatched = false;
        string? promoError = null;

        foreach (var s in candidates)
        {
            var live = s.IsActive && req.Now >= s.StartsAt && req.Now <= s.EndsAt && s.TripIds.Contains(req.TripId);

            if (s.Type == SpecialType.PromoCode)
            {
                if (enteredCode is null || !string.Equals(s.PromoCode, enteredCode, StringComparison.OrdinalIgnoreCase))
                    continue;
                promoMatched = true;
                if (!live) { promoError = "This promo code is not valid for this trip or has expired."; continue; }
                if (s.MaxUses is not null && s.TimesUsed >= s.MaxUses) { promoError = "This promo code has been fully used."; continue; }
            }
            else if (!live)
            {
                continue;
            }

            var eligible = s.Type switch
            {
                SpecialType.Percentage => true,
                SpecialType.Group => s.MinTravellers is not null && req.TravellerCount >= s.MinTravellers,
                SpecialType.PromoCode => true,
                SpecialType.Student => req.WantsStudentDiscount,
                _ => false,
            };
            if (!eligible) continue;

            var amount = Money.PercentOf(req.SubtotalCents, s.PercentOff);
            if (amount <= 0) continue;
            var status = s.Type == SpecialType.Student ? DiscountStatus.PendingVerification : DiscountStatus.Applied;
            options.Add(new DiscountChoice(s, amount, status));
        }

        if (enteredCode is not null && !promoMatched)
            promoError = "We couldn't find that promo code.";

        var best = options
            .OrderByDescending(o => o.DiscountCents)
            .ThenBy(o => o.IsPending)              // on a tie, prefer a discount that applies right away
            .ThenBy(o => o.Special.Id)
            .FirstOrDefault();

        return new DiscountOutcome(best, promoError);
    }

    /// <summary>
    /// Builds the full price breakdown. The discount comes off the trip price BEFORE the deposit and
    /// instalments are worked out. The deposit itself is never discounted: it is the per-traveller
    /// deposit × travellers, capped at the total.
    /// </summary>
    public static PriceQuote Quote(
        int adults,
        int children,
        int adultPriceCents,
        int childPriceCents,
        int depositPerTravellerCents,
        bool departureAllowsInstalments,
        DateOnly? finalPaymentDue,
        DateOnly todayInSa,
        DiscountChoice? discount)
    {
        var subtotal = Subtotal(adults, children, adultPriceCents, childPriceCents);
        var applied = discount is { IsPending: false } ? Math.Min(discount.DiscountCents, subtotal) : 0;
        var total = subtotal - applied;
        var deposit = Math.Min(checked(depositPerTravellerCents * (adults + children)), total);
        var instalmentsAvailable = departureAllowsInstalments
                                   && finalPaymentDue is not null
                                   && finalPaymentDue.Value > todayInSa
                                   && deposit > 0
                                   && deposit < total;

        return new PriceQuote(adults, children, adultPriceCents, childPriceCents, subtotal, discount, applied,
            total, deposit, instalmentsAvailable);
    }
}
