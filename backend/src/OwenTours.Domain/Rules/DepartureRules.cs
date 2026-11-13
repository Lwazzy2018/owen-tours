using OwenTours.Domain.Common;
using OwenTours.Domain.Entities;

namespace OwenTours.Domain.Rules;

public static class DepartureRules
{
    /// <summary>
    /// "X days before departure" → the exact deadline: 23:59 SAST on (departure date − X days).
    /// The app stores this exact moment, not the number of days.
    /// </summary>
    public static DateTimeOffset DeadlineFromDaysBefore(DateTimeOffset departureAt, int daysBefore)
    {
        if (daysBefore < 0) throw new ArgumentOutOfRangeException(nameof(daysBefore), "Days before departure can't be negative.");
        var departureDate = SaTime.DateInSa(departureAt);
        var deadline = SaTime.EndOfDayUtc(departureDate.AddDays(-daysBefore));
        // A deadline on the departure day itself would be after the bus leaves; keep it before departure.
        return deadline < departureAt ? deadline : departureAt.AddMinutes(-1);
    }

    /// <summary>
    /// Validates a departure and normalises the cancellation fields
    /// (e.g. a non-cancellable departure has no deadline and no refund).
    /// </summary>
    public static RuleResult ValidateAndNormalise(Departure d, DateTimeOffset now, bool isNew)
    {
        var r = new RuleResult();

        if (!Provinces.All.Contains(d.DepartureProvince))
            r.Error("departureProvince", "Choose one of the 9 South African provinces.");
        if (string.IsNullOrWhiteSpace(d.DepartureArea))
            r.Error("departureArea", "Enter the area or town the trip departs from (e.g. Mbombela).");
        if (string.IsNullOrWhiteSpace(d.MeetingPlace))
            r.Error("meetingPlace", "Enter the meeting place (e.g. Riverside Mall, main entrance).");

        if (isNew && d.DepartureAt <= now)
            r.Error("departureAt", "The departure date must be in the future.");
        if (d.ReturnDate < SaTime.DateInSa(d.DepartureAt))
            r.Error("returnDate", "The return date can't be before the departure date.");

        if (d.Capacity < 1)
            r.Error("capacity", "Capacity must be at least 1 seat.");
        if (d.Capacity < d.SeatsBooked)
            r.Error("capacity", $"{d.SeatsBooked} seats are already booked. Capacity can't be lower than that.");

        if (d.AdultPriceCents <= 0)
            r.Error("adultPriceCents", "Enter the adult price.");
        if (d.ChildPriceCents < 0)
            r.Error("childPriceCents", "The child price can't be negative.");

        if (d.BookingDeadline > d.DepartureAt)
            r.Error("bookingDeadline", "Bookings must close before the trip departs.");

        if (d.DepositCents < 0)
            r.Error("depositCents", "The deposit can't be negative.");
        if (d.DepositCents > 0 && d.DepositCents >= d.AdultPriceCents)
            r.Error("depositCents", "The deposit must be less than the adult price.");

        if (d.AllowInstalments)
        {
            if (d.DepositCents <= 0)
                r.Error("depositCents", "Instalments need a deposit amount.");
            if (d.FinalPaymentDue is null)
                r.Error("finalPaymentDue", "Instalments need a final payment due date.");
            else
            {
                if (d.FinalPaymentDue.Value >= SaTime.DateInSa(d.DepartureAt))
                    r.Error("finalPaymentDue", "The final payment must be due before the departure date.");
                if (isNew && d.FinalPaymentDue.Value < SaTime.DateInSa(now))
                    r.Error("finalPaymentDue", "The final payment due date can't be in the past.");
            }
        }
        else
        {
            d.FinalPaymentDue = null;
        }

        // Rule: cancellation policy validation.
        if (d.IsCancellable)
        {
            if (d.CancellationDeadline is null)
                r.Error("cancellationDeadline", "Choose a cancellation deadline (a date, or days before departure).");
            else if (d.CancellationDeadline.Value >= d.DepartureAt)
                r.Error("cancellationDeadline", "The cancellation deadline must be before the departure.");

            switch (d.RefundType)
            {
                case RefundType.Partial:
                    if (d.RefundPercent is null or < 1 or > 99)
                        r.Error("refundPercent", "For a partial refund, enter a percentage between 1 and 99.");
                    break;
                case RefundType.Full:
                case RefundType.None:
                    d.RefundPercent = null;
                    break;
                default:
                    r.Error("refundType", "Choose full refund, partial refund or no refund.");
                    break;
            }
        }
        else
        {
            // Non-refundable: refund fields are ignored and cleared.
            d.CancellationDeadline = null;
            d.RefundType = RefundType.None;
            d.RefundPercent = null;
            d.DepositRefundable = false;
        }

        return r;
    }
}
