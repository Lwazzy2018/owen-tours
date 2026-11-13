using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using OwenTours.Application.Dtos;
using OwenTours.Application.Services;

namespace OwenTours.Api.Controllers;

[ApiController]
[Route("api/bookings")]
[Authorize]
public sealed class BookingsController(BookingService bookings, PaymentService payments, DocumentService documents) : ControllerBase
{
    private const long MaxStudentIdBytes = 10 * 1024 * 1024;

    /// <summary>Price, discount, deposit and instalment plan – before booking. No sign-in needed.</summary>
    [HttpPost("price-preview")]
    [AllowAnonymous]
    public Task<PricePreviewDto> Preview(PricePreviewRequest req, CancellationToken ct) => bookings.PreviewAsync(req, ct);

    /// <summary>Creates a pending booking and holds the seats for 20 minutes while the customer pays.</summary>
    [HttpPost]
    [EnableRateLimiting("bookings")]
    public async Task<ActionResult<CreateBookingResponse>> Create(CreateBookingRequest req, CancellationToken ct)
    {
        var result = await bookings.CreateAsync(req, ct);
        return CreatedAtAction(nameof(Get), new { id = result.Booking.Id }, result);
    }

    [HttpGet("me")]
    public Task<IReadOnlyList<BookingSummaryDto>> Mine(CancellationToken ct) => bookings.MineAsync(ct);

    [HttpGet("{id:guid}")]
    public Task<BookingDto> Get(Guid id, CancellationToken ct) => bookings.GetAsync(id, ct);

    /// <summary>Starts a payment. Type: full, deposit, next_instalment or balance. Returns a PayFast form to POST.</summary>
    [HttpPost("{id:guid}/pay")]
    public async Task<PaymentRedirectDto> Pay(Guid id, PayRequest req, CancellationToken ct)
    {
        var result = await payments.StartAsync(id, req, ct);
        return result with { CheckoutUrl = $"{Request.Scheme}://{Request.Host}/api/payments/{result.PaymentId}/checkout" };
    }

    /// <summary>Whether the booking can be cancelled now, and exactly how much would be refunded.</summary>
    [HttpGet("{id:guid}/cancel-preview")]
    public Task<CancelPreviewDto> CancelPreview(Guid id, CancellationToken ct) => bookings.CancelPreviewAsync(id, ct);

    [HttpPost("{id:guid}/cancel")]
    public Task<BookingDto> Cancel(Guid id, CancelRequest req, CancellationToken ct) => bookings.CancelByCustomerAsync(id, req, ct);

    [HttpGet("{id:guid}/invoice")]
    public async Task<IActionResult> Invoice(Guid id, CancellationToken ct)
    {
        var (content, name) = await documents.InvoiceAsync(id, ct);
        return File(content, "application/pdf", name);
    }

    /// <summary>Upload a photo of a valid student ID for a student discount. Staff approve it.</summary>
    [HttpPost("{id:guid}/student-id")]
    [RequestSizeLimit(MaxStudentIdBytes)]
    public async Task<IActionResult> StudentId(Guid id, IFormFile file, CancellationToken ct)
    {
        if (file.Length == 0 || file.Length > MaxStudentIdBytes)
            return Problem(statusCode: 413, title: "File too large", detail: "Please upload a photo smaller than 10 MB.");
        await using var stream = file.OpenReadStream();
        await bookings.UploadStudentIdAsync(id, stream, ct);
        return NoContent();
    }
}

[ApiController]
[Route("api/payments")]
[AllowAnonymous]
public sealed class PaymentsController(PaymentService payments) : ControllerBase
{
    /// <summary>PayFast ITN (payment notification). PayFast calls this; it must always get 200 OK.</summary>
    [HttpPost("payfast/notify")]
    [Consumes("application/x-www-form-urlencoded")]
    [ApiExplorerSettings(IgnoreApi = true)]
    public async Task<IActionResult> PayFastNotify(CancellationToken ct)
    {
        var form = await Request.ReadFormAsync(ct);
        // Keep PayFast's field order: the signature depends on it.
        var fields = form.Select(kv => new KeyValuePair<string, string>(kv.Key, kv.Value.ToString())).ToList();
        await payments.HandleNotificationAsync(fields, HttpContext.Connection.RemoteIpAddress?.ToString(), ct);
        return Ok();
    }

    /// <summary>Auto-submitting form that forwards the customer to PayFast.</summary>
    [HttpGet("{paymentId:guid}/checkout")]
    public async Task<ContentResult> Checkout(Guid paymentId, CancellationToken ct) => new()
    {
        ContentType = "text/html; charset=utf-8",
        Content = await payments.CheckoutHtmlAsync(paymentId, ct),
    };

    /// <summary>PayFast sends the customer here after paying. The app closes its payment screen when it sees this URL.</summary>
    [HttpGet("return")]
    public ContentResult Return() => Page("Payment received", "Thank you! You can close this page and go back to the app. Your booking updates in a few seconds.");

    [HttpGet("cancel")]
    public ContentResult CancelPage() => Page("Payment cancelled", "No money was taken. You can close this page and try again from My Trips.");

    private static ContentResult Page(string title, string text) => new()
    {
        ContentType = "text/html; charset=utf-8",
        Content = $"""
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>{title}</title></head>
            <body style="font-family:sans-serif;background:#F7E7CE;color:#063B4C;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0">
            <div style="background:#fff;padding:32px;border-radius:16px;max-width:420px;text-align:center">
            <h1 style="margin-top:0">{title}</h1><p>{text}</p></div></body></html>
            """,
    };
}
