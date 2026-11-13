using OwenTours.Domain.Common;
using OwenTours.Domain.Rules;
using Xunit;
using static OwenTours.Domain.Tests.TestData;

namespace OwenTours.Domain.Tests;

public class DepartureRulesTests
{
    [Fact]
    public void A_valid_departure_passes()
    {
        var result = DepartureRules.ValidateAndNormalise(Lesotho(), Now, isNew: true);
        Assert.True(result.IsValid);
    }

    [Fact]
    public void Cancellable_departure_needs_a_deadline()
    {
        var d = Lesotho();
        d.CancellationDeadline = null;
        var result = DepartureRules.ValidateAndNormalise(d, Now, isNew: true);
        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, e => e.Field == "cancellationDeadline");
    }

    [Fact]
    public void Deadline_must_be_before_departure()
    {
        var d = Lesotho();
        d.CancellationDeadline = d.DepartureAt.AddHours(1);
        var result = DepartureRules.ValidateAndNormalise(d, Now, isNew: true);
        Assert.Contains(result.Errors, e => e.Field == "cancellationDeadline");
    }

    [Theory]
    [InlineData(-1)]   // -1 = left empty
    [InlineData(0)]
    [InlineData(100)]
    public void Partial_refund_needs_a_percentage_between_1_and_99(int percent)
    {
        var d = Lesotho();
        d.RefundType = RefundType.Partial;
        d.RefundPercent = percent < 0 ? null : percent;
        var result = DepartureRules.ValidateAndNormalise(d, Now, isNew: true);
        Assert.Contains(result.Errors, e => e.Field == "refundPercent");
    }

    [Fact]
    public void Non_cancellable_departure_clears_refund_fields()
    {
        var d = Lesotho();
        d.IsCancellable = false;
        d.RefundType = RefundType.Partial;
        d.RefundPercent = 50;
        d.DepositRefundable = true;
        var result = DepartureRules.ValidateAndNormalise(d, Now, isNew: true);
        Assert.True(result.IsValid);
        Assert.Null(d.CancellationDeadline);
        Assert.Equal(RefundType.None, d.RefundType);
        Assert.Null(d.RefundPercent);
        Assert.False(d.DepositRefundable);
    }

    [Fact]
    public void Full_refund_ignores_a_percentage()
    {
        var d = Lesotho();
        d.RefundPercent = 40;
        DepartureRules.ValidateAndNormalise(d, Now, isNew: true);
        Assert.Null(d.RefundPercent);
    }

    [Fact]
    public void Instalments_need_a_final_due_date_before_departure()
    {
        var d = Lesotho();
        d.FinalPaymentDue = new DateOnly(2027, 7, 9);
        var result = DepartureRules.ValidateAndNormalise(d, Now, isNew: true);
        Assert.Contains(result.Errors, e => e.Field == "finalPaymentDue");
    }

    [Fact]
    public void Capacity_cannot_drop_below_seats_already_booked()
    {
        var d = Lesotho();
        d.SeatsBooked = 20;
        d.Capacity = 15;
        var result = DepartureRules.ValidateAndNormalise(d, Now, isNew: false);
        Assert.Contains(result.Errors, e => e.Field == "capacity");
    }

    [Fact]
    public void Booking_must_close_before_departure()
    {
        var d = Lesotho();
        d.BookingDeadline = d.DepartureAt.AddMinutes(1);
        var result = DepartureRules.ValidateAndNormalise(d, Now, isNew: true);
        Assert.Contains(result.Errors, e => e.Field == "bookingDeadline");
    }

    [Fact]
    public void Invalid_province_is_rejected()
    {
        var d = Lesotho();
        d.DepartureProvince = "Maseru";
        var result = DepartureRules.ValidateAndNormalise(d, Now, isNew: true);
        Assert.Contains(result.Errors, e => e.Field == "departureProvince");
    }

    [Fact]
    public void Days_before_departure_becomes_end_of_that_day_in_SA()
    {
        // Departs 9 July 2027 04:00 SAST; 14 days before = 25 June 2027 23:59:59 SAST
        var deadline = DepartureRules.DeadlineFromDaysBefore(Sast(2027, 7, 9, 4), 14);
        Assert.Equal(Sast(2027, 6, 25, 23, 59, 59), deadline);
    }

    [Fact]
    public void Zero_days_before_departure_stays_before_the_bus_leaves()
    {
        var departs = Sast(2027, 7, 9, 4);
        var deadline = DepartureRules.DeadlineFromDaysBefore(departs, 0);
        Assert.True(deadline < departs);
    }
}
