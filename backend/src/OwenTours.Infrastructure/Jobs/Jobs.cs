using Hangfire;
using OwenTours.Application.Services;

namespace OwenTours.Infrastructure.Jobs;

/// <summary>Background jobs run by Hangfire (stored in Postgres, so they survive restarts).</summary>
public sealed class BookingJobs(BookingService bookings, ReminderService reminders)
{
    public const string ExpirePendingId = "expire-pending-bookings";
    public const string DailyRemindersId = "daily-reminders";

    /// <summary>Every minute: release seats held by unpaid bookings older than 20 minutes.</summary>
    [DisableConcurrentExecution(timeoutInSeconds: 120)]
    [AutomaticRetry(Attempts = 0)]
    public Task ExpirePendingAsync() => bookings.ExpirePendingAsync(CancellationToken.None);

    /// <summary>Daily at 07:00 SAST: overdue instalments, payment reminders, departure and passport reminders.</summary>
    [DisableConcurrentExecution(timeoutInSeconds: 1800)]
    [AutomaticRetry(Attempts = 2)]
    public Task DailyRemindersAsync() => reminders.RunDailyAsync(CancellationToken.None);

    public static void Schedule(IRecurringJobManager jobs)
    {
        jobs.AddOrUpdate<BookingJobs>(ExpirePendingId, j => j.ExpirePendingAsync(), "* * * * *");
        // 05:00 UTC = 07:00 South African time (no daylight saving).
        jobs.AddOrUpdate<BookingJobs>(DailyRemindersId, j => j.DailyRemindersAsync(), "0 5 * * *");
    }
}
