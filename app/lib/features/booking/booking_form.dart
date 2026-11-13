import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_client.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../auth/auth.dart';
import '../trips/data.dart';
import '../trips/models.dart';
import 'data.dart';
import 'models.dart';

class BookingFormScreen extends ConsumerWidget {
  const BookingFormScreen({super.key, required this.tripId, this.departureId});
  final String tripId;
  final String? departureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(tripDetailProvider(tripId));
    return Scaffold(
      appBar: AppBar(title: const Text('Book your trip')),
      body: AsyncView(
        value: trip,
        onRetry: () => ref.invalidate(tripDetailProvider(tripId)),
        data: (t) {
          final open = t.departures.where((d) => d.bookingOpen).toList();
          if (open.isEmpty) {
            return const EmptyView(icon: Icons.event_busy, title: 'No open dates', message: 'Bookings for this trip are closed.');
          }
          final selected = open.firstWhere((d) => d.id == departureId, orElse: () => open.first);
          return _BookingForm(trip: t, departures: open, initial: selected);
        },
      ),
    );
  }
}

class _BookingForm extends ConsumerStatefulWidget {
  const _BookingForm({required this.trip, required this.departures, required this.initial});
  final TripDetail trip;
  final List<Departure> departures;
  final Departure initial;

  @override
  ConsumerState<_BookingForm> createState() => _BookingFormState();
}

class _BookingFormState extends ConsumerState<_BookingForm> {
  final _form = GlobalKey<FormState>();
  late Departure _departure = widget.initial;
  final List<TravellerDraft> _travellers = [TravellerDraft()];
  final _promo = TextEditingController();
  String? _appliedPromo;
  bool _wantsStudent = false;
  String _plan = 'full';
  bool _acceptedPolicy = false;

  // Guardian (youth camps)
  final _guardianName = TextEditingController();
  final _guardianPhone = TextEditingController();
  final _guardianRelationship = TextEditingController();
  final _emergencyName = TextEditingController();
  final _emergencyPhone = TextEditingController();
  bool _consent = false;

  PricePreview? _preview;
  ApiException? _previewError;
  ApiException? _submitError;
  bool _submitting = false;
  Timer? _debounce;

  TripDetail get trip => widget.trip;
  bool get _hasStudentSpecial => trip.specials.any((s) => s.type == 'student');

