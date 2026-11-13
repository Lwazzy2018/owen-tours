import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/file_saver.dart';
import '../trips/models.dart';

final adminTripsProvider = FutureProvider.autoDispose<Paged<TripSummary>>((ref) {
  return ref.watch(apiProvider).get('/api/admin/trips', (d) => Paged.fromJson(d, TripSummary.fromJson), query: {'pageSize': 50});
});

final adminTripProvider = FutureProvider.autoDispose.family<TripDetail, String>((ref, id) {
  return ref.watch(apiProvider).get('/api/admin/trips/$id', (d) => TripDetail.fromJson(asJson(d)));
});

final adminDeparturesProvider = FutureProvider.autoDispose.family<List<Departure>, String>((ref, tripId) {
  return ref.watch(apiProvider).get('/api/admin/trips/$tripId/departures', (d) => asList(d, Departure.fromJson));
});

// ============================ Trip list ============================

class AdminTripsScreen extends ConsumerWidget {
  const AdminTripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(adminTripsProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/admin/trips/new'),
        icon: const Icon(Icons.add),
        label: const Text('New trip'),
      ),
      body: AsyncView(
        value: trips,
        onRetry: () => ref.invalidate(adminTripsProvider),
        data: (page) => ListView(padding: const EdgeInsets.all(20), children: [
          Text('Trips', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          for (final t in page.items)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: NetImage(t.coverImageUrl, width: 64, height: 48, radius: 8),
                title: Text(t.title),
                subtitle: Text([
                  t.destination,
                  if (t.nextDepartureAt != null) 'next ${formatDay(t.nextDepartureAt!)}',
                  if (t.departsFrom.isNotEmpty) t.departsFrom.join(', '),
                ].join(' · ')),
                trailing: Pill(t.isPublished ? 'Published' : 'Draft', tone: t.isPublished ? PillTone.success : PillTone.neutral),
                onTap: () => context.go('/admin/trips/${t.id}'),
              ),
            ),
          if (page.items.isEmpty) const EmptyView(icon: Icons.travel_explore, title: 'No trips yet', message: 'Create your first trip.'),
        ]),
      ),
    );
  }
}

// ============================ Trip editor ============================

class AdminTripEditorScreen extends ConsumerWidget {
  const AdminTripEditorScreen({super.key, this.tripId});
  final String? tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tripId == null) return const _TripForm(trip: null);
    final trip = ref.watch(adminTripProvider(tripId!));
    return AsyncView(value: trip, onRetry: () => ref.invalidate(adminTripProvider(tripId!)), data: (t) => _TripForm(key: ValueKey(t.id), trip: t));
  }
}

class _TripForm extends ConsumerStatefulWidget {
  const _TripForm({super.key, required this.trip});
  final TripDetail? trip;

  @override
  ConsumerState<_TripForm> createState() => _TripFormState();
}

