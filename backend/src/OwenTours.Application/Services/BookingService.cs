using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using OwenTours.Application.Abstractions;
using OwenTours.Application.Common;
using OwenTours.Application.Dtos;
using OwenTours.Domain.Common;
using OwenTours.Domain.Entities;
using OwenTours.Domain.Rules;

namespace OwenTours.Application.Services;

public sealed class BookingService(
    IAppDbContext db,
    IClock clock,
    ICurrentUser currentUser,
    AuditLogger audit,
    NotificationService notifications,
    IFileStorage storage,
    IImageProcessor images,
    ILogger<BookingService> logger)
{
    public const string StudentIdBucket = "student-ids";

    // ======================================================================
    // Price preview (no booking is created)
    // ======================================================================

    public async Task<PricePreviewDto> PreviewAsync(PricePreviewRequest req, CancellationToken ct)
    {
        var now = clock.UtcNow;
        var departure = await LoadBookableDepartureAsync(req.DepartureId, ct);
        var discount = await ChooseDiscountAsync(departure, req.Adults + req.Children,
            Pricing.Subtotal(req.Adults, req.Children, departure.AdultPriceCents, departure.ChildPriceCents),
            req.PromoCode, req.WantsStudentDiscount, ct);

        var quote = Pricing.Quote(req.Adults, req.Children, departure.AdultPriceCents, departure.ChildPriceCents,
            departure.DepositCents, departure.AllowInstalments, departure.FinalPaymentDue, SaTime.DateInSa(now), discount.Choice);

        var plan = quote.InstalmentsAvailable
            ? InstalmentRules.Schedule(quote.TotalCents, quote.DepositCents, SaTime.DateInSa(now), departure.FinalPaymentDue!.Value)
                .Select(p => new PlannedInstalmentDto(p.Sequence, p.DueDate, p.AmountCents)).ToList()
            : [];

        return new PricePreviewDto(
            quote.Adults, quote.Children, quote.AdultPriceCents, quote.ChildPriceCents, quote.SubtotalCents,
            discount.Choice?.Special.Name, discount.Choice?.Special.PercentOff,
            discount.Choice?.DiscountCents ?? 0, discount.Choice?.IsPending ?? false,
            quote.TotalCents, quote.DepositCents, quote.BalanceAfterDepositCents, quote.InstalmentsAvailable, plan,
            discount.PromoCodeError,
            CancellationRules.Describe(PolicySnapshot.FromDeparture(departure)),
            departure.SeatsLeft);
    }

    // ======================================================================
    // Create a booking
    // ======================================================================

    public async Task<CreateBookingResponse> CreateAsync(CreateBookingRequest req, CancellationToken ct)
    {
        var userId = currentUser.RequireUserId();
        var now = clock.UtcNow;
        var today = SaTime.DateInSa(now);

        if (!req.AcceptedCancellationPolicy)
            throw new BusinessRuleException("Please read and agree to the cancellation policy before booking.", 422,
                [new RuleMessage("acceptedCancellationPolicy", "You must agree to the cancellation policy.")]);
        if (req.PaymentPlan is not (PaymentPlan.Full or PaymentPlan.Instalments))
            throw new BusinessRuleException("Choose to pay in full or with a deposit and instalments.", 400);

        var departure = await LoadBookableDepartureAsync(req.DepartureId, ct);
        var trip = departure.Trip!;

        // ---- Travellers and trip rules ----
        var inputs = req.Travellers.Select(t => new TravellerInput(
            t.FullName.Trim(), Clean(t.IdNumber), Clean(t.PassportNumber), t.PassportExpiry, Clean(t.Phone), t.IsChild,
            t.DateOfBirth, t.SchoolGrade, Clean(t.MedicalNotes), Clean(t.Allergies))).ToList();
        var guardian = req.Guardian is null ? null : new GuardianInput(
            req.Guardian.GuardianName.Trim(), req.Guardian.GuardianPhone.Trim(), req.Guardian.GuardianRelationship.Trim(),
            req.Guardian.EmergencyContactName.Trim(), req.Guardian.EmergencyContactPhone.Trim(), req.Guardian.ConsentGiven);

        var rules = TravellerRules.Validate(
            new TripRuleInfo(trip.Audience, trip.MinGrade, trip.MaxGrade, trip.IsCrossBorderTrip),
            SaTime.DateInSa(departure.DepartureAt), departure.ReturnDate, inputs, guardian);
        if (!rules.IsValid) throw BusinessRuleException.From(rules);

        var adults = inputs.Count(t => !t.IsChild);
        var children = inputs.Count(t => t.IsChild);

        // ---- Price (server only) ----
        var subtotal = Pricing.Subtotal(adults, children, departure.AdultPriceCents, departure.ChildPriceCents);
        var discount = await ChooseDiscountAsync(departure, adults + children, subtotal, req.PromoCode, req.WantsStudentDiscount, ct);
        if (discount.PromoCodeError is not null)
            throw new BusinessRuleException(discount.PromoCodeError, 422, [new RuleMessage("promoCode", discount.PromoCodeError)]);

        var quote = Pricing.Quote(adults, children, departure.AdultPriceCents, departure.ChildPriceCents,
            departure.DepositCents, departure.AllowInstalments, departure.FinalPaymentDue, today, discount.Choice);

        if (req.PaymentPlan == PaymentPlan.Instalments && !quote.InstalmentsAvailable)
            throw new BusinessRuleException("Instalments aren't available for this departure any more. Please pay in full.");

        // ---- Save everything in one transaction ----
        await using var tx = await db.Database.BeginTransactionAsync(ct);

        // 1. Reserve seats atomically. Two people can never get the same last seat.
        var seats = adults + children;
        var reserved = await db.Departures
            .Where(d => d.Id == departure.Id && !d.IsCancelledByCompany && d.SeatsBooked + seats <= d.Capacity)
            .ExecuteUpdateAsync(s => s.SetProperty(d => d.SeatsBooked, d => d.SeatsBooked + seats), ct);
        if (reserved == 0)
            throw new BusinessRuleException(
                departure.SeatsLeft == 0 ? "Sorry, this departure is fully booked." : "Not enough seats left for your group.", 409);

        // 2. Use up a promo code (only if it still has uses left).
        if (discount.Choice?.Special.Type == SpecialType.PromoCode)
        {
            var specialId = discount.Choice.Special.Id;
            var used = await db.Specials
                .Where(s => s.Id == specialId && (s.MaxUses == null || s.TimesUsed < s.MaxUses))
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.TimesUsed, x => x.TimesUsed + 1), ct);
            if (used == 0)
                throw new BusinessRuleException("This promo code has just been fully used.", 409);
        }

        // 3. The booking itself.
        var isFree = quote.TotalCents == 0;
        var booking = new Booking
        {
            DepartureId = departure.Id,
            CustomerId = userId,
            Status = isFree ? BookingStatus.Paid : BookingStatus.Pending,
            PaymentPlan = req.PaymentPlan,
            Adults = adults,
            Children = children,
            SubtotalCents = quote.SubtotalCents,
            DiscountCents = quote.DiscountAppliedCents,
            TotalCents = quote.TotalCents,
            DepositCents = quote.DepositCents,
            ExpiresAt = isFree ? null : now.Add(BookingRules.SeatHold),
            CancellationPolicySnapshot = PolicySnapshot.FromDeparture(departure).ToJson(),
            PolicyAcceptedAt = now,
            CreatedAt = now,
            UpdatedAt = now,
        };
        db.Bookings.Add(booking);

        foreach (var t in inputs)
        {
            db.Travellers.Add(new Traveller
            {
                BookingId = booking.Id,
                FullName = t.FullName,
                IdNumber = t.IdNumber,
                PassportNumber = t.PassportNumber,
                PassportExpiry = t.PassportExpiry,
                Phone = t.Phone,
                IsChild = t.IsChild,
                DateOfBirth = t.DateOfBirth,
                SchoolGrade = t.SchoolGrade,
                MedicalNotes = t.MedicalNotes,
                Allergies = t.Allergies,
                CreatedAt = now,
            });
        }

        if (guardian is not null && trip.Audience == Audience.HighSchool)
        {
            db.GuardianDetails.Add(new GuardianDetails
            {
                BookingId = booking.Id,
                GuardianName = guardian.GuardianName,
                GuardianPhone = guardian.GuardianPhone,
                GuardianRelationship = guardian.GuardianRelationship,
                EmergencyContactName = guardian.EmergencyContactName,
                EmergencyContactPhone = guardian.EmergencyContactPhone,
                ConsentGivenAt = now,
            });
        }

        if (discount.Choice is not null)
        {
            db.BookingDiscounts.Add(new BookingDiscount
            {
                BookingId = booking.Id,
                SpecialId = discount.Choice.Special.Id,
                SpecialName = discount.Choice.Special.Name,
                PercentOff = discount.Choice.Special.PercentOff,
                DiscountCents = discount.Choice.DiscountCents,
                Status = discount.Choice.Status,
                CreatedAt = now,
            });
        }

        if (req.PaymentPlan == PaymentPlan.Instalments)
        {
            foreach (var p in InstalmentRules.Schedule(quote.TotalCents, quote.DepositCents, today, departure.FinalPaymentDue!.Value))
            {
                db.Instalments.Add(new Instalment
                {
                    BookingId = booking.Id,
                    Sequence = p.Sequence,
                    DueDate = p.DueDate,
                    AmountCents = p.AmountCents,
                    Status = InstalmentStatus.Due,
                });
            }
        }

        audit.Log("booking.created", "booking", booking.Id, new
        {
            departure_id = departure.Id, adults, children, quote.TotalCents, req.PaymentPlan,
            discount = discount.Choice?.Special.Name,
        }, userId);

        await db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);

        logger.LogInformation("Booking {BookingId} created for departure {DepartureId} ({Seats} seats)", booking.Id, departure.Id, seats);

        var dto = await GetAsync(booking.Id, ct);
        return new CreateBookingResponse(dto, rules.Warnings.Select(w => w.Message).ToList());
    }

    // ======================================================================
    // Reading bookings
    // ======================================================================

    public async Task<IReadOnlyList<BookingSummaryDto>> MineAsync(CancellationToken ct)
    {
        var userId = currentUser.RequireUserId();
        var list = await BookingsWithDetails().AsNoTracking()
            .Where(b => b.CustomerId == userId && b.Status != BookingStatus.Expired)
            .OrderByDescending(b => b.CreatedAt)
            .ToListAsync(ct);
        return list.Select(Mapping.ToSummary).ToList();
    }

    public async Task<BookingDto> GetAsync(Guid id, CancellationToken ct)
    {
        var booking = await BookingsWithDetails().AsNoTracking().FirstOrDefaultAsync(b => b.Id == id, ct)
                      ?? throw new NotFoundException("Booking");
        EnsureCanSee(booking);

        var now = clock.UtcNow;
        var canReview = booking.Status is BookingStatus.Paid or BookingStatus.Confirmed
                        && booking.Departure!.ReturnDate < SaTime.DateInSa(now)
                        && booking.CustomerId == currentUser.UserId
                        && !await db.Reviews.AnyAsync(r => r.TripId == booking.Departure.TripId && r.CustomerId == booking.CustomerId, ct);

        return Mapping.ToDto(booking, now, currentUser.IsAdmin, canReview);
    }

    public async Task<PagedResult<BookingSummaryDto>> SearchAsync(BookingQuery q, CancellationToken ct)
    {
        var (page, size) = Paging.Normalise(q.Page, q.PageSize);
        var query = BookingsWithDetails().AsNoTracking();
        if (q.TripId is not null) query = query.Where(b => b.Departure!.TripId == q.TripId);
        if (q.DepartureId is not null) query = query.Where(b => b.DepartureId == q.DepartureId);
        if (!string.IsNullOrWhiteSpace(q.Status)) query = query.Where(b => b.Status == q.Status);
        if (!string.IsNullOrWhiteSpace(q.DepartureProvince)) query = query.Where(b => b.Departure!.DepartureProvince == q.DepartureProvince);
        if (!string.IsNullOrWhiteSpace(q.DepartureArea)) query = query.Where(b => b.Departure!.DepartureArea == q.DepartureArea);
        if (!string.IsNullOrWhiteSpace(q.Search))
        {
            var term = $"%{q.Search.Trim()}%";
            query = query.Where(b => EF.Functions.ILike(b.Reference, term)
                                     || EF.Functions.ILike(b.Customer!.FullName, term)
                                     || b.Travellers.Any(t => EF.Functions.ILike(t.FullName, term)));
        }

        var total = await query.CountAsync(ct);
        var items = await query.OrderByDescending(b => b.CreatedAt).Skip((page - 1) * size).Take(size).ToListAsync(ct);
        return new PagedResult<BookingSummaryDto>(items.Select(Mapping.ToSummary).ToList(), page, size, total);
    }

    // ======================================================================
    // Cancelling
    // ======================================================================

    public async Task<CancelPreviewDto> CancelPreviewAsync(Guid id, CancellationToken ct)
    {
        var booking = await db.Bookings.AsNoTracking().FirstOrDefaultAsync(b => b.Id == id, ct) ?? throw new NotFoundException("Booking");
        EnsureCanSee(booking);
        var policy = PolicySnapshot.FromJson(booking.CancellationPolicySnapshot);
        var (allowed, reason, refund) = CustomerCancellation(booking, policy);
        return new CancelPreviewDto(allowed, allowed ? null : reason, policy.CancellationDeadline,
            booking.AmountPaidCents, refund, CancellationRules.Describe(policy));
    }

    public async Task<BookingDto> CancelByCustomerAsync(Guid id, CancelRequest req, CancellationToken ct)
    {
        var userId = currentUser.RequireUserId();
        var booking = await db.Bookings.Include(b => b.Discount).FirstOrDefaultAsync(b => b.Id == id, ct)
                      ?? throw new NotFoundException("Booking");
        if (booking.CustomerId != userId) throw new ForbiddenException();

        // Cancelling twice does nothing the second time.
        if (booking.Status == BookingStatus.Cancelled) return await GetAsync(id, ct);

        var policy = PolicySnapshot.FromJson(booking.CancellationPolicySnapshot);
        var (allowed, reason, refund) = CustomerCancellation(booking, policy);
        if (!allowed) throw new BusinessRuleException(reason, 422);

        await CancelInternalAsync(booking, refund, req.Reason ?? "Cancelled by customer", userId, staffOverride: false, ct);
        return await GetAsync(id, ct);
    }

    public async Task<BookingDto> CancelByStaffAsync(Guid id, AdminCancelRequest req, CancellationToken ct)
    {
        var adminId = currentUser.RequireUserId();
        var booking = await db.Bookings.Include(b => b.Discount).FirstOrDefaultAsync(b => b.Id == id, ct)
                      ?? throw new NotFoundException("Booking");
        if (booking.Status == BookingStatus.Cancelled) return await GetAsync(id, ct);
        if (string.IsNullOrWhiteSpace(req.Reason))
            throw new BusinessRuleException("A reason is required when staff cancel a booking.", 422);

        var policy = PolicySnapshot.FromJson(booking.CancellationPolicySnapshot);
        var policyRefund = CancellationRules.CalculateRefund(policy, booking.AmountPaidCents, booking.DepositCents);
        var refund = req.RefundCentsOverride ?? policyRefund;
        if (refund > booking.AmountPaidCents)
            throw new BusinessRuleException($"The refund can't be more than what was paid ({Money.FormatRand(booking.AmountPaidCents)}).", 422);

        await CancelInternalAsync(booking, refund, req.Reason.Trim(), adminId, staffOverride: true, ct, new
        {
            policy_refund_cents = policyRefund,
            override_refund_cents = req.RefundCentsOverride,
            customer_could_cancel = CancellationRules.CanCustomerCancel(policy, booking.Status, clock.UtcNow).Allowed,
        });
        return await GetAsync(id, ct);
    }

    public async Task<BookingDto> MarkRefundedAsync(Guid id, CancellationToken ct)
    {
        var booking = await db.Bookings.FirstOrDefaultAsync(b => b.Id == id, ct) ?? throw new NotFoundException("Booking");
        if (booking.RefundStatus != RefundStatus.Pending)
            throw new BusinessRuleException("There is no pending refund on this booking.", 409);
        booking.RefundStatus = RefundStatus.Refunded;
        booking.RefundedAt = clock.UtcNow;
        booking.UpdatedAt = clock.UtcNow;
        audit.Log("booking.refunded", "booking", id, new { booking.RefundCents });
        await db.SaveChangesAsync(ct);

        await notifications.NotifyUserAsync(booking.CustomerId, booking.Id, "refund_paid",
            $"Refund paid – {booking.Reference}",
            $"Your refund of {Money.FormatRand(booking.RefundCents)} for booking {booking.Reference} has been paid.",
            $"refund-paid:{booking.Id}", ct);
        return await GetAsync(id, ct);
    }

    /// <summary>Staff record money received outside the app (e.g. EFT or cash at the office).</summary>
    public async Task<BookingDto> RecordManualPaymentAsync(Guid id, AdminBookingStatusRequest req, CancellationToken ct)
    {
        if (req.Action != "record_payment" || req.AmountReceivedCents is null)
            throw new BusinessRuleException("Use action \"record_payment\" with the amount received.", 400);

        await using var tx = await db.Database.BeginTransactionAsync(ct);
        var booking = await db.Bookings.Include(b => b.Instalments).FirstOrDefaultAsync(b => b.Id == id, ct)
                      ?? throw new NotFoundException("Booking");
        if (!BookingStatus.IsActive(booking.Status))
            throw new BusinessRuleException("This booking is cancelled or expired.", 409);
        if (req.AmountReceivedCents > booking.BalanceCents)
            throw new BusinessRuleException($"That's more than the balance of {Money.FormatRand(booking.BalanceCents)}.", 422);

        var now = clock.UtcNow;
        var payment = new Payment
        {
            BookingId = booking.Id,
            Purpose = req.AmountReceivedCents == booking.BalanceCents ? PaymentPurpose.Balance : PaymentPurpose.Instalment,
            InstalmentId = booking.Instalments.Where(i => i.Status is InstalmentStatus.Due or InstalmentStatus.Overdue)
                .OrderBy(i => i.Sequence).FirstOrDefault(i => i.AmountCents == req.AmountReceivedCents)?.Id,
            AmountCents = req.AmountReceivedCents.Value,
            Provider = "manual",
            ProviderReference = $"manual-{Guid.NewGuid():N}",
            Status = PaymentStatus.Complete,
            PaidAt = now,
            RawPayload = System.Text.Json.JsonSerializer.Serialize(new { note = req.Note, recorded_by = currentUser.UserId }),
            CreatedAt = now,
        };
        if (payment.Purpose == PaymentPurpose.Instalment && payment.InstalmentId is null)
            payment.Purpose = PaymentPurpose.Deposit; // a part payment not matching an instalment counts towards what's due first
        db.Payments.Add(payment);
        PaymentRules.ApplyPayment(booking, booking.Instalments, payment, now);
        booking.UpdatedAt = now;
        audit.Log("payment.manual_recorded", "booking", booking.Id, new { payment.AmountCents, req.Note });
        await db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);
        return await GetAsync(id, ct);
    }

    // ======================================================================
    // Student discount
    // ======================================================================

    public async Task UploadStudentIdAsync(Guid bookingId, Stream image, CancellationToken ct)
    {
        var userId = currentUser.RequireUserId();
        var discount = await db.BookingDiscounts.FirstOrDefaultAsync(d => d.BookingId == bookingId, ct)
                       ?? throw new BusinessRuleException("This booking doesn't have a student discount.", 409);
        var booking = await db.Bookings.AsNoTracking().FirstAsync(b => b.Id == bookingId, ct);
        if (booking.CustomerId != userId) throw new ForbiddenException();
        if (discount.Status != DiscountStatus.PendingVerification)
            throw new BusinessRuleException("This discount has already been reviewed.", 409);

        var processed = await images.ProcessAsync(image, ct);   // re-encoding strips location data from the photo
        var path = $"{bookingId}/{Guid.NewGuid():N}{processed.Extension}";
        await storage.UploadAsync(StudentIdBucket, path, new MemoryStream(processed.Full), processed.ContentType, ct);

        var old = discount.StudentIdImagePath;
        discount.StudentIdImagePath = path;
        audit.Log("discount.student_id_uploaded", "booking", bookingId, null, userId);
        await db.SaveChangesAsync(ct);
        if (old is not null) await storage.DeleteAsync(StudentIdBucket, old, ct);

        await notifications.NotifyAdminsAsync("student_id_uploaded", $"Student ID to review – {booking.Reference}",
            $"A student ID was uploaded for booking {booking.Reference}. Please review it in the admin panel.", ct);
    }

    public async Task<IReadOnlyList<PendingDiscountDto>> PendingDiscountsAsync(CancellationToken ct)
    {
        var rows = await db.Bookings.AsNoTracking()
            .Include(b => b.Customer)
            .Include(b => b.Discount)
            .Where(b => b.Discount != null && b.Discount.Status == DiscountStatus.PendingVerification)
            .Where(b => b.Status == BookingStatus.Pending || b.Status == BookingStatus.Confirmed || b.Status == BookingStatus.Paid)
            .OrderBy(b => b.CreatedAt)
            .ToListAsync(ct);

        var result = new List<PendingDiscountDto>();
        foreach (var b in rows)
        {
            var d = b.Discount!;
            var url = d.StudentIdImagePath is null
                ? null
                : await storage.CreateSignedUrlAsync(StudentIdBucket, d.StudentIdImagePath, TimeSpan.FromMinutes(15), ct);
            result.Add(new PendingDiscountDto(d.Id, b.Id, b.Reference, b.Customer?.FullName ?? "", d.SpecialName,
                d.PercentOff, d.DiscountCents, url, d.CreatedAt));
        }
        return result;
    }

    public async Task<BookingDto> ReviewDiscountAsync(Guid discountId, DiscountReviewRequest req, CancellationToken ct)
    {
        var adminId = currentUser.RequireUserId();
        await using var tx = await db.Database.BeginTransactionAsync(ct);

        var discount = await db.BookingDiscounts.FirstOrDefaultAsync(d => d.Id == discountId, ct) ?? throw new NotFoundException("Discount");
        if (discount.Status != DiscountStatus.PendingVerification)
            throw new BusinessRuleException("This discount has already been reviewed.", 409);
        var booking = await db.Bookings.Include(b => b.Instalments).FirstAsync(b => b.Id == discount.BookingId, ct);
        var now = clock.UtcNow;

        discount.ReviewedBy = adminId;
        discount.ReviewedAt = now;
        discount.ReviewNote = req.Note;

        if (!req.Approve)
        {
            discount.Status = DiscountStatus.Rejected;
            audit.Log("discount.rejected", "booking", booking.Id, new { req.Note });
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            await notifications.NotifyUserAsync(booking.CustomerId, booking.Id, "student_discount_rejected",
                $"Student discount not approved – {booking.Reference}",
                $"We couldn't approve the student discount for booking {booking.Reference}. The normal price applies." +
                (string.IsNullOrWhiteSpace(req.Note) ? "" : $" Note from our team: {req.Note}"),
                $"discount-reviewed:{discount.Id}", ct);
            return await GetAsync(booking.Id, ct);
        }

        if (!BookingStatus.IsActive(booking.Status))
            throw new BusinessRuleException("This booking is cancelled or expired.", 409);

        // Approve: take the discount off the price. Money already paid is never changed.
        discount.Status = DiscountStatus.Applied;
        discount.DiscountCents = Money.PercentOf(booking.SubtotalCents, discount.PercentOff);
        booking.DiscountCents = discount.DiscountCents;
        booking.TotalCents = booking.SubtotalCents - booking.DiscountCents;
        booking.DepositCents = Math.Min(booking.DepositCents, booking.TotalCents);
        booking.UpdatedAt = now;

        if (booking.AmountPaidCents > booking.TotalCents)
        {
            // Already paid more than the new price: the difference is refunded.
            booking.RefundCents += booking.AmountPaidCents - booking.TotalCents;
            booking.RefundStatus = RefundStatus.Pending;
        }

        var unpaid = booking.Instalments.Where(i => i.Status is InstalmentStatus.Due or InstalmentStatus.Overdue)
            .Select(i => (i.Id, i.Sequence)).ToList();
        var owedForInstalments = booking.TotalCents - Math.Max(booking.AmountPaidCents, booking.DepositCents);
        foreach (var change in InstalmentRules.Rebalance(unpaid, owedForInstalments))
        {
            var inst = booking.Instalments.First(i => i.Id == change.InstalmentId);
            if (change.Cancel) inst.Status = InstalmentStatus.Cancelled;
            else inst.AmountCents = change.NewAmountCents;
        }

        booking.Status = PaymentRules.StatusFor(booking);
        if (booking.Status != BookingStatus.Pending) booking.ExpiresAt = null;

        audit.Log("discount.approved", "booking", booking.Id, new { discount.DiscountCents, booking.TotalCents, req.Note });
        await db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);

        await notifications.NotifyUserAsync(booking.CustomerId, booking.Id, "student_discount_approved",
            $"Student discount approved – {booking.Reference}",
            $"Good news! Your student discount of {Money.FormatRand(discount.DiscountCents)} has been applied to booking {booking.Reference}. " +
            $"Your new total is {Money.FormatRand(booking.TotalCents)}.",
            $"discount-reviewed:{discount.Id}", ct);
        return await GetAsync(booking.Id, ct);
    }

    // ======================================================================
    // Background job: release seats from unpaid bookings
    // ======================================================================

    public async Task<int> ExpirePendingAsync(CancellationToken ct)
    {
        var now = clock.UtcNow;
        var dueIds = await db.Bookings.AsNoTracking()
            .Where(b => b.Status == BookingStatus.Pending && b.ExpiresAt < now)
            .Select(b => b.Id)
            .Take(500)
            .ToListAsync(ct);

        var expired = 0;
        foreach (var id in dueIds)
        {
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            // Conditional update: if a payment arrived a moment ago, the booking is no longer pending and is left alone.
            var changed = await db.Bookings
                .Where(b => b.Id == id && b.Status == BookingStatus.Pending && b.ExpiresAt < now)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(b => b.Status, BookingStatus.Expired)
                    .SetProperty(b => b.UpdatedAt, now), ct);
            if (changed == 0) { await tx.RollbackAsync(ct); continue; }

            var booking = await db.Bookings.AsNoTracking().Include(b => b.Discount).FirstAsync(b => b.Id == id, ct);
            await ReleaseSeatsAsync(booking.DepartureId, booking.TravellerCount, ct);
            await CancelUnpaidInstalmentsAsync(id, ct);
            await ReleasePromoUseAsync(booking.Discount, ct);
            audit.Log("booking.expired", "booking", id, new { seats_released = booking.TravellerCount });
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            expired++;
        }

        if (expired > 0) logger.LogInformation("Expired {Count} unpaid bookings and released their seats", expired);
        return expired;
    }

    // ======================================================================
    // Helpers
    // ======================================================================

    private IQueryable<Booking> BookingsWithDetails() => db.Bookings
        .Include(b => b.Departure).ThenInclude(d => d!.Trip)
        .Include(b => b.Customer)
        .Include(b => b.Travellers)
        .Include(b => b.Guardian)
        .Include(b => b.Discount)
        .Include(b => b.Instalments)
        .Include(b => b.Payments)
        .AsSplitQuery();

    private void EnsureCanSee(Booking booking)
    {
        if (currentUser.IsAdmin) return;
        if (booking.CustomerId != currentUser.UserId) throw new NotFoundException("Booking"); // don't reveal it exists
    }

    private (bool Allowed, string Reason, int Refund) CustomerCancellation(Booking booking, PolicySnapshot policy)
    {
        // An unpaid booking can always be abandoned: it only releases the seats.
        if (booking.Status == BookingStatus.Pending && booking.AmountPaidCents == 0)
            return (true, "", 0);

        var check = CancellationRules.CanCustomerCancel(policy, booking.Status, clock.UtcNow);
        var refund = check.Allowed ? CancellationRules.CalculateRefund(policy, booking.AmountPaidCents, booking.DepositCents) : 0;
        return (check.Allowed, check.Reason, refund);
    }

    private async Task CancelInternalAsync(Booking booking, int refund, string reason, Guid actorId, bool staffOverride,
        CancellationToken ct, object? extraAudit = null)
    {
        var now = clock.UtcNow;
        await using var tx = await db.Database.BeginTransactionAsync(ct);

        // Only one cancellation can win, even if the button is tapped twice at once.
        var changed = await db.Bookings
            .Where(b => b.Id == booking.Id && (b.Status == BookingStatus.Pending || b.Status == BookingStatus.Confirmed || b.Status == BookingStatus.Paid))
            .ExecuteUpdateAsync(s => s.SetProperty(b => b.Status, BookingStatus.Cancelled), ct);
        if (changed == 0)
        {
            await tx.RollbackAsync(ct);
            return;
        }

        booking.Status = BookingStatus.Cancelled;
        booking.CancelledAt = now;
        booking.CancelledBy = actorId;
        booking.CancellationReason = reason;
        booking.RefundCents += refund;
        booking.RefundStatus = booking.RefundCents > 0 ? RefundStatus.Pending : RefundStatus.None;
        booking.ExpiresAt = null;
        booking.UpdatedAt = now;

        await ReleaseSeatsAsync(booking.DepartureId, booking.TravellerCount, ct);
        await CancelUnpaidInstalmentsAsync(booking.Id, ct);
        await ReleasePromoUseAsync(booking.Discount, ct);

        audit.Log(staffOverride ? "booking.cancelled_by_staff" : "booking.cancelled", "booking", booking.Id,
            new { reason, refund_cents = refund, extra = extraAudit }, actorId);
        await db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);

        await notifications.NotifyUserAsync(booking.CustomerId, booking.Id, "booking_cancelled",
            $"Booking cancelled – {booking.Reference}",
            refund > 0
                ? $"Your booking {booking.Reference} has been cancelled. A refund of {Money.FormatRand(refund)} will be paid to you."
                : $"Your booking {booking.Reference} has been cancelled.",
            $"booking-cancelled:{booking.Id}", ct);
    }

    private Task<int> ReleaseSeatsAsync(Guid departureId, int seats, CancellationToken ct) =>
        db.Departures
            .Where(d => d.Id == departureId)
            .ExecuteUpdateAsync(s => s.SetProperty(d => d.SeatsBooked, d => d.SeatsBooked >= seats ? d.SeatsBooked - seats : 0), ct);

    private Task<int> CancelUnpaidInstalmentsAsync(Guid bookingId, CancellationToken ct) =>
        db.Instalments
            .Where(i => i.BookingId == bookingId && (i.Status == InstalmentStatus.Due || i.Status == InstalmentStatus.Overdue))
            .ExecuteUpdateAsync(s => s.SetProperty(i => i.Status, InstalmentStatus.Cancelled), ct);

    private async Task ReleasePromoUseAsync(BookingDiscount? discount, CancellationToken ct)
    {
        if (discount is null || discount.PromoUseReleased) return;
        var specialId = discount.SpecialId;
        var isPromo = await db.Specials.AnyAsync(s => s.Id == specialId && s.Type == SpecialType.PromoCode, ct);
        if (!isPromo) return;

        await db.Specials.Where(s => s.Id == specialId && s.TimesUsed > 0)
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.TimesUsed, x => x.TimesUsed - 1), ct);
        await db.BookingDiscounts.Where(d => d.Id == discount.Id)
            .ExecuteUpdateAsync(s => s.SetProperty(d => d.PromoUseReleased, true), ct);
        discount.PromoUseReleased = true;
    }

    private async Task<Departure> LoadBookableDepartureAsync(Guid departureId, CancellationToken ct)
    {
        var now = clock.UtcNow;
        var departure = await db.Departures.AsNoTracking().Include(d => d.Trip)
                            .FirstOrDefaultAsync(d => d.Id == departureId, ct)
                        ?? throw new NotFoundException("Departure");
        if (departure.Trip is null || !departure.Trip.IsPublished) throw new NotFoundException("Departure");
        if (departure.IsCancelledByCompany)
            throw new BusinessRuleException("This departure has been cancelled. Please choose another date.", 409);
        if (now > departure.BookingDeadline)
            throw new BusinessRuleException(
                $"Bookings for this departure closed on {SaTime.FormatDateTime(departure.BookingDeadline)}.", 422);
        return departure;
    }

    private async Task<DiscountOutcome> ChooseDiscountAsync(Departure departure, int travellers, int subtotal,
        string? promoCode, bool wantsStudent, CancellationToken ct)
    {
        var code = string.IsNullOrWhiteSpace(promoCode) ? null : promoCode.Trim().ToLower();
        var tripId = departure.TripId;
        var specials = await db.Specials.AsNoTracking().Include(s => s.SpecialTrips)
            .Where(s => s.SpecialTrips.Any(x => x.TripId == tripId)
                        || (code != null && s.PromoCode != null && s.PromoCode.ToLower() == code))
            .ToListAsync(ct);

        return Pricing.ChooseDiscount(specials.Select(Mapping.ToCandidate),
            new DiscountRequest(tripId, travellers, subtotal, clock.UtcNow, promoCode, wantsStudent));
    }

    private static string? Clean(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