  @override
  void initState() {
    super.initState();
    final me = ref.read(meProvider).valueOrNull;
    if (me != null && !trip.isYouthCamp) {
      _travellers.first.fullName = me.fullName;
      _travellers.first.phone = me.phone ?? '';
    }
    if (trip.isYouthCamp) {
      // Learners are priced per learner (the "child" price type isn't used for camps).
      if (me != null) {
        _guardianName.text = me.fullName;
        _guardianPhone.text = me.phone ?? '';
      }
    }
    _refreshPreview();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_promo, _guardianName, _guardianPhone, _guardianRelationship, _emergencyName, _emergencyPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  void _refreshPreview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final p = await ref.read(bookingRepositoryProvider).preview(
              departureId: _departure.id,
              adults: _travellers.where((t) => !t.isChild).length,
              children: _travellers.where((t) => t.isChild).length,
              promoCode: _appliedPromo,
              wantsStudentDiscount: _wantsStudent,
            );
        if (!mounted) return;
        setState(() {
          _preview = p;
          _previewError = null;
          if (!p.instalmentsAvailable) _plan = 'full';
        });
      } catch (e) {
        if (mounted) setState(() => _previewError = ApiException.from(e));
      }
    });
  }

  Future<void> _submit() async {
    setState(() => _submitError = null);
    if (!_form.currentState!.validate()) {
      showSnack(context, 'Please fix the highlighted fields.', error: true);
      return;
    }
    if (!_acceptedPolicy) {
      setState(() => _submitError = ApiException('Please read and agree to the cancellation policy.'));
      return;
    }
    if (trip.isYouthCamp && !_consent) {
      setState(() => _submitError = ApiException('The guardian must give permission for the learner to attend.'));
      return;
    }

    setState(() => _submitting = true);
    try {
      final body = <String, dynamic>{
        'departureId': _departure.id,
        'paymentPlan': _plan,
        'travellers': _travellers.map((t) => t.toJson()).toList(),
        'promoCode': _appliedPromo,
        'wantsStudentDiscount': _wantsStudent,
        'acceptedCancellationPolicy': _acceptedPolicy,
        if (trip.isYouthCamp)
          'guardian': {
            'guardianName': _guardianName.text.trim(),
            'guardianPhone': _guardianPhone.text.trim(),
            'guardianRelationship': _guardianRelationship.text.trim(),
            'emergencyContactName': _emergencyName.text.trim(),
            'emergencyContactPhone': _emergencyPhone.text.trim(),
            'consentGiven': _consent,
          },
      };
      final (booking, warnings) = await ref.read(bookingRepositoryProvider).create(body);
      if (!mounted) return;
      ref.invalidate(myBookingsProvider);

      if (warnings.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Please note'),
            content: Text(warnings.join('\n\n')),
            actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
          ),
        );
      }
      if (!mounted) return;
      if (_wantsStudent && booking.discount?.status == 'pending_verification') {
        await _askForStudentId(booking.id);
      }
      if (!mounted) return;
      if (booking.status == 'paid') {
        context.go('/bookings/${booking.id}');
      } else {
        context.go('/bookings/${booking.id}?pay=${booking.paymentPlan == 'instalments' ? 'deposit' : 'full'}');
      }
    } catch (e) {
      setState(() => _submitError = ApiException.from(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _askForStudentId(String bookingId) async {
    final pick = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Upload your student ID'),
        content: const Text(
            'Take a clear photo of a valid student ID. Our team checks it and the discount is applied once approved. Until then the normal price shows.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Later')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Choose photo')),
        ],
      ),
    );
    if (pick != true || !mounted) return;
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, imageQuality: 90);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    await runAction(
      context,
      () => ref.read(bookingRepositoryProvider).uploadStudentId(bookingId, bytes, file.name, file.mimeType ?? 'image/jpeg'),
      success: 'Student ID uploaded. We\'ll let you know once it\'s checked.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    return Form(
      key: _form,
      child: Constrained(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(trip.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),

          // ---------- Date ----------
          const SectionTitle('1. Choose your date'),
          for (final d in widget.departures)
            Card(
              child: RadioListTile<String>(
                value: d.id,
                groupValue: _departure.id,
                onChanged: (_) {
                  setState(() => _departure = d);
                  _refreshPreview();
                },
                title: Text('${formatDay(d.departureAt)} · ${rand(d.adultPriceCents)}'),
                subtitle: Text('From ${d.departsFrom} · ${d.meetingPlace} at ${formatTime(d.departureAt)}\n${d.seatsLeft} seats left'),
                isThreeLine: true,
              ),
            ),

          // ---------- Travellers ----------
          SectionTitle(trip.isYouthCamp ? '2. Learner details' : '2. Who is travelling?'),
          if (trip.isCrossBorder)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SandBox(
                child: Text(
                    'This trip crosses into ${trip.destinationCountry}. Every traveller needs a valid passport. Children may need extra documents such as a birth certificate and parental consent.'),
              ),
            ),
          for (var i = 0; i < _travellers.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _TravellerCard(
                key: ObjectKey(_travellers[i]),
                index: i,
                draft: _travellers[i],
                trip: trip,
                returnDate: DateTime.parse(_departure.returnDate),
                onChanged: () => setState(() {}),
                onTypeChanged: _refreshPreview,
                onRemove: _travellers.length == 1
                    ? null
                    : () {
                        setState(() => _travellers.removeAt(i));
                        _refreshPreview();
                      },
              ),
            ),
          OutlinedButton.icon(
            onPressed: _travellers.length >= (p?.seatsLeft ?? _departure.seatsLeft)
                ? null
                : () {
                    setState(() => _travellers.add(TravellerDraft()));
                    _refreshPreview();
                  },
            icon: const Icon(Icons.person_add_alt),
            label: Text(trip.isYouthCamp ? 'Add another learner' : 'Add another traveller'),
          ),

          // ---------- Guardian ----------
          if (trip.isYouthCamp) ...[
            const SectionTitle('3. Parent / guardian'),
            TextFormField(controller: _guardianName, decoration: const InputDecoration(labelText: 'Guardian full name'), validator: _required),
            const SizedBox(height: 12),
            TextFormField(
                controller: _guardianPhone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Guardian cellphone'),
                validator: _required),
            const SizedBox(height: 12),
            TextFormField(
                controller: _guardianRelationship,
                decoration: const InputDecoration(labelText: 'Relationship to learner', hintText: 'e.g. Mother'),
                validator: _required),
            const SizedBox(height: 12),
            TextFormField(controller: _emergencyName, decoration: const InputDecoration(labelText: 'Emergency contact name'), validator: _required),
            const SizedBox(height: 12),
            TextFormField(
                controller: _emergencyPhone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Emergency contact cellphone'),
                validator: _required),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _consent,
              onChanged: (v) => setState(() => _consent = v ?? false),
              title: const Text('I give permission for my child to attend and take part in the listed activities.'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],

          // ---------- Discounts ----------
          SectionTitle('${trip.isYouthCamp ? 4 : 3}. Discounts'),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _promo,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: 'Promo code', errorText: p?.promoCodeError),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () {
                setState(() => _appliedPromo = _promo.text.trim().isEmpty ? null : _promo.text.trim());
                _refreshPreview();
              },
              child: const Text('Apply'),
            ),
          ]),
          if (_hasStudentSpecial)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _wantsStudent,
              onChanged: (v) {
                setState(() => _wantsStudent = v ?? false);
                _refreshPreview();
              },
              title: const Text('I have a valid student ID'),
              subtitle: const Text('You\'ll upload a photo after booking. The discount applies once our team approves it.'),
              controlAffinity: ListTileControlAffinity.leading,
            ),

          // ---------- Price and payment ----------
          SectionTitle('${trip.isYouthCamp ? 5 : 4}. Price and payment'),
          if (_previewError != null) ErrorBanner(error: _previewError!),
          if (p == null && _previewError == null) const LinearProgressIndicator(),
          if (p != null) ...[
            SandBox(
              child: Column(children: [
                if (p.adults > 0) KeyValueRow('${p.adults} × adult (${rand(p.adultPriceCents)})', rand(p.adults * p.adultPriceCents)),
                if (p.children > 0) KeyValueRow('${p.children} × child (${rand(p.childPriceCents)})', rand(p.children * p.childPriceCents)),
                if (p.discountName != null)
                  KeyValueRow(
                    p.discountPendingVerification ? '${p.discountName} (after approval)' : p.discountName!,
                    '-${rand(p.discountCents)}',
                    valueColor: AppColors.green,
                  ),
                const Divider(height: 16),
                KeyValueRow('Total', rand(p.totalCents), bold: true),
              ]),
            ),
            const SizedBox(height: 12),
            RadioListTile<String>(
              value: 'full',
              groupValue: _plan,
              onChanged: (v) => setState(() => _plan = v!),
              title: Text('Pay in full now – ${rand(p.totalCents)}'),
            ),
            if (p.instalmentsAvailable)
              RadioListTile<String>(
                value: 'instalments',
                groupValue: _plan,
                onChanged: (v) => setState(() => _plan = v!),
                title: Text('Pay a ${rand(p.depositCents)} deposit now, the rest monthly'),
                subtitle: Text(p.instalmentPlan.map((i) => '${formatDateOnly(i.dueDate)}: ${rand(i.amountCents)}').join('\n')),
              ),
          ],

          // ---------- Policy ----------
          const SectionTitle('Cancellation policy'),
          SandBox(child: Text(p?.policyText ?? _departure.policyText)),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _acceptedPolicy,
            onChanged: (v) => setState(() => _acceptedPolicy = v ?? false),
            title: const Text('I have read and agree to the cancellation policy'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 12),
          if (_submitError != null) ...[ErrorBanner(error: _submitError!), const SizedBox(height: 12)],
          CtaButton(
            label: _submitting
                ? 'Reserving your seats…'
                : p == null
                    ? 'Continue'
                    : _plan == 'instalments'
                        ? 'Book and pay ${rand(p.depositCents)} deposit'
                        : 'Book and pay ${rand(p.totalCents)}',
            onPressed: _submitting || p == null || !_acceptedPolicy ? null : _submit,
          ),
          const SizedBox(height: 8),
          const Text('Your seats are held for 20 minutes while you pay.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.secondaryText, fontSize: 12)),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }

  static String? _required(String? v) => (v ?? '').trim().isEmpty ? 'Required' : null;
}

