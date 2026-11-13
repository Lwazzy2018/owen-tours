import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../booking/models.dart';

class BookingQuery {
  const BookingQuery({this.status, this.departureId, this.search, this.page = 1});
  final String? status, departureId, search;
  final int page;

  Map<String, dynamic> toQuery() => {'status': status, 'departureId': departureId, 'search': search, 'page': page, 'pageSize': 30};

  @override
  bool operator ==(Object other) =>
      other is BookingQuery && other.status == status && other.departureId == departureId && other.search == search && other.page == page;

  @override
  int get hashCode => Object.hash(status, departureId, search, page);
}

final adminBookingsProvider = FutureProvider.autoDispose.family<Paged<BookingSummary>, BookingQuery>((ref, q) {
  return ref.watch(apiProvider).get('/api/admin/bookings', (d) => Paged.fromJson(d, BookingSummary.fromJson), query: q.toQuery());
});

final adminBookingProvider = FutureProvider.autoDispose.family<Booking, String>((ref, id) {
  return ref.watch(apiProvider).get('/api/admin/bookings/$id', (d) => Booking.fromJson(asJson(d)));
});

class AdminBookingsScreen extends ConsumerStatefulWidget {
  const AdminBookingsScreen({super.key, this.initialStatus, this.departureId});
  final String? initialStatus, departureId;

  @override
  ConsumerState<AdminBookingsScreen> createState() => _AdminBookingsScreenState();
}

class _AdminBookingsScreenState extends ConsumerState<AdminBookingsScreen> {
  late BookingQuery _q = BookingQuery(status: widget.initialStatus, departureId: widget.departureId);
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bookings = ref.watch(adminBookingsProvider(_q));
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Bookings', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 320,
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Reference or name'),
            onSubmitted: (v) => setState(() => _q = BookingQuery(status: _q.status, departureId: _q.departureId, search: v.trim())),
          ),
        ),
        for (final s in const [null, 'pending', 'confirmed', 'paid', 'cancelled'])
          ChoiceChip(
            label: Text(s == null ? 'All' : statusLabel(s)),
            selected: _q.status == s,
            onSelected: (_) => setState(() => _q = BookingQuery(status: s, departureId: _q.departureId, search: _q.search)),
          ),
        if (_q.departureId != null)
          InputChip(
            label: const Text('One departure'),
            onDeleted: () => setState(() => _q = BookingQuery(status: _q.status, search: _q.search)),
          ),
      ]),
      const SizedBox(height: 16),
      AsyncView(
        value: bookings,
        onRetry: () => ref.invalidate(adminBookingsProvider(_q)),
        data: (page) => Card(
          child: Column(children: [
            for (final b in page.items)
              ListTile(
                title: Text('${b.reference} · ${b.customerName}'),
                subtitle: Text('${b.tripTitle} · ${formatDay(b.departureAt)} · ${b.travellers} travellers'),
                trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Pill(statusLabel(b.status), tone: toneForStatus(b.status)),
                  const SizedBox(height: 4),
                  Text('${rand(b.amountPaidCents)} / ${rand(b.totalCents)}', style: const TextStyle(fontSize: 12)),
                  if (b.refundStatus == 'pending') const Text('Refund due', style: TextStyle(color: AppColors.error, fontSize: 12)),
                ]),
                onTap: () => context.go('/admin/bookings/${b.id}'),
              ),
            if (page.items.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No bookings found.')),
            if (page.totalPages > 1)
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(
                  onPressed: _q.page <= 1 ? null : () => setState(() => _q = BookingQuery(status: _q.status, departureId: _q.departureId, search: _q.search, page: _q.page - 1)),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('Page ${page.page} of ${page.totalPages}'),
                IconButton(
                  onPressed: _q.page >= page.totalPages
                      ? null
                      : () => setState(() => _q = BookingQuery(status: _q.status, departureId: _q.departureId, search: _q.search, page: _q.page + 1)),
                  icon: const Icon(Icons.chevron_right),
                ),
              ]),
          ]),
        ),
      ),
    ]);
  }
}

class AdminBookingDetailScreen extends ConsumerWidget {
  const AdminBookingDetailScreen({super.key, required this.id});
  final String id;

  void _refresh(WidgetRef ref) {
    ref.invalidate(adminBookingProvider(id));
    ref.invalidate(adminBookingsProvider);
  }