class _TripFormState extends ConsumerState<_TripForm> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.trip?.title);
  late final _destination = TextEditingController(text: widget.trip?.destination);
  late final _country = TextEditingController(text: widget.trip?.destinationCountry ?? 'South Africa');
  late final _tagline = TextEditingController(text: widget.trip?.tagline);
  late final _description = TextEditingController(text: widget.trip?.description);
  late final _activities = TextEditingController(text: widget.trip?.activities.join('\n'));
  late final _includes = TextEditingController(text: widget.trip?.included.otherIncludes.join('\n'));
  late final _excludes = TextEditingController(text: widget.trip?.included.excludes.join('\n'));
  late final _transportNotes = TextEditingController(text: widget.trip?.included.transportNotes);
  late final _mealsNotes = TextEditingController(text: widget.trip?.included.mealsNotes);
  late final _accommodationNotes = TextEditingController(text: widget.trip?.included.accommodationNotes);

  late String _category = widget.trip?.category ?? 'weekend_getaway';
  late String _audience = widget.trip?.audience ?? 'everyone';
  late int _minGrade = widget.trip?.minGrade ?? 8;
  late int _maxGrade = widget.trip?.maxGrade ?? 12;
  late bool _transport = widget.trip?.included.transportIncluded ?? true;
  late String _transportType = widget.trip?.included.transportType ?? 'bus';
  late bool _breakfast = widget.trip?.included.breakfast ?? false;
  late bool _lunch = widget.trip?.included.lunch ?? false;
  late bool _dinner = widget.trip?.included.dinner ?? false;
  late bool _snacks = widget.trip?.included.snacks ?? false;
  late bool _accommodation = widget.trip?.included.accommodationIncluded ?? false;
  late String _accommodationType = widget.trip?.included.accommodationType ?? 'hotel';
  late bool _published = widget.trip?.isPublished ?? false;
  late final List<ItineraryDay> _itinerary = [...?widget.trip?.itinerary];
  bool _saving = false;
  ApiException? _error;

  bool get _isNew => widget.trip == null;

  @override
  void dispose() {
    for (final c in [_title, _destination, _country, _tagline, _description, _activities, _includes, _excludes, _transportNotes, _mealsNotes, _accommodationNotes]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _lines(TextEditingController c) => c.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {
      'title': _title.text.trim(),
      'destination': _destination.text.trim(),
      'destinationCountry': _country.text.trim(),
      'category': _category,
      'audience': _audience,
      'minGrade': _audience == 'high_school' ? _minGrade : null,
      'maxGrade': _audience == 'high_school' ? _maxGrade : null,
      'activities': _lines(_activities),
      'tagline': _tagline.text.trim(),
      'description': _description.text.trim(),
      'transportIncluded': _transport,
      'transportType': _transport ? _transportType : null,
      'transportNotes': _transportNotes.text.trim(),
      'mealsBreakfast': _breakfast,
      'mealsLunch': _lunch,
      'mealsDinner': _dinner,
      'mealsSnacks': _snacks,
      'mealsNotes': _mealsNotes.text.trim(),
      'accommodationIncluded': _accommodation,
      'accommodationType': _accommodation ? _accommodationType : null,
      'accommodationNotes': _accommodationNotes.text.trim(),
      'includes': _lines(_includes),
      'excludes': _lines(_excludes),
      'isPublished': _published,
      'itinerary': [for (var i = 0; i < _itinerary.length; i++) ItineraryDay(i + 1, _itinerary[i].title, _itinerary[i].description).toJson()],
    };
    try {
      final api = ref.read(apiProvider);
      final saved = _isNew
          ? await api.post('/api/admin/trips', (d) => TripDetail.fromJson(asJson(d)), body: body)
          : await api.put('/api/admin/trips/${widget.trip!.id}', (d) => TripDetail.fromJson(asJson(d)), body: body);
      ref.invalidate(adminTripsProvider);
      if (!mounted) return;
      showSnack(context, 'Trip saved.');
      if (_isNew) {
        context.go('/admin/trips/${saved.id}');
      } else {
        ref.invalidate(adminTripProvider(saved.id));
      }
    } catch (e) {
      setState(() => _error = ApiException.from(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uploadImages() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true, withData: true);
    if (result == null || !mounted) return;
    final api = ref.read(apiProvider);
    for (final f in result.files) {
      if (f.bytes == null) continue;
      final ok = await runAction(context, () => api.upload('/api/admin/trips/${widget.trip!.id}/images', (_) {},
          bytes: f.bytes!, filename: f.name, contentType: _imageType(f.extension)));
      if (!ok || !mounted) break;
    }
    ref.invalidate(adminTripProvider(widget.trip!.id));
  }

  Future<void> _deleteImage(TripImage image) async {
    final ok = await runAction(context, () => ref.read(apiProvider).delete('/api/admin/trips/${widget.trip!.id}/images/${image.id}'));
    if (ok) ref.invalidate(adminTripProvider(widget.trip!.id));
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    return Form(
      key: _form,
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          IconButton(onPressed: () => context.go('/admin/trips'), icon: const Icon(Icons.arrow_back)),
          Expanded(child: Text(_isNew ? 'New trip' : trip!.title, style: Theme.of(context).textTheme.headlineSmall)),
          FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save), label: Text(_saving ? 'Saving…' : 'Save')),
        ]),
        if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(error: _error!)],
        SwitchListTile(
          value: _published,
          onChanged: (v) => setState(() => _published = v),
          title: const Text('Published'),
          subtitle: const Text('Customers can see and book published trips.'),
        ),

        const SectionTitle('Basics'),
        TextFormField(controller: _title, decoration: const InputDecoration(labelText: 'Title'), validator: _required),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextFormField(controller: _destination, decoration: const InputDecoration(labelText: 'Destination'), validator: _required)),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _country,
              decoration: const InputDecoration(labelText: 'Country', helperText: 'Not South Africa = passports required'),
              validator: _required,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [for (final c in tripCategories) DropdownMenuItem(value: c, child: Text(titleCase(c)))],
              onChanged: (v) => setState(() => _category = v!),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _audience,
              decoration: const InputDecoration(labelText: "Who it's for"),
              items: const [
                DropdownMenuItem(value: 'everyone', child: Text('Everyone')),
                DropdownMenuItem(value: 'adults_only', child: Text('Adults only (18+)')),
                DropdownMenuItem(value: 'high_school', child: Text('High school learners')),
              ],
              onChanged: (v) => setState(() => _audience = v!),
            ),
          ),
        ]),
        if (_audience == 'high_school') ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _gradePicker('From grade', _minGrade, (g) => setState(() => _minGrade = g))),
            const SizedBox(width: 12),
            Expanded(child: _gradePicker('To grade', _maxGrade, (g) => setState(() => _maxGrade = g))),
          ]),
        ],
        const SizedBox(height: 12),
        TextFormField(controller: _tagline, decoration: const InputDecoration(labelText: 'Tagline (optional)')),
        const SizedBox(height: 12),
        TextFormField(controller: _description, maxLines: 5, decoration: const InputDecoration(labelText: 'Description')),
        const SizedBox(height: 12),
        TextFormField(controller: _activities, maxLines: 4, decoration: const InputDecoration(labelText: 'Activities (one per line)')),

        const SectionTitle("What's included"),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              SwitchListTile(value: _transport, onChanged: (v) => setState(() => _transport = v), title: const Text('🚌 Transport included')),
              if (_transport) ...[
                DropdownButtonFormField<String>(
                  value: _transportType,
                  decoration: const InputDecoration(labelText: 'Transport type'),
                  items: const [
                    DropdownMenuItem(value: 'bus', child: Text('Bus')),
                    DropdownMenuItem(value: 'coach', child: Text('Coach')),
                    DropdownMenuItem(value: 'minibus', child: Text('Minibus')),
                    DropdownMenuItem(value: 'flight', child: Text('Flight')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (v) => setState(() => _transportType = v!),
                ),
                const SizedBox(height: 8),
                TextFormField(controller: _transportNotes, decoration: const InputDecoration(labelText: 'Transport notes (optional)')),
              ],
              const Divider(height: 24),
              const Align(alignment: Alignment.centerLeft, child: Text('🍽 Meals included', style: TextStyle(fontWeight: FontWeight.w600))),
              Wrap(spacing: 8, children: [
                FilterChip(label: const Text('Breakfast'), selected: _breakfast, onSelected: (v) => setState(() => _breakfast = v)),
                FilterChip(label: const Text('Lunch'), selected: _lunch, onSelected: (v) => setState(() => _lunch = v)),
                FilterChip(label: const Text('Dinner'), selected: _dinner, onSelected: (v) => setState(() => _dinner = v)),
                FilterChip(label: const Text('Snacks / drinks'), selected: _snacks, onSelected: (v) => setState(() => _snacks = v)),
              ]),
              if (!_breakfast && !_lunch && !_dinner && !_snacks)
                const Align(alignment: Alignment.centerLeft, child: Text('Shown as "No meals included"', style: TextStyle(color: AppColors.secondaryText))),
              const SizedBox(height: 8),
              TextFormField(controller: _mealsNotes, decoration: const InputDecoration(labelText: 'Meal notes, e.g. "Dinner on day 1 only"')),
              const Divider(height: 24),
              SwitchListTile(value: _accommodation, onChanged: (v) => setState(() => _accommodation = v), title: const Text('🏨 Accommodation included')),
              if (_accommodation) ...[
                DropdownButtonFormField<String>(
                  value: _accommodationType,
                  decoration: const InputDecoration(labelText: 'Accommodation type'),
                  items: const [
                    DropdownMenuItem(value: 'hotel', child: Text('Hotel')),
                    DropdownMenuItem(value: 'lodge', child: Text('Lodge')),
                    DropdownMenuItem(value: 'guesthouse', child: Text('Guesthouse')),
                    DropdownMenuItem(value: 'camping', child: Text('Camping')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (v) => setState(() => _accommodationType = v!),
                ),
                const SizedBox(height: 8),
                TextFormField(controller: _accommodationNotes, decoration: const InputDecoration(labelText: 'Accommodation notes (optional)')),
              ],
              const Divider(height: 24),
              TextFormField(controller: _includes, maxLines: 3, decoration: const InputDecoration(labelText: 'Other extras included (one per line)')),
              const SizedBox(height: 8),
              TextFormField(controller: _excludes, maxLines: 3, decoration: const InputDecoration(labelText: 'NOT included (one per line)')),
            ]),
          ),
        ),

        SectionTitle('Day by day',
            trailing: TextButton.icon(
              onPressed: () => setState(() => _itinerary.add(ItineraryDay(_itinerary.length + 1, '', ''))),
              icon: const Icon(Icons.add),
              label: const Text('Add day'),
            )),
        for (var i = 0; i < _itinerary.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(backgroundColor: AppColors.tealTint, child: Text('${i + 1}')),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(children: [
                    TextFormField(
                      initialValue: _itinerary[i].title,
                      decoration: const InputDecoration(labelText: 'Title'),
                      onChanged: (v) => _itinerary[i] = ItineraryDay(i + 1, v, _itinerary[i].description),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: _itinerary[i].description,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'What happens'),
                      onChanged: (v) => _itinerary[i] = ItineraryDay(i + 1, _itinerary[i].title, v),
                    ),
                  ]),
                ),
                IconButton(onPressed: () => setState(() => _itinerary.removeAt(i)), icon: const Icon(Icons.delete_outline)),
              ]),
            ),
          ),

        if (trip != null) ...[
          SectionTitle('Photos', trailing: TextButton.icon(onPressed: _uploadImages, icon: const Icon(Icons.upload), label: const Text('Upload'))),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final img in trip.images)
              Stack(children: [
                NetImage(img.thumbnailUrl ?? img.url, width: 140, height: 100, radius: 8),
                Positioned(
                  right: 0,
                  top: 0,
                  child: IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: AppColors.white),
                    onPressed: () => _deleteImage(img),
                    icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 18),
                  ),
                ),
              ]),
            if (trip.images.isEmpty) const Text('No photos yet. The first photo becomes the cover.'),
          ]),
          SectionTitle('Departures',
              trailing: FilledButton.icon(
                onPressed: () => context.go('/admin/trips/${trip.id}/departures/new'),
                icon: const Icon(Icons.add),
                label: const Text('Add departure'),
              )),
          _DepartureList(tripId: trip.id),
        ] else
          const Padding(padding: EdgeInsets.only(top: 24), child: Text('Save the trip first, then add photos and departures.')),
        const SizedBox(height: 48),
      ]),
    );
  }

  Widget _gradePicker(String label, int value, ValueChanged<int> onChanged) => DropdownButtonFormField<int>(
        value: value,
        decoration: InputDecoration(labelText: label),
        items: [for (var g = 1; g <= 12; g++) DropdownMenuItem(value: g, child: Text('Grade $g'))],
        onChanged: (v) => onChanged(v!),
      );

  static String _imageType(String? ext) => switch ((ext ?? '').toLowerCase()) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'heic' => 'image/heic',
        _ => 'image/jpeg',
      };

  static String? _required(String? v) => (v ?? '').trim().isEmpty ? 'Required' : null;
}

