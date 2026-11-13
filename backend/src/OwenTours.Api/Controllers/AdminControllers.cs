using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using OwenTours.Api.Auth;
using OwenTours.Application.Common;
using OwenTours.Application.Dtos;
using OwenTours.Application.Services;

namespace OwenTours.Api.Controllers;

[ApiController]
[Authorize(Policy = AppClaims.AdminPolicy)]
[Route("api/admin")]
public sealed class AdminTripsController(TripService trips, DepartureService departures) : ControllerBase
{
    private const long MaxImageBytes = 15 * 1024 * 1024;

    [HttpGet("trips")]
    public Task<PagedResult<TripSummaryDto>> List([FromQuery] TripQuery q, CancellationToken ct) => trips.SearchAsync(q, includeUnpublished: true, ct);

    [HttpGet("trips/{id:guid}")]
    public Task<TripDetailDto> Get(Guid id, CancellationToken ct) => trips.GetAsync(id, includeUnpublished: true, ct);

    [HttpPost("trips")]
    public Task<TripDetailDto> Create(TripUpsertRequest req, CancellationToken ct) => trips.CreateAsync(req, ct);

    [HttpPut("trips/{id:guid}")]
    public Task<TripDetailDto> Update(Guid id, TripUpsertRequest req, CancellationToken ct) => trips.UpdateAsync(id, req, ct);

    [HttpDelete("trips/{id:guid}")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct)
    {
        await trips.DeleteAsync(id, ct);
        return NoContent();
    }

    [HttpPost("trips/{id:guid}/images")]
    [RequestSizeLimit(MaxImageBytes)]
    public async Task<TripImageDto> AddImage(Guid id, IFormFile file, CancellationToken ct)
    {
        await using var stream = file.OpenReadStream();
        return await trips.AddImageAsync(id, stream, ct);
    }

    [HttpPut("trips/{id:guid}/images/order")]
    public async Task<IActionResult> ReorderImages(Guid id, ImageOrderRequest req, CancellationToken ct)
    {
        await trips.ReorderImagesAsync(id, req, ct);
        return NoContent();
    }

    [HttpDelete("trips/{id:guid}/images/{imageId:guid}")]
    public async Task<IActionResult> DeleteImage(Guid id, Guid imageId, CancellationToken ct)
    {
        await trips.DeleteImageAsync(id, imageId, ct);
        return NoContent();
    }

    [HttpGet("trips/{id:guid}/departures")]
    public Task<IReadOnlyList<DepartureDto>> Departures(Guid id, CancellationToken ct) => trips.DeparturesAsync(id, includePast: true, ct);

    [HttpPost("trips/{id:guid}/departures")]
    public Task<DepartureDto> CreateDeparture(Guid id, DepartureUpsertRequest req, CancellationToken ct) => departures.CreateAsync(id, req, ct);

    [HttpPut("trips/{id:guid}/departures/{departureId:guid}")]
    public Task<DepartureDto> UpdateDeparture(Guid id, Guid departureId, DepartureUpsertRequest req, CancellationToken ct) =>
        departures.UpdateAsync(id, departureId, req, ct);

    /// <summary>The cancellation policy of another departure, to copy into the form.</summary>
    [HttpGet("departures/{departureId:guid}/policy")]
    public Task<object> PolicyFrom(Guid departureId, CancellationToken ct) => departures.PolicyFromAsync(departureId, ct);
}

[ApiController]
[Authorize(Policy = AppClaims.AdminPolicy)]
[Route("api/admin")]
public sealed class AdminBookingsController(BookingService bookings, DocumentService documents, DashboardService dashboard) : ControllerBase
{
    [HttpGet("dashboard")]
    public Task<DashboardDto> Dashboard(CancellationToken ct) => dashboard.GetAsync(ct);

    [HttpGet("bookings")]
    public Task<PagedResult<BookingSummaryDto>> List([FromQuery] BookingQuery q, CancellationToken ct) => bookings.SearchAsync(q, ct);

