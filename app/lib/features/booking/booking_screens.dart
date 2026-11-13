import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_client.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/file_saver.dart';
import '../trips/widgets.dart';
import 'data.dart';
import 'models.dart';
import 'payment_screen.dart';

// ============================ My trips ============================

class MyTripsScreen extends ConsumerWidget {
  const MyTripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(myBookingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My trips')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(myBookingsProvider.future).then((_) {}),
        child: AsyncView(
          value: bookings,
          onRetry: () => ref.invalidate(myBookingsProvider),
          data: (list) {
            if (list.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 80),
                EmptyView(
                  icon: Icons.luggage_outlined,
                  title: 'No trips booked yet',
                  message: 'When you book, your trips, payments and tickets show here.',
                  action: FilledButton(onPressed: () => context.go('/'), child: const Text('Explore trips')),
                ),
              ]);
            }
            final upcoming = list.where((b) => b.isUpcoming).toList();
            final past = list.where((b) => !b.isUpcoming).toList();
            return Constrained(
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (upcoming.isNotEmpty) const SectionTitle('Upcoming'),
                for (final b in upcoming) _BookingTile(b),
                if (past.isNotEmpty) const SectionTitle('Past and cancelled'),
                for (final b in past) _BookingTile(b),
              ]),
            );
          },
        ),
      ),
    );
  }
}