class _DepartureList extends ConsumerWidget {
  const _DepartureList({required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final departures = ref.watch(adminDeparturesProvider(tripId));
    return AsyncView(
      value: departures,
      onRetry: () => ref.invalidate(adminDeparturesProvider(tripId)),
      data: (list) => Column(children: [
        for (final d in list)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text('${formatDateTime(d.departureAt)} · ${d.departsFrom}'),
              subtitle: Text('${d.seatsBooked}/${d.capacity} booked · ${rand(d.adultPriceCents)} · ${d.policyBadge}'
                  '${d.isCancelledByCompany ? ' · CANCELLED' : ''}'),
              trailing: Wrap(spacing: 4, children: [
                IconButton(
                  tooltip: 'Passenger list (PDF)',
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: () => _manifest(context, ref, d, 'pdf'),
                ),
                IconButton(
                  tooltip: 'Passenger list (CSV)',
                  icon: const Icon(Icons.table_view_outlined),
                  onPressed: () => _manifest(context, ref, d, 'csv'),
                ),
                IconButton(
                  tooltip: 'Bookings',
                  icon: const Icon(Icons.confirmation_number_outlined),
                  onPressed: () => context.go('/admin/bookings?departureId=${d.id}'),
                ),
              ]),
              onTap: () => context.go('/admin/trips/$tripId/departures/${d.id}'),
            ),
          ),
        if (list.isEmpty) const Text('No departures yet.'),
      ]),
    );
  }

  Future<void> _manifest(BuildContext context, WidgetRef ref, Departure d, String format) => runAction(context, () async {
        final bytes = await ref.read(apiProvider).download('/api/admin/departures/${d.id}/manifest', query: {'format': format});
        await saveOrShareFile(bytes, 'passengers-${toIsoDate(toSast(d.departureAt))}.$format', format == 'pdf' ? 'application/pdf' : 'text/csv');
      });
}

