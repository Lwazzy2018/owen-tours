using OwenTours.Domain.Common;
using OwenTours.Domain.Entities;
using OwenTours.Domain.Rules;
using OwenTours.Infrastructure.Payments;
using Xunit;

namespace OwenTours.Domain.Tests;

public class PaymentRulesTests
{
    private static Booking InstalmentBooking() => new()
    {
        Id = Guid.NewGuid(),
        Status = BookingStatus.Pending,
        PaymentPlan = PaymentPlan.Instalments,
        Adults = 1,
        SubtotalCents = 460000,
        TotalCents = 460000,
        DepositCents = 100000,
        ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(20),
    };

    private static List<Instalment> Plan(Booking b) =>
    [
        new() { Id = Guid.NewGuid(), BookingId = b.Id, Sequence = 1, AmountCents = 180000, Status = InstalmentStatus.Due },
        new() { Id = Guid.NewGuid(), BookingId = b.Id, Sequence = 2, AmountCents = 180000, Status = InstalmentStatus.Due },
    ];

    [Fact]
    public void Deposit_first_then_instalments()
    {
        var b = InstalmentBooking();
        var plan = Plan(b);
        Assert.Throws<BusinessRuleException>(() => PaymentRules.Resolve(b, plan, "next_instalment"));

        var deposit = PaymentRules.Resolve(b, plan, "deposit");
        Assert.Equal(PaymentPurpose.Deposit, deposit.Purpose);
        Assert.Equal(100000, deposit.AmountCents);
    }

    [Fact]
    public void Paying_the_deposit_confirms_the_booking()
    {
        var b = InstalmentBooking();
        var plan = Plan(b);
        PaymentRules.ApplyPayment(b, plan, new Payment { Purpose = PaymentPurpose.Deposit, AmountCents = 100000 }, DateTimeOffset.UtcNow);
        Assert.Equal(BookingStatus.Confirmed, b.Status);
        Assert.Null(b.ExpiresAt);

        var next = PaymentRules.Resolve(b, plan, "next_instalment");
        Assert.Equal(plan[0].Id, next.InstalmentId);
        Assert.Equal(180000, next.AmountCents);
    }

    [Fact]
    public void Paying_everything_marks_the_booking_paid()
    {
        var b = InstalmentBooking();
        var plan = Plan(b);
        var now = DateTimeOffset.UtcNow;
        PaymentRules.ApplyPayment(b, plan, new Payment { Purpose = PaymentPurpose.Deposit, AmountCents = 100000 }, now);
        PaymentRules.ApplyPayment(b, plan, new Payment { Purpose = PaymentPurpose.Instalment, AmountCents = 180000, InstalmentId = plan[0].Id }, now);
        Assert.Equal(BookingStatus.Confirmed, b.Status);
        Assert.Equal(InstalmentStatus.Paid, plan[0].Status);

        var balance = PaymentRules.Resolve(b, plan, "balance");
        Assert.Equal(180000, balance.AmountCents);
        PaymentRules.ApplyPayment(b, plan, new Payment { Purpose = PaymentPurpose.Balance, AmountCents = 180000 }, now);
        Assert.Equal(BookingStatus.Paid, b.Status);
        Assert.True(plan.All(i => i.Status == InstalmentStatus.Paid));
        Assert.Throws<BusinessRuleException>(() => PaymentRules.Resolve(b, plan, "balance"));
    }

    [Fact]
    public void Cannot_pay_a_cancelled_booking()
    {
        var b = InstalmentBooking();
        b.Status = BookingStatus.Cancelled;
        var ex = Assert.Throws<BusinessRuleException>(() => PaymentRules.Resolve(b, [], "deposit"));
        Assert.Equal(409, ex.StatusCode);
    }

    [Fact]
    public void Full_payment_only_when_nothing_paid_yet()
    {
        var b = InstalmentBooking();
        b.PaymentPlan = PaymentPlan.Full;
        Assert.Equal(460000, PaymentRules.Resolve(b, [], "full").AmountCents);
        b.AmountPaidCents = 1000;
        Assert.Throws<BusinessRuleException>(() => PaymentRules.Resolve(b, [], "full"));
    }

    [Fact]
    public void Webhook_is_idempotent()
    {
        var payment = new Payment { AmountCents = 100000, Status = PaymentStatus.Pending };
        Assert.Equal(NotificationDecision.Apply, PaymentRules.CheckNotification(payment, 100000, "COMPLETE"));

        payment.Status = PaymentStatus.Complete;   // first notification processed
        Assert.Equal(NotificationDecision.AlreadyProcessed, PaymentRules.CheckNotification(payment, 100000, "COMPLETE"));
    }

    [Fact]
    public void Webhook_rejects_a_different_amount_or_failed_payment()
    {
        var payment = new Payment { AmountCents = 100000, Status = PaymentStatus.Pending };
        Assert.Equal(NotificationDecision.AmountMismatch, PaymentRules.CheckNotification(payment, 99999, "COMPLETE"));
        Assert.Equal(NotificationDecision.NotSuccessful, PaymentRules.CheckNotification(payment, 100000, "CANCELLED"));
    }

    [Fact]
    public void PayFast_encoding_matches_php_urlencode()
    {
        Assert.Equal("Owen+Tours+%26+Travels", PayFastSignature.Encode("Owen Tours & Travels"));
        Assert.Equal("a-b_c.d%21%2A%28%29", PayFastSignature.Encode("a-b_c.d!*()"));
        Assert.Equal("https%3A%2F%2Fx.co%2Fpay", PayFastSignature.Encode("https://x.co/pay"));
    }

    [Fact]
    public void PayFast_signature_round_trip()
    {
        var fields = new List<KeyValuePair<string, string>>
        {
            new("m_payment_id", "abc"),
            new("pf_payment_id", "123"),
            new("payment_status", "COMPLETE"),
            new("amount_gross", "1000.00"),
        };
        var signature = PayFastSignature.ForRequest(fields.Select(f => new KeyValuePair<string, string?>(f.Key, f.Value)), "secret pass");
        fields.Add(new("signature", signature));

        Assert.True(PayFastSignature.VerifyNotification(fields, "secret pass"));
        Assert.False(PayFastSignature.VerifyNotification(fields, "wrong"));

        fields[3] = new("amount_gross", "1.00");     // tampered amount
        Assert.False(PayFastSignature.VerifyNotification(fields, "secret pass"));
    }

    [Fact]
    public void PayFast_signature_has_known_value()
    {
        // Empty fields are skipped; the rest are joined in order and MD5-hashed.
        var sig = PayFastSignature.ForRequest(
            [new("merchant_id", "10000100"), new("amount", "100.00"), new("empty", "")], null);
        Assert.Equal(32, sig.Length);
        Assert.Equal(System.Convert.ToHexString(System.Security.Cryptography.MD5.HashData(
            System.Text.Encoding.UTF8.GetBytes("merchant_id=10000100&amount=100.00"))).ToLowerInvariant(), sig);
    }
}
