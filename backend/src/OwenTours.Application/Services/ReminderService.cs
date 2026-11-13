using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using OwenTours.Application.Abstractions;
using OwenTours.Domain.Common;

namespace OwenTours.Application.Services;

/// <summary>Daily reminders. Every message has a dedupe key, so running the job twice never sends twice.</summary>
public sealed class ReminderService(IAppDbContext db, IClock clock, NotificationService notifications, ILogger<ReminderService> logger)
{
    public const int InstalmentReminderDaysBefore = 3;
    public const int PassportReminderDaysBefore = 30;

    public async Task RunDailyAsync(CancellationToken ct)
    {
        var today = SaTime.DateInSa(clock.UtcNow);
        var overdue = await MarkOverdueAsync(today, ct);
        var instalments = await InstalmentRemindersAsync(today, ct);
        var departures = await DepartureRemindersAsync(today, ct);
        var passports = await PassportRemindersAsync(today, ct);
        logger.LogInformation(
            "Daily reminders: {Overdue} instalments marked overdue, {Instalments} instalment reminders, {Departures} departure reminders, {Passports} passport reminders",
            overdue, instalments, departures, passports);
    }

    public async Task<int> MarkOverdueAsync(DateOnly today, CancellationToken ct)
    {
        var rows = await db.Instalments
            .Where(i => i.Status == InstalmentStatus.Due && i.DueDate < today)
            .Join(db.Bookings, i => i.BookingId, b => b.Id, (i, b) => new { i, b })
            .Where(x => x.b.Status == BookingStatus.Confirmed || x.b.Status == BookingStatus.Pending)
            .Select(x => new { x.i.Id, x.b.CustomerId, x.b.Reference, BookingId = x.b.Id, x.i.AmountCents, x.i.DueDate })
            .ToListAsync(ct);

        foreach (var r in rows)
        {
            await db.Instalments.Where(i => i.Id == r.Id && i.Status == InstalmentStatus.Due)
                .ExecuteUpdateAsync(s => s.SetProperty(i => i.Status, InstalmentStatus.Overdue), ct);
            await notifications.NotifyUserAsync(r.CustomerId, r.BookingId, "instalment_overdue",
                $"Payment overdue – {r.Reference}",
                $"Your instalment of {Money.FormatRand(r.AmountCents)} for booking {r.Reference} was due on {SaTime.FormatDate(r.DueDate)}. " +
                "Please pay it in the app as soon as possible to keep your seat, or contact us if you need help.",
                $"instalment-overdue:{r.Id}", ct);
        }
        return rows.Count;
    }

    public async Task<int> InstalmentRemindersAsync(DateOnly today, CancellationToken ct)
    {
        var target = today.AddDays(InstalmentReminderDaysBefore);
        var rows = await db.Instalments.AsNoTracking()
            .Where(i => i.Status == InstalmentStatus.Due && i.DueDate == target)
            .Join(db.Bookings, i => i.BookingId, b => b.Id, (i, b) => new { i, b })
            .Where(x => x.b.Status == BookingStatus.Confirmed)
            .Select(x => new { x.i.Id, x.b.CustomerId, x.b.Reference, BookingId = x.b.Id, x.i.AmountCents, x.i.DueDate })
            .ToListAsync(ct);

        var sent = 0;
        foreach (var r in rows)
        {
            if (await notifications.NotifyUserAsync(r.CustomerId, r.BookingId, "instalment_reminder",
                    $"Instalment due in {InstalmentReminderDaysBefore} days – {r.Reference}",
                    $"Friendly reminder: your instalment of {Money.FormatRand(r.AmountCents)} for booking {r.Reference} " +
                    $"is due on {SaTime.FormatDate(r.DueDate)}. You can pay in the app under My Trips.",
                    $"instalment-reminder:{r.Id}", ct))
                sent++;
        }
        return sent;
    }

    public async Task<int> DepartureRemindersAsync(DateOnly today, CancellationToken ct)
    {
        var tomorrowStart = SaTime.StartOfDayUtc(today.AddDays(1));
        var tomorrowEnd = SaTime.EndOfDayUtc(today.AddDays(1));
        var rows = await db.Bookings.AsNoTracking()
            .Where(b => b.Status == BookingStatus.Confirmed || b.Status == BookingStatus.Paid)
            .Where(b => b.Departure!.DepartureAt >= tomorrowStart && b.Departure.DepartureAt <= tomorrowEnd && !b.Departure.IsCancelledByCompany)
            .Select(b => new
            {
                b.Id, b.CustomerId, b.Reference, b.TotalCents, b.AmountPaidCents,
                b.Departure!.DepartureAt, b.Departure.MeetingPlace, b.Departure.DepartureArea, b.Departure.DepartureProvince,
                TripTitle = b.Departure.Trip!.Title,
            })
            .ToListAsync(ct);

        var sent = 0;
        foreach (var r in rows)
        {
            var balance = r.TotalCents - r.AmountPaidCents;
            var body = $"See you tomorrow! {r.TripTitle} departs at {SaTime.ToSast(r.DepartureAt):HH:mm} from {r.MeetingPlace}, " +
                       $"{r.DepartureArea}, {r.DepartureProvince}. Please arrive 15 minutes early and bring your ID or passport." +
                       (balance > 0 ? $" Note: {Money.FormatRand(balance)} is still outstanding on booking {r.Reference}." : "");
            if (await notifications.NotifyUserAsync(r.CustomerId, r.Id, "departure_reminder",
                    $"Your trip departs tomorrow – {r.Reference}", body, $"departure-reminder:{r.Id}", ct))
                sent++;
        }
        return sent;
    }

    public async Task<int> PassportRemindersAsync(DateOnly today, CancellationToken ct)
    {
        var start = SaTime.StartOfDayUtc(today.AddDays(PassportReminderDaysBefore));
        var end = SaTime.EndOfDayUtc(today.AddDays(PassportReminderDaysBefore));
        var rows = await db.Bookings.AsNoTracking()
            .Where(b => b.Status == BookingStatus.Confirmed || b.Status == BookingStatus.Paid)
            .Where(b => b.Departure!.DepartureAt >= start && b.Departure.DepartureAt <= end)
            .Where(b => b.Departure!.Trip!.DestinationCountry != "South Africa")
            .Select(b => new { b.Id, b.CustomerId, b.Reference, b.Children, Country = b.Departure!.Trip!.DestinationCountry, b.Departure.DepartureAt })
            .ToListAsync(ct);

        var sent = 0;
        foreach (var r in rows)
        {
            var body = $"Your trip to {r.Country} is 30 days away (booking {r.Reference}). Please check that every traveller's " +
                       "passport is valid and with you." +
                       (r.Children > 0
                           ? " Children travelling across the border may need extra documents (such as a birth certificate and parental consent). Contact us if you're unsure."
                           : "");
            if (await notifications.NotifyUserAsync(r.CustomerId, r.Id, "passport_reminder",
                    $"Passport check – {r.Reference}", body, $"passport-reminder:{r.Id}", ct))
                sent++;
        }
        return sent;
    }
}