    [HttpGet("bookings/{id:guid}")]
    public Task<BookingDto> Get(Guid id, CancellationToken ct) => bookings.GetAsync(id, ct);

    /// <summary>Record money received outside the app (EFT/cash): { "action": "record_payment", "amountReceivedCents": 100000 }.</summary>
    [HttpPut("bookings/{id:guid}/status")]
    public Task<BookingDto> Status(Guid id, AdminBookingStatusRequest req, CancellationToken ct) => bookings.RecordManualPaymentAsync(id, req, ct);

    /// <summary>Staff cancellation. A reason is required; the refund can be overridden (e.g. medical emergency).</summary>
    [HttpPost("bookings/{id:guid}/cancel")]
    public Task<BookingDto> Cancel(Guid id, AdminCancelRequest req, CancellationToken ct) => bookings.CancelByStaffAsync(id, req, ct);

    /// <summary>Mark a pending refund as paid out.</summary>
    [HttpPut("bookings/{id:guid}/refund")]
    public Task<BookingDto> Refunded(Guid id, CancellationToken ct) => bookings.MarkRefundedAsync(id, ct);

    [HttpGet("departures/{id:guid}/manifest")]
    public async Task<IActionResult> Manifest(Guid id, [FromQuery] string format = "pdf", CancellationToken ct = default)
    {
        var (content, name, type) = await documents.ManifestAsync(id, format, ct);
        return File(content, type, name);
    }

    [HttpGet("discounts/pending")]
    public Task<IReadOnlyList<PendingDiscountDto>> PendingDiscounts(CancellationToken ct) => bookings.PendingDiscountsAsync(ct);

    [HttpPut("discounts/{id:guid}")]
    public Task<BookingDto> ReviewDiscount(Guid id, DiscountReviewRequest req, CancellationToken ct) => bookings.ReviewDiscountAsync(id, req, ct);
}

[ApiController]
[Authorize(Policy = AppClaims.AdminPolicy)]
[Route("api/admin/past-trips")]
public sealed class AdminPastTripsController(PastTripService pastTrips) : ControllerBase
{
    private const long MaxUploadBytes = PastTripService.MaxVideoBytes + 1024 * 1024;

    [HttpGet]
    public Task<PagedResult<PastTripSummaryDto>> List([FromQuery] string? destination, [FromQuery] int? page, [FromQuery] int? pageSize, CancellationToken ct) =>
        pastTrips.ListAsync(destination, null, includeUnpublished: true, page, pageSize, ct);

    [HttpGet("{id:guid}")]
    public Task<PastTripDetailDto> Get(Guid id, CancellationToken ct) => pastTrips.GetAsync(id, includeUnpublished: true, ct);

    [HttpPost]
    public Task<PastTripDetailDto> Create(PastTripUpsertRequest req, CancellationToken ct) => pastTrips.CreateAsync(req, ct);

