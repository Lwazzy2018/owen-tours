using OwenTours.Domain.Common;
using OwenTours.Domain.Rules;
using Xunit;
using static OwenTours.Domain.Tests.TestData;

namespace OwenTours.Domain.Tests;

public class CancellationTests
{
    private static readonly DateTimeOffset Deadline = Sast(2026, 12, 1, 23, 59);

    [Fact]
    public void Can_cancel_before_the_deadline()
    {
        var check = CancellationRules.CanCustomerCancel(Policy(deadline: Deadline), BookingStatus.Confirmed, Deadline.AddDays(-1));
        Assert.True(check.Allowed);
    }

    [Fact]
    public void Can_cancel_exactly_at_the_deadline()
    {
        var check = CancellationRules.CanCustomerCancel(Policy(deadline: Deadline), BookingStatus.Paid, Deadline);
        Assert.True(check.Allowed);
    }

    [Fact]
    public void Cannot_cancel_one_minute_after_the_deadline()
    {
        var check = CancellationRules.CanCustomerCancel(Policy(deadline: Deadline), BookingStatus.Paid, Deadline.AddMinutes(1));
        Assert.False(check.Allowed);
        Assert.Contains("1 Dec 2026, 23:59", check.Reason);
    }

    [Fact]
    public void Cannot_cancel_a_non_refundable_trip()
    {
        var check = CancellationRules.CanCustomerCancel(Policy(cancellable: false), BookingStatus.Paid, Now);
        Assert.False(check.Allowed);
        Assert.Contains("non-refundable", check.Reason);
    }

    [Fact]
    public void Cannot_cancel_twice()
    {
        var check = CancellationRules.CanCustomerCancel(Policy(deadline: Deadline), BookingStatus.Cancelled, Now);
        Assert.False(check.Allowed);
    }

    [Fact]
    public void Full_refund_keeps_the_non_refundable_deposit()
    {
        // Paid R4 600, deposit R1 000 not refundable → R3 600 back
        var refund = CancellationRules.CalculateRefund(Policy(refund: RefundType.Full), 460000, 100000);
        Assert.Equal(360000, refund);
    }

    [Fact]
    public void Full_refund_with_refundable_deposit_returns_everything()
    {
        var refund = CancellationRules.CalculateRefund(Policy(refund: RefundType.Full, depositRefundable: true), 460000, 100000);
        Assert.Equal(460000, refund);
    }

    [Fact]
    public void Partial_refund_rounds_down_to_the_cent()
    {
        // (R1 000.01 paid, no deposit) × 33% = 33 000.33 cents → 33 000 cents
        var refund = CancellationRules.CalculateRefund(Policy(refund: RefundType.Partial, percent: 33), 100001, 0);
        Assert.Equal(33000, refund);
    }

    [Fact]
    public void Partial_refund_applies_after_removing_the_deposit()
    {
        // Paid R5 500, deposit R1 500 kept, 50% of R4 000 = R2 000
        var refund = CancellationRules.CalculateRefund(Policy(refund: RefundType.Partial, percent: 50), 550000, 150000);
        Assert.Equal(200000, refund);
    }

    [Fact]
    public void No_refund_policy_returns_nothing()
    {
        Assert.Equal(0, CancellationRules.CalculateRefund(Policy(refund: RefundType.None), 460000, 100000));
    }

    [Fact]
    public void Only_deposit_paid_and_deposit_not_refundable_returns_nothing()
    {
        Assert.Equal(0, CancellationRules.CalculateRefund(Policy(refund: RefundType.Full), 100000, 100000));
    }

    [Fact]
    public void Paid_less_than_the_deposit_returns_nothing_when_deposit_not_refundable()
    {
        Assert.Equal(0, CancellationRules.CalculateRefund(Policy(refund: RefundType.Full), 50000, 100000));
    }

    [Fact]
    public void Non_cancellable_policy_never_refunds()
    {
        Assert.Equal(0, CancellationRules.CalculateRefund(Policy(cancellable: false), 460000, 0));
    }

    [Fact]
    public void Snapshot_survives_changes_to_the_departure()
    {
        var departure = Lesotho();
        var snapshot = PolicySnapshot.FromDeparture(departure);
        var json = snapshot.ToJson();

        // The admin changes the policy after the booking was made...
        departure.IsCancellable = false;
        departure.RefundType = RefundType.None;
        departure.CancellationDeadline = null;

        // ...but the booking keeps the policy it agreed to.
        var stored = PolicySnapshot.FromJson(json);
        Assert.True(stored.IsCancellable);
        Assert.Equal(RefundType.Full, stored.RefundType);
        Assert.Equal(Sast(2027, 6, 25, 23, 59), stored.CancellationDeadline);
        Assert.Equal(100000, stored.DepositPerTravellerCents);
    }

    [Fact]
    public void Snapshot_json_uses_snake_case()
    {
        var json = PolicySnapshot.FromDeparture(Lesotho()).ToJson();
        Assert.Contains("\"is_cancellable\":true", json);
        Assert.Contains("\"deposit_refundable\":false", json);
    }

    [Fact]
    public void Policy_reads_in_plain_words()
    {
        Assert.Equal("Free cancellation until 1 Dec 2026 – 100% refund, deposit not refundable.",
            CancellationRules.Describe(Policy(deadline: Deadline)));
        Assert.Equal("Cancel until 1 Dec 2026 for a 50% refund.",
            CancellationRules.Describe(Policy(refund: RefundType.Partial, percent: 50, depositRefundable: true, deadline: Deadline)));
        Assert.Equal("Non-refundable. This booking can't be cancelled.",
            CancellationRules.Describe(Policy(cancellable: false)));
    }

    [Fact]
    public void Badges()
    {
        Assert.Equal("Free cancellation", CancellationRules.Badge(Policy()));
        Assert.Equal("Partial refund", CancellationRules.Badge(Policy(refund: RefundType.Partial, percent: 50)));
        Assert.Equal("Non-refundable", CancellationRules.Badge(Policy(cancellable: false)));
    }
}
