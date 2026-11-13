using OwenTours.Application.Abstractions;
using OwenTours.Domain.Common;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace OwenTours.Infrastructure.Pdf;

/// <summary>
/// Invoices and passenger lists. QuestPDF's Community licence is free for businesses
/// with under USD 1M annual revenue – check https://www.questpdf.com/license/ before launch.
/// </summary>
public sealed class QuestPdfGenerator : IPdfGenerator
{
    private const string DeepBlue = "#063B4C";
    private const string Teal = "#007C91";
    private const string Sand = "#F7E7CE";
    private const string Grey = "#5B6B73";
    private const string Border = "#E3EAED";

    static QuestPdfGenerator()
    {
        QuestPDF.Settings.License = LicenseType.Community;
    }

    public byte[] Invoice(InvoiceModel m) => Document.Create(doc =>
    {
        doc.Page(page =>
        {
            page.Size(PageSizes.A4);
            page.Margin(36);
            page.DefaultTextStyle(t => t.FontSize(10).FontColor(DeepBlue));

            page.Header().Row(row =>
            {
                row.RelativeItem().Column(c =>
                {
                    c.Item().Text(m.CompanyName).FontSize(20).Bold();
                    if (m.RegisteredName is not null) c.Item().Text(m.RegisteredName).FontColor(Grey);
                    c.Item().Text(string.Join("  ·  ", new[] { m.CompanyPhone, m.CompanyEmail }.Where(x => !string.IsNullOrEmpty(x)))).FontColor(Grey);
                });
                row.ConstantItem(180).AlignRight().Column(c =>
                {
                    c.Item().AlignRight().Text("INVOICE").FontSize(18).Bold().FontColor(Teal);
                    c.Item().AlignRight().Text($"Booking {m.BookingReference}");
                    c.Item().AlignRight().Text($"Issued {SaTime.FormatDate(m.IssuedAt)}").FontColor(Grey);
                });
            });

            page.Content().PaddingVertical(16).Column(col =>
            {
                col.Spacing(10);
                col.Item().Background(Sand).Padding(10).Column(c =>
                {
                    c.Item().Text($"Billed to: {m.CustomerName}").Bold();
                    c.Item().Text(m.TripTitle).FontSize(12).Bold();
                    c.Item().Text(m.DepartureSummary);
                });

                col.Item().Table(t =>
                {
                    t.ColumnsDefinition(c =>
                    {
                        c.RelativeColumn(5);
                        c.RelativeColumn(1);
                        c.RelativeColumn(2);
                        c.RelativeColumn(2);
                    });
                    t.Header(h =>
                    {
                        foreach (var title in new[] { "Description", "Qty", "Unit price", "Amount" })
                            h.Cell().BorderBottom(1).BorderColor(DeepBlue).PaddingVertical(4).Text(title).Bold();
                    });
                    foreach (var line in m.Lines)
                    {
                        t.Cell().BorderBottom(1).BorderColor(Border).PaddingVertical(4).Text(line.Description);
                        t.Cell().BorderBottom(1).BorderColor(Border).PaddingVertical(4).Text(line.Quantity.ToString());
                        t.Cell().BorderBottom(1).BorderColor(Border).PaddingVertical(4).Text(Money.FormatRand(line.UnitCents));
                        t.Cell().BorderBottom(1).BorderColor(Border).PaddingVertical(4).AlignRight().Text(Money.FormatRand(line.TotalCents));
                    }
                });

                col.Item().AlignRight().Width(240).Column(c =>
                {
                    void Line(string label, int cents, bool bold = false)
                    {
                        c.Item().Row(r =>
                        {
                            var l = r.RelativeItem().Text(label);
                            var v = r.ConstantItem(110).AlignRight().Text(Money.FormatRand(cents));
                            if (bold) { l.Bold(); v.Bold(); }
                        });
                    }
                    Line("Subtotal", m.SubtotalCents);
                    if (m.DiscountCents > 0) Line($"Discount ({m.DiscountName})", -m.DiscountCents);
                    Line("Total", m.TotalCents, bold: true);
                    Line("Paid", m.PaidCents);
                    Line("Balance due", m.BalanceCents, bold: true);
                });

                if (m.Instalments.Count > 0)
                {
                    col.Item().PaddingTop(8).Text("Payment plan").Bold().FontSize(12);
                    col.Item().Table(t =>
                    {
                        t.ColumnsDefinition(c =>
                        {
                            c.RelativeColumn();
                            c.RelativeColumn();
                            c.RelativeColumn();
                        });
                        foreach (var (due, amount, status) in m.Instalments)
                        {
                            t.Cell().PaddingVertical(2).Text(SaTime.FormatDate(due));
                            t.Cell().PaddingVertical(2).Text(Money.FormatRand(amount));
                            t.Cell().PaddingVertical(2).Text(status);
                        }
                    });
                }

                col.Item().PaddingTop(8).Text("Cancellation policy").Bold().FontSize(12);
                col.Item().Text(m.CancellationPolicy);
            });

            page.Footer().AlignCenter().Text(t =>
            {
                t.Span("Thank you for travelling with us – Explore the World. ").FontColor(Grey);
                t.CurrentPageNumber().FontColor(Grey);
            });
        });
    }).GeneratePdf();

