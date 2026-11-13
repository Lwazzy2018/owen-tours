using OwenTours.Domain.Common;
using OwenTours.Domain.Rules;
using Xunit;
using static OwenTours.Domain.Tests.TestData;

namespace OwenTours.Domain.Tests;

public class PricingTests
{
    private static DiscountRequest Request(int travellers = 2, int subtotal = 920000, string? code = null, bool student = false) =>
        new(LesothoTripId, travellers, subtotal, Now, code, student);

    [Fact]
    public void Subtotal_adds_adults_and_children()
    {
        Assert.Equal(2 * 550000 + 400000, Pricing.Subtotal(2, 1, 550000, 400000));
    }

    [Fact]
    public void Booking_needs_at_least_one_traveller()
    {
        Assert.Throws<BusinessRuleException>(() => Pricing.Subtotal(0, 0, 100, 100));
    }

    [Fact]
    public void Picks_the_biggest_single_discount()
    {
        var ten = Special(SpecialType.Percentage, 10);
        var fifteen = Special(SpecialType.Group, 15, minTravellers: 2);
        var outcome = Pricing.ChooseDiscount([ten, fifteen], Request());
        Assert.Equal(fifteen.Id, outcome.Choice!.Special.Id);
        Assert.Equal(138000, outcome.Choice.DiscountCents);
    }

    [Fact]
    public void Group_discount_needs_enough_travellers()
    {
        var group = Special(SpecialType.Group, 15, minTravellers: 5);
        Assert.Null(Pricing.ChooseDiscount([group], Request(travellers: 4)).Choice);
        Assert.NotNull(Pricing.ChooseDiscount([group], Request(travellers: 5)).Choice);
    }

    [Fact]
    public void Special_must_be_linked_to_the_trip()
    {
        var other = Special(SpecialType.Percentage, 10, tripId: OtherTripId);
        Assert.Null(Pricing.ChooseDiscount([other], Request()).Choice);
    }

    [Fact]
    public void Expired_or_inactive_specials_do_not_apply()
    {
        var expired = Special(SpecialType.Percentage, 10, ends: Now.AddMinutes(-1));
        var future = Special(SpecialType.Percentage, 10, starts: Now.AddDays(1));
        var inactive = Special(SpecialType.Percentage, 10, active: false);
        Assert.Null(Pricing.ChooseDiscount([expired, future, inactive], Request()).Choice);
    }

    [Fact]
    public void Promo_code_is_case_insensitive()
    {
        var promo = Special(SpecialType.PromoCode, 10, code: "TEST10");
        var outcome = Pricing.ChooseDiscount([promo], Request(code: "  test10 "));
        Assert.NotNull(outcome.Choice);
        Assert.Null(outcome.PromoCodeError);
    }

    [Fact]
    public void Promo_code_respects_max_uses()
    {
        var promo = Special(SpecialType.PromoCode, 10, code: "TEST10", maxUses: 5, used: 5);
        var outcome = Pricing.ChooseDiscount([promo], Request(code: "TEST10"));
        Assert.Null(outcome.Choice);
        Assert.Equal("This promo code has been fully used.", outcome.PromoCodeError);
    }

    [Fact]
    public void Unknown_promo_code_gives_a_message()
    {
        var outcome = Pricing.ChooseDiscount([], Request(code: "NOPE"));
        Assert.Equal("We couldn't find that promo code.", outcome.PromoCodeError);
    }

    [Fact]
    public void Promo_code_is_ignored_when_not_typed()
    {
        var promo = Special(SpecialType.PromoCode, 50, code: "SECRET");
        Assert.Null(Pricing.ChooseDiscount([promo], Request()).Choice);
    }

    [Fact]
    public void Student_discount_only_when_asked_and_stays_pending()
    {
        var student = Special(SpecialType.Student, 10);
        Assert.Null(Pricing.ChooseDiscount([student], Request(student: false)).Choice);

        var outcome = Pricing.ChooseDiscount([student], Request(student: true));
        Assert.True(outcome.Choice!.IsPending);
        Assert.Equal(DiscountStatus.PendingVerification, outcome.Choice.Status);
    }

    [Fact]
    public void On_a_tie_the_discount_that_applies_now_wins()
    {
        var student = Special(SpecialType.Student, 10, id: Guid.Parse("00000000-0000-0000-0000-000000000001"));
        var percentage = Special(SpecialType.Percentage, 10, id: Guid.Parse("00000000-0000-0000-0000-000000000002"));
        var outcome = Pricing.ChooseDiscount([student, percentage], Request(student: true));
        Assert.Equal(percentage.Id, outcome.Choice!.Special.Id);
    }

    [Fact]
    public void Quote_takes_discount_before_deposit_and_never_discounts_deposit()
    {
        var discount = new DiscountChoice(Special(SpecialType.Percentage, 10), 92000, DiscountStatus.Applied);
        var q = Pricing.Quote(2, 0, 460000, 460000, 100000, true, new DateOnly(2027, 6, 30), new DateOnly(2026, 11, 10), discount);
        Assert.Equal(920000, q.SubtotalCents);
        Assert.Equal(92000, q.DiscountAppliedCents);
        Assert.Equal(828000, q.TotalCents);
        Assert.Equal(200000, q.DepositCents);          // R1 000 × 2, not discounted
        Assert.Equal(628000, q.BalanceAfterDepositCents);
        Assert.True(q.InstalmentsAvailable);
    }

    [Fact]
    public void Pending_student_discount_is_not_taken_off_yet()
    {
        var discount = new DiscountChoice(Special(SpecialType.Student, 10), 46000, DiscountStatus.PendingVerification);
        var q = Pricing.Quote(1, 0, 460000, 460000, 100000, true, new DateOnly(2027, 6, 30), new DateOnly(2026, 11, 10), discount);
        Assert.Equal(0, q.DiscountAppliedCents);
        Assert.Equal(460000, q.TotalCents);
    }

    [Fact]
    public void Deposit_is_capped_at_the_total()
    {
        var q = Pricing.Quote(1, 0, 75000, 75000, 100000, false, null, new DateOnly(2026, 11, 10), null);
        Assert.Equal(75000, q.DepositCents);
        Assert.False(q.InstalmentsAvailable);
    }

    [Fact]
    public void Instalments_not_available_after_final_due_date()
    {
        var q = Pricing.Quote(1, 0, 460000, 460000, 100000, true, new DateOnly(2026, 11, 10), new DateOnly(2026, 11, 10), null);
        Assert.False(q.InstalmentsAvailable);
    }

    [Fact]
    public void Money_formats_as_rand()
    {
        Assert.Equal("R 4 600.00", Money.FormatRand(460000));
        Assert.Equal("R 750.00", Money.FormatRand(75000));
        Assert.Equal("R 1 234 567.89", Money.FormatRand(123456789));
        Assert.Equal("R 0.05", Money.FormatRand(5));
    }

    [Fact]
    public void Percent_of_rounds_down()
    {
        Assert.Equal(3300, Money.PercentOf(10001, 33));   // 3300.33 cents → 3300
        Assert.Equal(46000, Money.PercentOf(460000, 10));
    }
}
