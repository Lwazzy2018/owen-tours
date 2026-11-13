using OwenTours.Domain.Rules;
using Xunit;

namespace OwenTours.Domain.Tests;

public class InstalmentTests
{
    [Fact]
    public void Splits_the_balance_monthly_with_the_remainder_on_the_last_instalment()
    {
        // R6 000 total, R1 000 deposit → R5 000 over 3 instalments
        var plan = InstalmentRules.Schedule(600000, 100000, new DateOnly(2026, 11, 10), new DateOnly(2027, 1, 31));
        Assert.Equal(3, plan.Count);
        Assert.Equal(new DateOnly(2026, 12, 10), plan[0].DueDate);
        Assert.Equal(new DateOnly(2027, 1, 10), plan[1].DueDate);
        Assert.Equal(new DateOnly(2027, 1, 31), plan[2].DueDate);
        Assert.Equal(166666, plan[0].AmountCents);
        Assert.Equal(166666, plan[1].AmountCents);
        Assert.Equal(166668, plan[2].AmountCents);
        Assert.Equal(500000, plan.Sum(p => p.AmountCents));
    }

    [Fact]
    public void Last_instalment_is_due_on_the_final_payment_date()
    {
        var plan = InstalmentRules.Schedule(460000, 100000, new DateOnly(2026, 11, 10), new DateOnly(2027, 6, 30));
        Assert.Equal(new DateOnly(2027, 6, 30), plan[^1].DueDate);
        Assert.Equal(360000, plan.Sum(p => p.AmountCents));
        Assert.Equal(new[] { 1, 2, 3, 4, 5, 6, 7, 8 }, plan.Select(p => p.Sequence).ToArray());
    }

    [Fact]
    public void One_instalment_when_final_date_is_less_than_a_month_away()
    {
        var plan = InstalmentRules.Schedule(550000, 150000, new DateOnly(2026, 11, 10), new DateOnly(2026, 12, 5));
        var only = Assert.Single(plan);
        Assert.Equal(400000, only.AmountCents);
        Assert.Equal(new DateOnly(2026, 12, 5), only.DueDate);
    }

    [Fact]
    public void Never_more_than_12_instalments()
    {
        var plan = InstalmentRules.Schedule(1200000, 100000, new DateOnly(2026, 1, 1), new DateOnly(2028, 1, 1));
        Assert.Equal(12, plan.Count);
        Assert.Equal(1100000, plan.Sum(p => p.AmountCents));
    }

    [Fact]
    public void Too_late_for_instalments_throws()
    {
        Assert.Throws<BusinessRuleException>(() =>
            InstalmentRules.Schedule(460000, 100000, new DateOnly(2027, 6, 30), new DateOnly(2027, 6, 30)));
    }

    [Fact]
    public void Nothing_left_after_deposit_means_no_instalments()
    {
        Assert.Empty(InstalmentRules.Schedule(100000, 100000, new DateOnly(2026, 11, 10), new DateOnly(2027, 6, 30)));
    }

    [Fact]
    public void Rebalance_spreads_the_new_amount_over_unpaid_instalments()
    {
        var a = Guid.NewGuid();
        var b = Guid.NewGuid();
        var changes = InstalmentRules.Rebalance([(b, 3), (a, 2)], 100001);
        Assert.Equal(a, changes[0].InstalmentId);
        Assert.Equal(50000, changes[0].NewAmountCents);
        Assert.Equal(50001, changes[1].NewAmountCents);
        Assert.False(changes[0].Cancel);
    }

    [Fact]
    public void Rebalance_to_nothing_owed_cancels_unpaid_instalments()
    {
        var changes = InstalmentRules.Rebalance([(Guid.NewGuid(), 1), (Guid.NewGuid(), 2)], 0);
        Assert.True(changes.All(c => c.Cancel));
    }

    [Fact]
    public void Rebalance_never_creates_zero_rand_instalments()
    {
        var changes = InstalmentRules.Rebalance([(Guid.NewGuid(), 1), (Guid.NewGuid(), 2), (Guid.NewGuid(), 3)], 2);
        Assert.True(changes[0].Cancel);
        Assert.True(changes[1].Cancel);
        Assert.Equal(2, changes[2].NewAmountCents);
    }

    [Theory]
    [InlineData(100, 3)]
    [InlineData(500000, 7)]
    [InlineData(1, 1)]
    [InlineData(0, 4)]
    public void Split_always_adds_up(int amount, int parts)
    {
        Assert.Equal(amount, InstalmentRules.Split(amount, parts).Sum());
    }
}