    public byte[] Manifest(ManifestModel m) => Document.Create(doc =>
    {
        doc.Page(page =>
        {
            page.Size(PageSizes.A4.Landscape());
            page.Margin(28);
            page.DefaultTextStyle(t => t.FontSize(9).FontColor(DeepBlue));

            page.Header().Column(c =>
            {
                c.Item().Text($"{m.CompanyName} – Passenger list").FontSize(16).Bold();
                c.Item().Text(m.TripTitle).FontSize(13).Bold().FontColor(Teal);
                c.Item().Background(Sand).Padding(6).Text(
                    $"Departs {SaTime.FormatDateTime(m.DepartureAt)} from {m.MeetingPlace}, {m.DepartureArea}, {m.DepartureProvince}  ·  " +
                    $"Returns {SaTime.FormatDate(m.ReturnDate)}  ·  {m.Travellers.Count} of {m.Capacity} seats");
            });

            page.Content().PaddingTop(10).Table(t =>
            {
                t.ColumnsDefinition(c =>
                {
                    c.ConstantColumn(24);
                    c.RelativeColumn(3);
                    c.RelativeColumn(2.5f);
                    c.RelativeColumn(2);
                    c.ConstantColumn(36);
                    c.RelativeColumn(1.5f);
                    c.RelativeColumn(4);
                    c.ConstantColumn(40);
                });
                t.Header(h =>
                {
                    foreach (var title in new[] { "#", "Name", "ID / passport", "Phone", "Child", "Booking", "Notes", "Here" })
                        h.Cell().BorderBottom(1).BorderColor(DeepBlue).PaddingVertical(3).Text(title).Bold();
                });
                var n = 1;
                foreach (var p in m.Travellers)
                {
                    t.Cell().BorderBottom(1).BorderColor(Border).PaddingVertical(3).Text((n++).ToString());
                    t.Cell().BorderBottom(1).BorderColor(Border).PaddingVertical(3).Text(p.FullName);
                    t.Cell().BorderBottom(1).BorderColor(Border).PaddingVertical(3).Text(p.Document ?? "");
                    t.Cell().BorderBottom(1).BorderColor(Border).PaddingVertical(3).Text(p.Phone ?? "");
                    t.Cell().BorderBottom(1).BorderColor(Border).PaddingVertical(3).Text(p.IsChild ? "Yes" : "");
                    t.Cell().BorderBottom(1).BorderColor(Border).PaddingVertical(3).Text(p.BookingReference);
                    t.Cell().BorderBottom(1).BorderColor(Border).PaddingVertical(3).Text(p.Notes ?? "");
                    t.Cell().BorderBottom(1).BorderColor(Border).PaddingVertical(3).Text("☐");
                }
            });

            page.Footer().AlignRight().Text(t =>
            {
                t.Span("Confidential – contains personal information (POPIA). Page ").FontColor(Grey);
                t.CurrentPageNumber().FontColor(Grey);
            });
        });
    }).GeneratePdf();
}