// ============================ Departure editor ============================

class AdminDepartureEditorScreen extends ConsumerWidget {
  const AdminDepartureEditorScreen({super.key, required this.tripId, this.departureId});
  final String tripId;
  final String? departureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(adminDeparturesProvider(tripId));
    return AsyncView(
      value: all,
      onRetry: () => ref.invalidate(adminDeparturesProvider(tripId)),
      data: (list) {
        final existing = departureId == null ? null : list.where((d) => d.id == departureId).firstOrNull;
        return _DepartureForm(tripId: tripId, departure: existing, others: list.where((d) => d.id != departureId).toList());
      },
    );
  }
}

class _DepartureForm extends ConsumerStatefulWidget {
  const _DepartureForm({required this.tripId, required this.departure, required this.others});
  final String tripId;
  final Departure? departure;
  final List<Departure> others;

  @override
  ConsumerState<_DepartureForm> createState() => _DepartureFormState();
}

class _DepartureFormState extends ConsumerState<_DepartureForm> {
  final _form = GlobalKey<FormState>();
  Departure? get d => widget.departure;

  late String _province = d?.departureProvince ?? 'Mpumalanga';
  late final _area = TextEditingController(text: d?.departureArea ?? 'Mbombela');
  late final _meeting = TextEditingController(text: d?.meetingPlace);
  late DateTime _departAt = d == null ? DateTime.now().add(const Duration(days: 60)) : toSast(d!.departureAt);
  late DateTime _returnDate = d == null ? _departAt.add(const Duration(days: 2)) : DateTime.parse(d!.returnDate);
  late final _capacity = TextEditingController(text: '${d?.capacity ?? 30}');
  late final _adult = TextEditingController(text: d == null ? '' : centsToRandInput(d!.adultPriceCents));
  late final _child = TextEditingController(text: d == null ? '' : centsToRandInput(d!.childPriceCents));
  late DateTime _bookingDeadline = d == null ? _departAt.subtract(const Duration(days: 7)) : toSast(d!.bookingDeadline);
  late bool _instalments = d?.allowInstalments ?? false;
  late final _deposit = TextEditingController(text: d == null || d!.depositCents == 0 ? '' : centsToRandInput(d!.depositCents));
  late DateTime? _finalDue = d?.finalPaymentDue == null ? null : DateTime.parse(d!.finalPaymentDue!);

