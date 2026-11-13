using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using OwenTours.Application.Common;
using OwenTours.Application.Dtos;
using OwenTours.Application.Services;

namespace OwenTours.Api.Controllers;

[ApiController]
[Route("api/trips")]
[AllowAnonymous]
public sealed class TripsController(TripService trips, PastTripService pastTrips, ReviewService reviews) : ControllerBase
{
    /// <summary>Search published trips. Filters: destination, category, dates, max price, departure province/area.</summary>
    [HttpGet]
    public Task<PagedResult<TripSummaryDto>> Search([FromQuery] TripQuery query, CancellationToken ct) =>
        trips.SearchAsync(query, includeUnpublished: false, ct);

    [HttpGet("{id:guid}")]
    public Task<TripDetailDto> Get(Guid id, CancellationToken ct) => trips.GetAsync(id, includeUnpublished: false, ct);

    [HttpGet("{id:guid}/departures")]
    public Task<IReadOnlyList<DepartureDto>> Departures(Guid id, CancellationToken ct) => trips.DeparturesAsync(id, includePast: false, ct);

    [HttpGet("{id:guid}/past-trips")]
    public Task<IReadOnlyList<PastTripSummaryDto>> PastTrips(Guid id, CancellationToken ct) => pastTrips.ForTripAsync(id, ct);

    [HttpGet("{id:guid}/reviews")]
    public Task<IReadOnlyList<ReviewDto>> Reviews(Guid id, CancellationToken ct) => reviews.ForTripAsync(id, ct);

    [HttpPost("{id:guid}/reviews")]
    [Authorize]
    public Task<ReviewDto> Review(Guid id, ReviewRequest req, CancellationToken ct) => reviews.CreateAsync(id, req, ct);
}

[ApiController]
[AllowAnonymous]
public sealed class InfoController(TripService trips, CompanyService company, SpecialService specials) : ControllerBase
{
    /// <summary>Provinces and areas that have upcoming departures (for the search filters).</summary>
    [HttpGet("api/departure-locations")]
    public Task<IReadOnlyList<object>> DepartureLocations(CancellationToken ct) => trips.DepartureLocationsAsync(ct);

    [HttpGet("api/company")]
    public Task<CompanyDto> Company(CancellationToken ct) => company.GetAsync(ct);

    /// <summary>Active specials for the home screen banners.</summary>
    [HttpGet("api/specials")]
    public Task<IReadOnlyList<SpecialDto>> Specials(CancellationToken ct) => specials.ActivePublicAsync(ct);
}

[ApiController]
[Route("api/past-trips")]
[AllowAnonymous]
public sealed class PastTripsController(PastTripService pastTrips) : ControllerBase
{
    [HttpGet]
    public Task<PagedResult<PastTripSummaryDto>> List([FromQuery] string? destination, [FromQuery] bool? featured,
        [FromQuery] int? page, [FromQuery] int? pageSize, CancellationToken ct) =>
        pastTrips.ListAsync(destination, featured, includeUnpublished: false, page, pageSize, ct);

    [HttpGet("{id:guid}")]
    public Task<PastTripDetailDto> Get(Guid id, CancellationToken ct) => pastTrips.GetAsync(id, includeUnpublished: false, ct);
}

[ApiController]
[Route("api/enquiries")]
[AllowAnonymous]
public sealed class EnquiriesController(EnquiryService enquiries) : ControllerBase
{
    /// <summary>"Plan a trip with us" / free consultation. Guests allowed; rate-limited.</summary>
    [HttpPost]
    [EnableRateLimiting("enquiries")]
    public async Task<IActionResult> Create(EnquiryRequest req, CancellationToken ct)
    {
        var id = await enquiries.CreateAsync(req, ct);
        return Created($"/api/admin/enquiries/{id}", new { id });
    }
}

[ApiController]
[Route("api/me")]
[Authorize]
public sealed class MeController(CompanyService company) : ControllerBase
{
    [HttpGet]
    public Task<MeDto> Get(CancellationToken ct) => company.MeAsync(ct);

    [HttpPut]
    public Task<MeDto> Update(UpdateMeRequest req, CancellationToken ct) => company.UpdateMeAsync(req, ct);
}