class _TravellerCard extends StatefulWidget {
  const _TravellerCard({
    super.key,
    required this.index,
    required this.draft,
    required this.trip,
    required this.returnDate,
    required this.onChanged,
    required this.onTypeChanged,
    this.onRemove,
  });

  final int index;
  final TravellerDraft draft;
  final TripDetail trip;
  final DateTime returnDate;
  final VoidCallback onChanged;
  final VoidCallback onTypeChanged;
  final VoidCallback? onRemove;

  @override
  State<_TravellerCard> createState() => _TravellerCardState();
}

class _TravellerCardState extends State<_TravellerCard> {
  TravellerDraft get t => widget.draft;
  TripDetail get trip => widget.trip;

  Future<DateTime?> _pickDate({required DateTime initial, required DateTime first, required DateTime last}) =>
      showDatePicker(context: context, initialDate: initial, firstDate: first, lastDate: last);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final passportWarning = t.passportExpiry != null &&
        t.passportExpiry!.isAfter(widget.returnDate) &&
        t.passportExpiry!.isBefore(DateTime(widget.returnDate.year, widget.returnDate.month + 6, widget.returnDate.day));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(trip.isYouthCamp ? 'Learner ${widget.index + 1}' : 'Traveller ${widget.index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (widget.onRemove != null) IconButton(onPressed: widget.onRemove, icon: const Icon(Icons.delete_outline), tooltip: 'Remove'),
          ]),
          TextFormField(
            initialValue: t.fullName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Full name (as on ID or passport)'),
            onChanged: (v) => t.fullName = v,
            validator: (v) => (v ?? '').trim().length < 2 ? 'Enter the full name' : null,
          ),
          const SizedBox(height: 12),
          if (trip.isCrossBorder) ...[
            TextFormField(
              initialValue: t.passportNumber,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Passport number'),
              onChanged: (v) => t.passportNumber = v,
              validator: (v) => (v ?? '').trim().isEmpty ? 'A passport is needed for this trip' : null,
            ),
            const SizedBox(height: 12),
            _DateField(
              label: 'Passport expiry date',
              value: t.passportExpiry,
              errorText: t.passportExpiry != null && !t.passportExpiry!.isAfter(widget.returnDate)
                  ? 'This passport expires before the trip ends'
                  : null,
              helperText: passportWarning ? 'Expires within 6 months of the trip – some borders may refuse entry.' : null,
              onTap: () async {
                final d = await _pickDate(initial: t.passportExpiry ?? now.add(const Duration(days: 365)), first: now, last: DateTime(now.year + 15));
                if (d != null) setState(() => t.passportExpiry = d);
                widget.onChanged();
              },
            ),
          ] else
            TextFormField(
              initialValue: t.idNumber,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'SA ID number (or passport number)'),
              onChanged: (v) => t.idNumber = v,
              validator: (v) {
                final value = (v ?? '').replaceAll(' ', '');
                if (value.isEmpty) return 'Enter an ID or passport number';
                if (RegExp(r'^\d+$').hasMatch(value) && value.length != 13) return 'An SA ID number has 13 digits';
                if (!RegExp(r'^\d+$').hasMatch(value)) {
                  t.passportNumber = value;
                  t.idNumber = '';
                }
                return null;
              },
            ),
          if (widget.index == 0 && !trip.isYouthCamp) ...[
            const SizedBox(height: 12),
            TextFormField(
              initialValue: t.phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Cellphone number'),
              onChanged: (v) => t.phone = v,
            ),
          ],
          if (trip.isYouthCamp || trip.isAdultsOnly) ...[
            const SizedBox(height: 12),
            _DateField(
              label: 'Date of birth',
              value: t.dateOfBirth,
              onTap: () async {
                final d = await _pickDate(
                    initial: t.dateOfBirth ?? DateTime(now.year - (trip.isYouthCamp ? 15 : 25)), first: DateTime(1920), last: now);
                if (d != null) setState(() => t.dateOfBirth = d);
                widget.onChanged();
              },
            ),
          ],
          if (trip.isYouthCamp) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: t.schoolGrade,
              decoration: const InputDecoration(labelText: 'School grade'),
              items: [
                for (var g = trip.minGrade ?? 8; g <= (trip.maxGrade ?? 12); g++) DropdownMenuItem(value: g, child: Text('Grade $g')),
              ],
              onChanged: (g) => setState(() => t.schoolGrade = g),
              validator: (g) => g == null ? 'Choose the grade' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: t.medicalNotes,
              decoration: const InputDecoration(labelText: 'Medical conditions', hintText: 'Write "None" if none'),
              onChanged: (v) => t.medicalNotes = v,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Required – write "None" if none' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: t.allergies,
              decoration: const InputDecoration(labelText: 'Allergies', hintText: 'Write "None" if none'),
              onChanged: (v) => t.allergies = v,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Required – write "None" if none' : null,
            ),
          ],
          if (!trip.isYouthCamp && !trip.isAdultsOnly)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: t.isChild,
              onChanged: (v) {
                setState(() => t.isChild = v);
                widget.onTypeChanged();
              },
              title: const Text('Child (under 18)'),
            ),
        ]),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onTap, this.errorText, this.helperText});
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final String? errorText, helperText;

  @override
  Widget build(BuildContext context) => FormField<DateTime>(
        validator: (_) => value == null ? 'Choose a date' : errorText,
        builder: (state) => InkWell(
          onTap: onTap,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              errorText: state.errorText ?? errorText,
              helperText: helperText,
              helperMaxLines: 2,
              suffixIcon: const Icon(Icons.calendar_today_outlined),
            ),
            child: Text(value == null ? 'Tap to choose' : formatDateOnly(toIsoDate(value!))),
          ),
        ),
      );
}
