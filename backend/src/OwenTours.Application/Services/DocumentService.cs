using System.Text;
using Microsoft.EntityFrameworkCore;
using OwenTours.Application.Abstractions;
using OwenTours.Application.Common;
using OwenTours.Domain.Common;
using OwenTours.Domain.Rules;

namespace OwenTours.Application.Services;

/// <summary>Invoices for customers and passenger lists for staff.</summary>
public sealed class DocumentService(IAppDbContext db, IClock clock, ICurrentUser currentUser, IPdfGenerator pdf)
{
    public async Task<(byte[] Content, string FileName)> InvoiceAsync(Guid bookingId, CancellationToken ct)
    {
        var b = await db.Bookings.AsNoTracking()
            .Include(x => x.Departure).ThenInclude(d => d!.Trip)
            .Include(x => x.Customer)
            .Include(x => x.Discount)
            .Include(x => x.Instalments)
            .FirstOrDefaultAsync(x => x.Id == bookingId, ct) ?? throw new NotFoundException("Booking");
        if (!currentUser.IsAdmin && b.CustomerId != currentUser.UserId) throw new NotFoundException("Booking");

        var company = await db.CompanySettings.AsNoTracking().FirstOrDefaultAsync(ct);
        var d = b.Departure!;
        var lines = new List<InvoiceLine>();
        if (b.Adults > 0) lines.Add(new InvoiceLine($"{d.Trip!.Title} – adult", b.Adults, d.AdultPriceCents, b.Adults * d.AdultPriceCents));
        if (b.Children > 0) lines.Add(new InvoiceLine($"{d.Trip!.Title} – child", b.Children, d.ChildPriceCents, b.Children * d.ChildPriceCents));

        var model = new InvoiceModel(
            company?.CompanyName ?? "Owen Tours and Travel", company?.RegisteredName, company?.Email, company?.Phone,
            b.Reference, clock.UtcNow, b.Customer?.FullName ?? "", d.Trip!.Title,
            $"Departs {SaTime.FormatDateTime(d.DepartureAt)} from {d.MeetingPlace}, {d.DepartureArea}, {d.DepartureProvince}. Returns {SaTime.FormatDate(d.ReturnDate)}.",
            lines, b.SubtotalCents, b.Discount?.Status == DiscountStatus.Applied ? b.Discount.SpecialName : null, b.DiscountCents,
            b.TotalCents, b.AmountPaidCents, b.BalanceCents,
            b.Instalments.OrderBy(i => i.Sequence).Select(i => (i.DueDate, i.AmountCents, i.Status)).ToList(),
            CancellationRules.Describe(PolicySnapshot.FromJson(b.CancellationPolicySnapshot)));

        return (pdf.Invoice(model), $"invoice-{b.Reference}.pdf");
    }

    public async Task<(byte[] Content, string FileName, string ContentType)> ManifestAsync(Guid departureId, string format, CancellationToken ct)
    {
        var d = await db.Departures.AsNoTracking().Include(x => x.Trip).FirstOrDefaultAsync(x => x.Id == departureId, ct)
                ?? throw new NotFoundException("Departure");
        var bookings = await db.Bookings.AsNoTracking()
            .Include(b => b.Travellers)
            .Include(b => b.Guardian)
            .Where(b => b.DepartureId == departureId && (b.Status == BookingStatus.Confirmed || b.Status == BookingStatus.Paid))
            .OrderBy(b => b.Reference)
            .ToListAsync(ct);

        var travellers = bookings.SelectMany(b => b.Travellers.OrderBy(t => t.FullName).Select(t => new ManifestTraveller(
            t.FullName,
            t.PassportNumber is not null ? $"Passport {t.PassportNumber}" : t.IdNumber is not null ? $"ID {t.IdNumber}" : null,
            t.Phone ?? b.Guardian?.GuardianPhone,
            t.IsChild,
            b.Reference,
            b.Status,
            Notes(t.SchoolGrade, t.MedicalNotes, t.Allergies, b.Guardian?.EmergencyContactName, b.Guardian?.EmergencyContactPhone,
                b.TotalCents - b.AmountPaidCents)))).ToList();

        var company = await db.CompanySettings.AsNoTracking().Select(c => c.CompanyName).FirstOrDefaultAsync(ct) ?? "Owen Tours and Travel";
        var model = new ManifestModel(company, d.Trip!.Title, d.DepartureProvince, d.DepartureArea, d.MeetingPlace,
            d.DepartureAt, d.ReturnDate, d.Capacity, travellers);
        var stamp = SaTime.ToSast(d.DepartureAt).ToString("yyyy-MM-dd");

        if (string.Equals(format, "csv", StringComparison.OrdinalIgnoreCase))
            return (Csv(model), $"passengers-{stamp}.csv", "text/csv");
        return (pdf.Manifest(model), $"passengers-{stamp}.pdf", "application/pdf");
    }

    private static string? Notes(int? grade, string? medical, string? allergies, string? emergencyName, string? emergencyPhone, int balance)
    {
        var parts = new List<string>();
        if (grade is not null) parts.Add($"Grade {grade}");
        if (!string.IsNullOrWhiteSpace(medical) && !medical.Equals("none", StringComparison.OrdinalIgnoreCase)) parts.Add($"Medical: {medical}");
        if (!string.IsNullOrWhiteSpace(allergies) && !allergies.Equals("none", StringComparison.OrdinalIgnoreCase)) parts.Add($"Allergies: {allergies}");
        if (emergencyName is not null) parts.Add($"Emergency: {emergencyName} {emergencyPhone}");
        if (balance > 0) parts.Add($"OWES {Money.FormatRand(balance)}");
        return parts.Count == 0 ? null : string.Join("; ", parts);
    }

    private static byte[] Csv(ManifestModel m)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"# {m.TripTitle} – departs {SaTime.FormatDateTime(m.DepartureAt)} from {m.MeetingPlace}, {m.DepartureArea}, {m.DepartureProvince}");
        sb.AppendLine("No,Full name,ID / passport,Phone,Child,Booking,Status,Notes");
        var n = 1;
        foreach (var t in m.Travellers)
            sb.AppendLine(string.Join(",", new[]
            {
                (n++).ToString(), t.FullName, t.Document ?? "", t.Phone ?? "", t.IsChild ? "Yes" : "No", t.BookingReference, t.BookingStatus, t.Notes ?? "",
            }.Select(CsvField)));
        // UTF-8 with BOM so Excel shows names with accents correctly.
        return [.. Encoding.UTF8.GetPreamble(), .. Encoding.UTF8.GetBytes(sb.ToString())];
    }

    private static string CsvField(string value)
    {
        // Prevent spreadsheet formula injection, then quote.
        if (value.Length > 0 && "=+-@".Contains(value[0])) value = "'" + value;
        return $"\"{value.Replace("\"", "\"\"")}\"";
    }
}
