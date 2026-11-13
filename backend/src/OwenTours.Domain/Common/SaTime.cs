using System.Globalization;

namespace OwenTours.Domain.Common;

/// <summary>
/// South African time helpers. South Africa is always UTC+02:00 (no daylight saving),
/// so a fixed offset is used instead of time zone databases that differ between Windows and Linux.
/// Store everything in UTC; convert only for display and for "calendar date" rules.
/// </summary>
public static class SaTime
{
    public static readonly TimeSpan Offset = TimeSpan.FromHours(2);
    private static readonly CultureInfo Culture = CultureInfo.GetCultureInfo("en-ZA");

    public static DateTimeOffset ToSast(DateTimeOffset utc) => utc.ToOffset(Offset);

    /// <summary>The calendar date in South Africa at the given moment.</summary>
    public static DateOnly DateInSa(DateTimeOffset moment) => DateOnly.FromDateTime(ToSast(moment).DateTime);

    /// <summary>The moment a South African calendar date starts (00:00 SAST) as UTC.</summary>
    public static DateTimeOffset StartOfDayUtc(DateOnly date) =>
        new DateTimeOffset(date.ToDateTime(TimeOnly.MinValue), Offset).ToUniversalTime();

    /// <summary>23:59:59 SAST on the given date, as UTC.</summary>
    public static DateTimeOffset EndOfDayUtc(DateOnly date) =>
        new DateTimeOffset(date.ToDateTime(new TimeOnly(23, 59, 59)), Offset).ToUniversalTime();

    /// <summary>e.g. "1 Dec 2026, 23:59"</summary>
    public static string FormatDateTime(DateTimeOffset moment) =>
        ToSast(moment).ToString("d MMM yyyy, HH:mm", Culture);

    /// <summary>e.g. "1 Dec 2026"</summary>
    public static string FormatDate(DateTimeOffset moment) => ToSast(moment).ToString("d MMM yyyy", Culture);

    public static string FormatDate(DateOnly date) => date.ToString("d MMM yyyy", Culture);
}

public static class Money
{
    /// <summary>Formats cents as South African rand, e.g. 460000 → "R 4 600.00".</summary>
    public static string FormatRand(long cents)
    {
        var negative = cents < 0;
        var abs = Math.Abs(cents);
        var rands = abs / 100;
        var rest = abs % 100;
        // Group thousands with a space (South African style) without relying on culture data.
        var digits = rands.ToString(CultureInfo.InvariantCulture);
        var grouped = new System.Text.StringBuilder();
        for (var i = 0; i < digits.Length; i++)
        {
            if (i > 0 && (digits.Length - i) % 3 == 0) grouped.Append(' ');
            grouped.Append(digits[i]);
        }
        return $"{(negative ? "-" : "")}R {grouped}.{rest:00}";
    }

    /// <summary>Percentage of an amount in cents, always rounded DOWN to the nearest cent.</summary>
    public static int PercentOf(int cents, int percent)
    {
        if (cents < 0) throw new ArgumentOutOfRangeException(nameof(cents));
        if (percent is < 0 or > 100) throw new ArgumentOutOfRangeException(nameof(percent));
        return (int)((long)cents * percent / 100);
    }
}