    [HttpPut("{id:guid}")]
    public Task<PastTripDetailDto> Update(Guid id, PastTripUpsertRequest req, CancellationToken ct) => pastTrips.UpdateAsync(id, req, ct);

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct)
    {
        await pastTrips.DeleteAsync(id, ct);
        return NoContent();
    }

    /// <summary>Upload one photo or video (max 50 MB). Call once per file; the admin app shows a progress bar per file.</summary>
    [HttpPost("{id:guid}/media")]
    [RequestSizeLimit(MaxUploadBytes)]
    [RequestFormLimits(MultipartBodyLengthLimit = MaxUploadBytes)]
    public async Task<PastTripMediaDto> AddMedia(Guid id, IFormFile file, [FromForm] string? caption, CancellationToken ct)
    {
        await using var stream = file.OpenReadStream();
        return await pastTrips.AddMediaAsync(id, stream, file.ContentType, file.Length, caption, ct);
    }

    [HttpPut("{id:guid}/media/order")]
    public async Task<IActionResult> Order(Guid id, IReadOnlyList<MediaOrderItem> items, CancellationToken ct)
    {
        await pastTrips.ReorderMediaAsync(id, items, ct);
        return NoContent();
    }

    [HttpDelete("{id:guid}/media/{mediaId:guid}")]
    public async Task<IActionResult> DeleteMedia(Guid id, Guid mediaId, CancellationToken ct)
    {
        await pastTrips.DeleteMediaAsync(id, mediaId, ct);
        return NoContent();
    }

    [HttpPost("{id:guid}/testimonials")]
    public Task<TestimonialDto> AddTestimonial(Guid id, TestimonialRequest req, CancellationToken ct) => pastTrips.AddTestimonialAsync(id, req, ct);

    [HttpPut("{id:guid}/testimonials/{testimonialId:guid}")]
    public Task<TestimonialDto> UpdateTestimonial(Guid id, Guid testimonialId, TestimonialRequest req, CancellationToken ct) =>
        pastTrips.UpdateTestimonialAsync(id, testimonialId, req, ct);

    [HttpDelete("{id:guid}/testimonials/{testimonialId:guid}")]
    public async Task<IActionResult> DeleteTestimonial(Guid id, Guid testimonialId, CancellationToken ct)
    {
        await pastTrips.DeleteTestimonialAsync(id, testimonialId, ct);
        return NoContent();
    }
}

[ApiController]
[Authorize(Policy = AppClaims.AdminPolicy)]
[Route("api/admin")]
public sealed class AdminSettingsController(SpecialService specials, EnquiryService enquiries, CompanyService company) : ControllerBase
{
    [HttpGet("specials")]
    public Task<IReadOnlyList<SpecialDto>> Specials(CancellationToken ct) => specials.AllAsync(ct);

    [HttpPost("specials")]
    public Task<SpecialDto> CreateSpecial(SpecialUpsertRequest req, CancellationToken ct) => specials.CreateAsync(req, ct);

    [HttpPut("specials/{id:guid}")]
    public Task<SpecialDto> UpdateSpecial(Guid id, SpecialUpsertRequest req, CancellationToken ct) => specials.UpdateAsync(id, req, ct);

    [HttpDelete("specials/{id:guid}")]
    public async Task<IActionResult> DeleteSpecial(Guid id, CancellationToken ct)
    {
        await specials.DeleteAsync(id, ct);
        return NoContent();
    }

    [HttpGet("enquiries")]
    public Task<PagedResult<EnquiryDto>> Enquiries([FromQuery] string? status, [FromQuery] string? service,
        [FromQuery] int? page, [FromQuery] int? pageSize, CancellationToken ct) => enquiries.ListAsync(status, service, page, pageSize, ct);

    [HttpPut("enquiries/{id:guid}")]
    public Task<EnquiryDto> UpdateEnquiry(Guid id, EnquiryUpdateRequest req, CancellationToken ct) => enquiries.UpdateAsync(id, req, ct);

    [HttpPut("company")]
    public Task<CompanyDto> UpdateCompany(CompanyUpdateRequest req, CancellationToken ct) => company.UpdateAsync(req, ct);

    [HttpGet("staff")]
    public Task<IReadOnlyList<StaffDto>> Staff(CancellationToken ct) => company.StaffAsync(ct);

    /// <summary>Invite another admin by email (Supabase sends the invite).</summary>
    [HttpPost("staff")]
    public Task<StaffDto> InviteStaff(StaffInviteRequest req, CancellationToken ct) => company.InviteStaffAsync(req, ct);

    [HttpDelete("staff/{id:guid}")]
    public async Task<IActionResult> RemoveStaff(Guid id, CancellationToken ct)
    {
        await company.RemoveStaffAsync(id, ct);
        return NoContent();
    }
}