  Future<void> _recordPayment(BuildContext context, WidgetRef ref, Booking b) async {
    final amount = TextEditingController(text: centsToRandInput(b.nextInstalment?.amountCents ?? b.balanceCents));
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Record a payment received'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('For EFT or cash received outside the app. Balance: ${rand(b.balanceCents)}'),
          const SizedBox(height: 12),
          TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (R)')),
          const SizedBox(height: 12),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'Note, e.g. EFT reference')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Record payment')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final cents = parseRandToCents(amount.text);
    if (cents == null || cents <= 0) {
      showSnack(context, 'Enter a valid amount.', error: true);
      return;
    }
    final done = await runAction(
      context,
      () => ref.read(apiProvider).put('/api/admin/bookings/${b.id}/status', (_) {},
          body: {'action': 'record_payment', 'amountReceivedCents': cents, 'note': note.text.trim()}),
      success: 'Payment recorded.',
    );
    if (done) _refresh(ref);
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, Booking b) async {
    final reason = TextEditingController();
    final refund = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancel booking (staff)'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Paid so far: ${rand(b.amountPaidCents)}\nPolicy: ${b.policyText}'),
          const SizedBox(height: 12),
          TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason (required)', hintText: 'e.g. medical emergency')),
          const SizedBox(height: 12),
          TextField(
            controller: refund,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Refund amount (R)', helperText: 'Leave empty to use the cancellation policy'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Back')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (reason.text.trim().length < 3) {
      showSnack(context, 'Please give a reason.', error: true);
      return;
    }
    final done = await runAction(
      context,
      () => ref.read(apiProvider).post('/api/admin/bookings/${b.id}/cancel', (_) {}, body: {
        'reason': reason.text.trim(),
        'refundCentsOverride': refund.text.trim().isEmpty ? null : parseRandToCents(refund.text),
      }),
      success: 'Booking cancelled.',
    );
    if (done) _refresh(ref);
  }

  Future<void> _markRefunded(BuildContext context, WidgetRef ref, Booking b) async {
    final done = await runAction(context, () => ref.read(apiProvider).put('/api/admin/bookings/${b.id}/refund', (_) {}),
        success: 'Refund marked as paid.');
    if (done) _refresh(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booking = ref.watch(adminBookingProvider(id));
    return AsyncView(
      value: booking,
      onRetry: () => ref.invalidate(adminBookingProvider(id)),
      data: (b) => ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          IconButton(onPressed: () => context.go('/admin/bookings'), icon: const Icon(Icons.arrow_back)),
          Expanded(child: Text('${b.reference} · ${b.customerName}', style: Theme.of(context).textTheme.headlineSmall)),
          Pill(statusLabel(b.status), tone: toneForStatus(b.status)),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: [
          if (b.isActive && b.balanceCents > 0)
            FilledButton.icon(onPressed: () => _recordPayment(context, ref, b), icon: const Icon(Icons.payments), label: const Text('Record payment')),
          if (b.isActive)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)),
              onPressed: () => _cancel(context, ref, b),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel booking'),
            ),
          if (b.refundStatus == 'pending')
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.green),
              onPressed: () => _markRefunded(context, ref, b),
              icon: const Icon(Icons.check),
              label: Text('Mark refund of ${rand(b.refundCents)} as paid'),
            ),
        ]),
        const SectionTitle('Trip'),
        Text(b.tripTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
        Text('${formatDateTime(b.departure.departureAt)} · ${b.departure.meetingPlace}, ${b.departure.departsFrom}'),
        const SectionTitle('Money'),
        KeyValueRow('Subtotal', rand(b.subtotalCents)),
        if (b.discount != null) KeyValueRow('${b.discount!.name} (${statusLabel(b.discount!.status)})', '-${rand(b.discountCents)}'),
        KeyValueRow('Total', rand(b.totalCents), bold: true),
        KeyValueRow('Deposit', rand(b.depositCents)),
        KeyValueRow('Paid', rand(b.amountPaidCents), valueColor: AppColors.green),
        KeyValueRow('Balance', rand(b.balanceCents), bold: true),
        if (b.refundCents > 0) KeyValueRow('Refund (${b.refundStatus})', rand(b.refundCents), valueColor: AppColors.error),
        if (b.instalments.isNotEmpty) ...[
          const SectionTitle('Instalments'),
          for (final i in b.instalments)
            ListTile(
              dense: true,
              title: Text('#${i.sequence} · ${rand(i.amountCents)} due ${formatDateOnly(i.dueDate)}'),
              trailing: Pill(statusLabel(i.status), tone: toneForStatus(i.status)),
            ),
        ],
        const SectionTitle('Payments'),
        for (final p in b.payments)
          ListTile(
            dense: true,
            title: Text('${titleCase(p.purpose)} · ${rand(p.amountCents)}'),
            subtitle: Text(formatDateTime(p.paidAt ?? p.createdAt)),
            trailing: Text(p.status),
          ),
        if (b.payments.isEmpty) const Text('No payments yet.'),
        const SectionTitle('Travellers'),
        for (final t in b.travellers)
          ListTile(
            dense: true,
            title: Text(t.fullName),
            subtitle: Text([
              if (t.idNumberMasked != null) 'ID ${t.idNumberMasked}',
              if (t.passportNumberMasked != null) 'Passport ${t.passportNumberMasked} (exp ${t.passportExpiry ?? '-'})',
              if (t.phone != null) t.phone!,
              if (t.schoolGrade != null) 'Grade ${t.schoolGrade}',
              if (t.medicalNotes != null) 'Medical: ${t.medicalNotes}',
              if (t.allergies != null) 'Allergies: ${t.allergies}',
            ].join(' · ')),
          ),
        if (b.guardian != null)
          ListTile(
            dense: true,
            leading: const Icon(Icons.family_restroom),
            title: Text('${b.guardian!.guardianName} (${b.guardian!.guardianRelationship}) · ${b.guardian!.guardianPhone}'),
            subtitle: Text('Emergency: ${b.guardian!.emergencyContactName} · ${b.guardian!.emergencyContactPhone}'),
          ),
        const SectionTitle('Cancellation policy agreed'),
        Text(b.policyText),
        if (b.cancellationReason != null) Text('Cancelled: ${b.cancellationReason}'),
        const SizedBox(height: 48),
      ]),
    );
  }
}