  // Cancellation policy
  late bool _cancellable = d?.isCancellable ?? true;
  late bool _useDaysBefore = d == null;
  late final _daysBefore = TextEditingController(text: '14');
  late DateTime? _deadline = d?.cancellationDeadline == null ? null : toSast(d!.cancellationDeadline!);
  late String _refundType = d?.refundType ?? 'full';
  late final _refundPercent = TextEditingController(text: d?.refundPercent?.toString() ?? '50');
  late bool _depositRefundable = d?.depositRefundable ?? false;
  late final _notes = TextEditingController(text: d?.cancellationNotes);
  late bool _cancelledByCompany = d?.isCancelledByCompany ?? false;

  bool _saving = false;
  ApiException? _error;

  @override
  void dispose() {
    for (final c in [_area, _meeting, _capacity, _adult, _child, _deposit, _daysBefore, _refundPercent, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  /// SAST wall-clock → UTC ISO string for the API.
  String _utc(DateTime sast) =>
      DateTime.utc(sast.year, sast.month, sast.day, sast.hour, sast.minute).subtract(const Duration(hours: 2)).toIso8601String();

  DateTime get _effectiveDeadline {
    if (_useDaysBefore) {
      final days = int.tryParse(_daysBefore.text) ?? 0;
      final day = DateTime(_departAt.year, _departAt.month, _departAt.day).subtract(Duration(days: days));
      return DateTime(day.year, day.month, day.day, 23, 59);
    }
    return _deadline ?? _departAt.subtract(const Duration(days: 1));
  }

  /// Live preview of how customers will read the policy (the server builds the real text).
  String get _policyPreview {
    if (!_cancellable) return 'Non-refundable. This booking can\'t be cancelled.';
    final until = formatDateOnly(toIsoDate(_effectiveDeadline));
    final deposit = _depositRefundable ? '' : ', deposit not refundable';
    final text = switch (_refundType) {
      'full' => 'Free cancellation until $until – 100% refund$deposit.',
      'partial' => 'Cancel until $until for a ${_refundPercent.text}% refund$deposit.',
      _ => 'You can cancel until $until to free your seat, but no refund is given.',
    };
    return _notes.text.trim().isEmpty ? text : '$text ${_notes.text.trim()}';
  }

  void _copyPolicy(Departure other) {
    setState(() {
      _cancellable = other.isCancellable;
      _refundType = other.refundType;
      _refundPercent.text = other.refundPercent?.toString() ?? '50';
      _depositRefundable = other.depositRefundable;
      _notes.text = other.cancellationNotes ?? '';
      if (other.cancellationDeadline != null) {
        final days = DateTime(toSast(other.departureAt).year, toSast(other.departureAt).month, toSast(other.departureAt).day)
            .difference(DateTime(toSast(other.cancellationDeadline!).year, toSast(other.cancellationDeadline!).month,
                toSast(other.cancellationDeadline!).day))
            .inDays;
        _useDaysBefore = true;
        _daysBefore.text = '$days';
      }
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {
      'departureProvince': _province,
      'departureArea': _area.text.trim(),
      'meetingPlace': _meeting.text.trim(),
      'departureAt': _utc(_departAt),
      'returnDate': toIsoDate(_returnDate),
      'capacity': int.parse(_capacity.text),
      'adultPriceCents': parseRandToCents(_adult.text),
      'childPriceCents': parseRandToCents(_child.text.isEmpty ? _adult.text : _child.text),
      'bookingDeadline': _utc(_bookingDeadline),
      'allowInstalments': _instalments,
      'depositCents': parseRandToCents(_deposit.text) ?? 0,
      'finalPaymentDue': _instalments && _finalDue != null ? toIsoDate(_finalDue!) : null,
      'isCancellable': _cancellable,
      'cancellationDaysBefore': _cancellable && _useDaysBefore ? int.tryParse(_daysBefore.text) : null,
      'cancellationDeadline': _cancellable && !_useDaysBefore && _deadline != null ? _utc(_deadline!) : null,
      'refundType': _cancellable ? _refundType : 'none',
      'refundPercent': _cancellable && _refundType == 'partial' ? int.tryParse(_refundPercent.text) : null,
      'depositRefundable': _cancellable && _depositRefundable,
      'cancellationNotes': _notes.text.trim(),
      'isCancelledByCompany': _cancelledByCompany,
    };
    try {
      final api = ref.read(apiProvider);
      if (d == null) {
        await api.post('/api/admin/trips/${widget.tripId}/departures', (_) {}, body: body);
      } else {
        await api.put('/api/admin/trips/${widget.tripId}/departures/${d!.id}', (_) {}, body: body);
      }
      ref.invalidate(adminDeparturesProvider(widget.tripId));
      if (!mounted) return;
      showSnack(context, 'Departure saved.');
      context.go('/admin/trips/${widget.tripId}');
    } catch (e) {
      setState(() => _error = ApiException.from(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<DateTime?> _pickDateTime(DateTime initial, {bool withTime = true}) async {
    final date = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2024), lastDate: DateTime(2035));
    if (date == null || !withTime || !mounted) return date;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Widget _dateTile(String label, DateTime value, ValueChanged<DateTime> onPicked, {bool withTime = true}) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: Text(withTime ? '${formatDateOnly(toIsoDate(value))}, ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')} (SA time)' : formatDateOnly(toIsoDate(value))),
        trailing: const Icon(Icons.edit_calendar),
        onTap: () async {
          final picked = await _pickDateTime(value, withTime: withTime);
          if (picked != null) setState(() => onPicked(picked));
        },
      );

  @override
  Widget build(BuildContext context) {
    const numbers = TextInputType.number;
    return Form(
      key: _form,
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          IconButton(onPressed: () => context.go('/admin/trips/${widget.tripId}'), icon: const Icon(Icons.arrow_back)),
          Expanded(child: Text(d == null ? 'New departure' : 'Edit departure', style: Theme.of(context).textTheme.headlineSmall)),
          FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save), label: Text(_saving ? 'Saving…' : 'Save')),
        ]),
        if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(error: _error!)],

        const SectionTitle('Where it departs from'),
        DropdownButtonFormField<String>(
          value: _province,
          decoration: const InputDecoration(labelText: 'Province'),
          items: [for (final p in provinces) DropdownMenuItem(value: p, child: Text(p))],
          onChanged: (v) => setState(() => _province = v!),
        ),
        const SizedBox(height: 12),
        TextFormField(controller: _area, decoration: const InputDecoration(labelText: 'Area / town', hintText: 'e.g. Mbombela'), validator: _required),
        const SizedBox(height: 12),
        TextFormField(
            controller: _meeting,
            decoration: const InputDecoration(labelText: 'Meeting place', hintText: 'e.g. Riverside Mall, main entrance'),
            validator: _required),

        const SectionTitle('Dates'),
        _dateTile('Departure', _departAt, (v) => _departAt = v),
        _dateTile('Return date', _returnDate, (v) => _returnDate = v, withTime: false),
        _dateTile('Bookings close', _bookingDeadline, (v) => _bookingDeadline = v),
        if (d != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _cancelledByCompany,
            onChanged: (v) => setState(() => _cancelledByCompany = v),
            title: const Text('Cancelled by Owen Tours'),
            subtitle: const Text('Stops new bookings. Cancel existing bookings from the Bookings page.'),
          ),

        const SectionTitle('Seats and prices'),
        Row(children: [
          Expanded(
            child: TextFormField(
              controller: _capacity,
              keyboardType: numbers,
              decoration: InputDecoration(labelText: 'Seats', helperText: d == null ? null : '${d!.seatsBooked} already booked'),
              validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? 'At least 1' : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _adult,
              keyboardType: numbers,
              decoration: const InputDecoration(labelText: 'Adult price (R)'),
              validator: (v) => parseRandToCents(v ?? '') == null ? 'Enter a price' : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(controller: _child, keyboardType: numbers, decoration: const InputDecoration(labelText: 'Child price (R)', helperText: 'Empty = adult price')),
          ),
        ]),
        const SizedBox(height: 12),
        TextFormField(
          controller: _deposit,
          keyboardType: numbers,
          decoration: const InputDecoration(labelText: 'Deposit per person (R)', helperText: 'e.g. 1000. Leave empty for no deposit.'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _instalments,
          onChanged: (v) => setState(() => _instalments = v),
          title: const Text('Allow paying in instalments (lay-by)'),
          subtitle: const Text('Deposit now, the rest in monthly instalments.'),
        ),
        if (_instalments)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Final payment due'),
            subtitle: Text(_finalDue == null ? 'Choose a date before departure' : formatDateOnly(toIsoDate(_finalDue!))),
            trailing: const Icon(Icons.edit_calendar),
            onTap: () async {
              final picked = await _pickDateTime(_finalDue ?? _departAt.subtract(const Duration(days: 14)), withTime: false);
              if (picked != null) setState(() => _finalDue = picked);
            },
          ),

        SectionTitle('Cancellation policy',
            trailing: widget.others.isEmpty
                ? null
                : PopupMenuButton<Departure>(
                    tooltip: 'Copy from another departure',
                    onSelected: _copyPolicy,
                    itemBuilder: (_) => [
                      for (final o in widget.others)
                        PopupMenuItem(value: o, child: Text('${formatDay(o.departureAt)} · ${o.policyBadge}')),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.copy, size: 18), SizedBox(width: 4), Text('Copy policy')]),
                    ),
                  )),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _cancellable,
          onChanged: (v) => setState(() => _cancellable = v),
          title: const Text('Customers can cancel'),
          subtitle: const Text('Off = "Non-refundable / no cancellations"'),
        ),
        if (_cancellable) ...[
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Days before departure')),
              ButtonSegment(value: false, label: Text('Specific date')),
            ],
            selected: {_useDaysBefore},
            onSelectionChanged: (s) => setState(() => _useDaysBefore = s.first),
          ),
          const SizedBox(height: 12),
          if (_useDaysBefore)
            TextFormField(
              controller: _daysBefore,
              keyboardType: numbers,
              decoration: InputDecoration(labelText: 'Days before departure', helperText: 'Deadline: ${formatDateOnly(toIsoDate(_effectiveDeadline))}, 23:59'),
              onChanged: (_) => setState(() {}),
              validator: (v) => int.tryParse(v ?? '') == null ? 'Enter a number of days' : null,
            )
          else
            _dateTile('Cancellation deadline', _deadline ?? _departAt.subtract(const Duration(days: 14)), (v) => _deadline = v),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _refundType,
            decoration: const InputDecoration(labelText: 'Refund when cancelled'),
            items: const [
              DropdownMenuItem(value: 'full', child: Text('Full refund')),
              DropdownMenuItem(value: 'partial', child: Text('Partial refund (%)')),
              DropdownMenuItem(value: 'none', child: Text('No refund (frees the seat only)')),
            ],
            onChanged: (v) => setState(() => _refundType = v!),
          ),
          if (_refundType == 'partial') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _refundPercent,
              keyboardType: numbers,
              decoration: const InputDecoration(labelText: 'Refund percentage', suffixText: '%'),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final p = int.tryParse(v ?? '');
                return p == null || p < 1 || p > 99 ? 'Between 1 and 99' : null;
              },
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _depositRefundable,
            onChanged: (v) => setState(() => _depositRefundable = v),
            title: const Text('Deposit is refundable'),
          ),
        ],
        TextFormField(
          controller: _notes,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Policy notes in plain words (optional)'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        SandBox(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Customers will see:', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(_policyPreview),
            const SizedBox(height: 8),
            const Text('Existing bookings keep the policy they agreed to.', style: TextStyle(fontSize: 12, color: AppColors.secondaryText)),
          ]),
        ),
        const SizedBox(height: 48),
      ]),
    );
  }

  static String? _required(String? v) => (v ?? '').trim().isEmpty ? 'Required' : null;
}