class _BookingTile extends StatelessWidget {
  const _BookingTile(this.b);
  final BookingSummary b;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('/bookings/${b.id}'),
            child: Row(children: [
              NetImage(b.coverImageUrl, width: 96, height: 110),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(b.tripTitle, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Pill(statusLabel(b.status), tone: toneForStatus(b.status)),
                    ]),
                    const SizedBox(height: 4),
                    Text('${formatDay(b.departureAt)} · ${b.departsFrom}', style: const TextStyle(fontSize: 13)),
                    Text('${b.reference} · ${b.travellers} traveller${b.travellers == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 12, color: AppColors.secondaryText)),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: b.totalCents == 0 ? 1 : b.amountPaidCents / b.totalCents),
                    const SizedBox(height: 4),
                    Text(
                      b.nextDueDate != null && b.nextDueCents != null
                          ? 'Next: ${rand(b.nextDueCents!)} due ${formatDateOnly(b.nextDueDate!)}'
                          : '${rand(b.amountPaidCents)} of ${rand(b.totalCents)} paid',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      );
}

// ============================ Booking details ============================

class BookingDetailScreen extends ConsumerStatefulWidget {
  const BookingDetailScreen({super.key, required this.bookingId, this.autoPay});
  final String bookingId;

  /// "full" or "deposit": start the payment straight away (right after booking).
  final String? autoPay;

  @override
  ConsumerState<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends ConsumerState<BookingDetailScreen> {
  bool _busy = false;
  bool _autoPayDone = false;

  Future<void> _pay(Booking b, String type) async {
    setState(() => _busy = true);
    try {
      final redirect = await ref.read(bookingRepositoryProvider).pay(b.id, type);
      if (!mounted) return;
      final outcome = await PaymentScreen.open(
        context,
        checkoutUrl: redirect.checkoutUrl ?? redirect.url,
        amountLabel: rand(redirect.amountCents),
      );
      if (!mounted) return;
      if (outcome == PaymentOutcome.cancelled) {
        showSnack(context, 'Payment cancelled. No money was taken.');
        return;
      }
      await _waitForPayment(b.amountPaidCents);
    } catch (e) {
      if (mounted) showSnack(context, ApiException.from(e).allMessages.join('\n'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// PayFast tells our server about the payment a few seconds after the customer returns.
  Future<void> _waitForPayment(int paidBefore) async {
    _showPendingDialog();
    var updated = false;
    for (var i = 0; i < 15 && mounted; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final fresh = await ref.refresh(bookingProvider(widget.bookingId).future);
      if (fresh.amountPaidCents > paidBefore || fresh.refundStatus == 'pending') {
        updated = true;
        break;
      }
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ref.invalidate(myBookingsProvider);
    showSnack(
      context,
      updated ? 'Payment received – thank you!' : "We're still waiting for PayFast to confirm. It'll update here shortly.",
      error: !updated,
    );
  }

  void _showPendingDialog() {
    unawaited(showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const PaymentPendingDialog()));
  }

  Future<void> _cancel(Booking b) async {
    final repo = ref.read(bookingRepositoryProvider);
    CancelPreview preview;
    try {
      preview = await repo.cancelPreview(b.id);
    } catch (e) {
      if (mounted) showSnack(context, ApiException.from(e).message, error: true);
      return;
    }
    if (!mounted) return;
    if (!preview.allowed) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text("This booking can't be cancelled"),
          content: Text(preview.reason ?? preview.policyText),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
      return;
    }
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(preview.refundCents > 0
              ? 'You\'ll get a refund of ${rand(preview.refundCents)} (you paid ${rand(preview.amountPaidCents)}).'
              : preview.amountPaidCents > 0
                  ? 'Under the cancellation policy no refund is due (you paid ${rand(preview.amountPaidCents)}).'
                  : 'Your seats will be released. Nothing has been paid.'),
          const SizedBox(height: 8),
          Text(preview.policyText, style: const TextStyle(fontSize: 12, color: AppColors.secondaryText)),
          const SizedBox(height: 12),
          TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep booking')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final done = await runAction(context, () => repo.cancel(b.id, reason.text.trim().isEmpty ? null : reason.text.trim()),
        success: 'Booking cancelled.');
    if (done) {
      ref.invalidate(bookingProvider(b.id));
      ref.invalidate(myBookingsProvider);
    }
  }

  Future<void> _uploadStudentId(Booking b) async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, imageQuality: 90);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final ok = await runAction(
      context,
      () => ref.read(bookingRepositoryProvider).uploadStudentId(b.id, bytes, file.name, file.mimeType ?? 'image/jpeg'),
      success: 'Student ID uploaded. We\'ll let you know once it\'s checked.',
    );
    if (ok) ref.invalidate(bookingProvider(b.id));
  }

  Future<void> _invoice(Booking b) async {
    await runAction(context, () async {
      final bytes = await ref.read(bookingRepositoryProvider).invoice(b.id);
      await saveOrShareFile(bytes, 'invoice-${b.reference}.pdf', 'application/pdf');
    });
  }

  Future<void> _review(Booking b) async {
    var rating = 5;
    final comment = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('How was your trip?'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  onPressed: () => set(() => rating = i),
                  icon: Icon(i <= rating ? Icons.star : Icons.star_border, color: AppColors.coral, size: 32),
                ),
            ]),
            TextField(controller: comment, maxLines: 3, decoration: const InputDecoration(labelText: 'Tell others about it (optional)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Post review')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final done = await runAction(context, () => ref.read(bookingRepositoryProvider).review(b.tripId, rating, comment.text.trim()),
        success: 'Thank you for your review!');
    if (done) ref.invalidate(bookingProvider(b.id));
  }

  @override
  Widget build(BuildContext context) {
    final booking = ref.watch(bookingProvider(widget.bookingId));

    // Start the first payment automatically right after booking.
    if (!_autoPayDone && widget.autoPay != null) {
      final b = booking.valueOrNull;
      if (b != null && b.status == 'pending') {
        _autoPayDone = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _pay(b, widget.autoPay!));
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(booking.valueOrNull?.reference ?? 'Booking')),
      body: AsyncView(
        value: booking,
        onRetry: () => ref.invalidate(bookingProvider(widget.bookingId)),
        data: (b) => RefreshIndicator(
          onRefresh: () => ref.refresh(bookingProvider(widget.bookingId).future).then((_) {}),
          child: Constrained(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                Expanded(child: Text(b.tripTitle, style: Theme.of(context).textTheme.titleLarge)),
                Pill(statusLabel(b.status), tone: toneForStatus(b.status)),
              ]),
              const SizedBox(height: 12),
              SandBox(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Departs ${formatDateTime(b.departure.departureAt)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${b.departure.meetingPlace}\n${b.departure.departsFrom}'),
                  const SizedBox(height: 4),
                  Text('Returns ${formatDateOnly(b.departure.returnDate)}'),
                  if (b.isCrossBorder) ...[
                    const SizedBox(height: 8),
                    const Text('Bring every traveller\'s passport.', style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ]),
              ),

              // ---------- Payment ----------
              const SectionTitle('Payment'),
              LinearProgressIndicator(value: b.paidFraction, minHeight: 10, borderRadius: BorderRadius.circular(8)),
              const SizedBox(height: 8),
              KeyValueRow('Paid', rand(b.amountPaidCents), bold: true, valueColor: AppColors.green),
              KeyValueRow('Total', rand(b.totalCents)),
              if (b.discountCents > 0) KeyValueRow('Discount (${b.discount?.name ?? ''})', '-${rand(b.discountCents)}'),
              KeyValueRow('Balance', rand(b.balanceCents), bold: true),
              if (b.status == 'pending' && b.expiresAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Your seats are held until ${formatTime(b.expiresAt!)}. Pay before then to keep them.',
                      style: const TextStyle(color: AppColors.coral, fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 12),
              if (b.isActive && b.balanceCents > 0) ...[
                if (b.paymentPlan == 'full' && b.amountPaidCents == 0)
                  CtaButton(label: 'Pay ${rand(b.totalCents)}', onPressed: _busy ? null : () => _pay(b, 'full'))
                else if (b.needsDeposit)
                  CtaButton(label: 'Pay deposit ${rand(b.depositCents - b.amountPaidCents)}', onPressed: _busy ? null : () => _pay(b, 'deposit'))
                else ...[
                  if (b.nextInstalment != null)
                    CtaButton(
                      label: 'Pay next instalment ${rand(b.nextInstalment!.amountCents)}',
                      onPressed: _busy ? null : () => _pay(b, 'next_instalment'),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: _busy ? null : () => _pay(b, 'balance'), child: Text('Pay full balance ${rand(b.balanceCents)}')),
                ],
              ],
              if (b.instalments.isNotEmpty) ...[
                const SectionTitle('Payment plan'),
                if (b.depositCents > 0)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(b.amountPaidCents >= b.depositCents ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: b.amountPaidCents >= b.depositCents ? AppColors.green : AppColors.secondaryText),
                    title: Text('Deposit · ${rand(b.depositCents)}'),
                    subtitle: const Text('Due now'),
                  ),
                for (final i in b.instalments.where((i) => i.status != 'cancelled'))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(i.status == 'paid' ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: i.status == 'paid' ? AppColors.green : i.status == 'overdue' ? AppColors.error : AppColors.secondaryText),
                    title: Text('Instalment ${i.sequence} · ${rand(i.amountCents)}'),
                    subtitle: Text('Due ${formatDateOnly(i.dueDate)}'),
                    trailing: Pill(statusLabel(i.status), tone: toneForStatus(i.status)),
                  ),
              ],

              // ---------- Student discount ----------
              if (b.discount != null && b.discount!.status != 'applied') ...[
                const SectionTitle('Student discount'),
                SandBox(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${b.discount!.name}: ${statusLabel(b.discount!.status)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(b.discount!.status == 'rejected'
                        ? (b.discount!.reviewNote ?? 'We couldn\'t approve the student ID. The normal price applies.')
                        : b.discount!.hasStudentId
                            ? 'We\'re checking your student ID. Once approved, ${rand(b.discount!.discountCents)} comes off.'
                            : 'Upload a photo of your student ID to get ${rand(b.discount!.discountCents)} off.'),
                    if (b.discount!.status == 'pending_verification') ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _uploadStudentId(b),
                        icon: const Icon(Icons.upload_outlined),
                        label: Text(b.discount!.hasStudentId ? 'Upload a different photo' : 'Upload student ID'),
                      ),
                    ],
                  ]),
                ),
              ],

              // ---------- Travellers ----------
              const SectionTitle('Travellers'),
              for (final t in b.travellers)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(t.fullName),
                  subtitle: Text([
                    if (t.passportNumberMasked != null) 'Passport ${t.passportNumberMasked}',
                    if (t.idNumberMasked != null) 'ID ${t.idNumberMasked}',
                    if (t.schoolGrade != null) 'Grade ${t.schoolGrade}',
                    if (t.isChild) 'Child',
                  ].join(' · ')),
                ),
              if (b.guardian != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.family_restroom),
                  title: Text('Guardian: ${b.guardian!.guardianName} (${b.guardian!.guardianRelationship})'),
                  subtitle: Text('Emergency: ${b.guardian!.emergencyContactName} · ${b.guardian!.emergencyContactPhone}'),
                ),

              const SectionTitle("What's included"),
              WhatsIncludedSection(included: b.included),

              // ---------- Cancellation ----------
              const SectionTitle('Cancellation'),
              Text(b.policyText),
              if (b.status == 'cancelled') ...[
                const SizedBox(height: 8),
                Text('Cancelled on ${formatDate(b.cancelledAt!)}${b.cancellationReason == null ? '' : ' – ${b.cancellationReason}'}'),
                if (b.refundCents > 0)
                  Text(b.refundStatus == 'refunded' ? 'Refund of ${rand(b.refundCents)} paid.' : 'Refund of ${rand(b.refundCents)} on its way.',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
              ] else if (b.canCancel && b.cancellationDeadline != null) ...[
                const SizedBox(height: 8),
                Text(_deadlineText(b.cancellationDeadline!), style: const TextStyle(color: AppColors.teal, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 16),
              if (b.isActive)
                Wrap(spacing: 12, runSpacing: 12, children: [
                  OutlinedButton.icon(onPressed: () => _invoice(b), icon: const Icon(Icons.receipt_long), label: const Text('Invoice (PDF)')),
                  if (b.canCancel || b.status == 'pending')
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)),
                      onPressed: () => _cancel(b),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancel booking'),
                    ),
                ]),
              if (b.canReview) ...[
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: () => _review(b), icon: const Icon(Icons.star_outline), label: const Text('Review this trip')),
              ],
              const SizedBox(height: 32),
            ]),
          ),
        ),
      ),
    );
  }

  String _deadlineText(DateTime deadline) {
    final days = deadline.difference(DateTime.now()).inDays;
    final left = days <= 0 ? 'less than a day left' : '$days day${days == 1 ? '' : 's'} left';
    return 'You can cancel until ${formatDate(deadline)} ($left).';
  }
}
