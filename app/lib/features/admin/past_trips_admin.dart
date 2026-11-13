import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../past_trips/models.dart';
import 'trips_admin.dart';

final adminPastTripsProvider = FutureProvider.autoDispose<Paged<PastTripSummary>>((ref) {
  return ref.watch(apiProvider).get('/api/admin/past-trips', (d) => Paged.fromJson(d, PastTripSummary.fromJson), query: {'pageSize': 100});
});

final adminPastTripProvider = FutureProvider.autoDispose.family<PastTripDetail, String>((ref, id) {
  return ref.watch(apiProvider).get('/api/admin/past-trips/$id', (d) => PastTripDetail.fromJson(asJson(d)));
});

class AdminPastTripsScreen extends ConsumerWidget {
  const AdminPastTripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(adminPastTripsProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/admin/past-trips/new'),
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('New album'),
      ),
      body: AsyncView(
        value: list,
        onRetry: () => ref.invalidate(adminPastTripsProvider),
        data: (page) => ListView(padding: const EdgeInsets.all(20), children: [
          Text('Our previous trips', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const Text('Albums from trips that already happened, to build trust with new customers.'),
          const SizedBox(height: 12),
          for (final p in page.items)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: NetImage(p.coverUrl, width: 64, height: 48, radius: 8),
                title: Text(p.title),
                subtitle: Text('${formatDateOnly(p.travelledOn)} · ${p.mediaCount} photos/videos'),
                trailing: Wrap(spacing: 6, children: [
                  if (p.isFeatured) const Pill('Featured', tone: PillTone.accent),
                  Pill(p.isPublished ? 'Published' : 'Hidden', tone: p.isPublished ? PillTone.success : PillTone.neutral),
                ]),
                onTap: () => context.go('/admin/past-trips/${p.id}'),
              ),
            ),
        ]),
      ),
    );
  }
}

class AdminPastTripEditorScreen extends ConsumerWidget {
  const AdminPastTripEditorScreen({super.key, this.id});
  final String? id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (id == null) return const _PastTripForm(trip: null);
    final trip = ref.watch(adminPastTripProvider(id!));
    return AsyncView(value: trip, onRetry: () => ref.invalidate(adminPastTripProvider(id!)), data: (t) => _PastTripForm(key: ValueKey(t.id), trip: t));
  }
}

class _Upload {
  _Upload(this.name);
  final String name;
  double progress = 0;
  String? error;
  bool done = false;
}

class _PastTripForm extends ConsumerStatefulWidget {
  const _PastTripForm({super.key, required this.trip});
  final PastTripDetail? trip;

  @override
  ConsumerState<_PastTripForm> createState() => _PastTripFormState();
}

class _PastTripFormState extends ConsumerState<_PastTripForm> {
  static const _maxVideoBytes = 50 * 1024 * 1024;

  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.trip?.title);
  late final _destination = TextEditingController(text: widget.trip?.destination);
  late final _count = TextEditingController(text: widget.trip?.travellerCount?.toString());
  late final _story = TextEditingController(text: widget.trip?.story);
  late DateTime _travelledOn = widget.trip == null ? DateTime.now() : DateTime.parse(widget.trip!.travelledOn);
  late String? _tripId = widget.trip?.tripId;
  late bool _featured = widget.trip?.isFeatured ?? false;
  late bool _published = widget.trip?.isPublished ?? false;
  late List<PastTripMedia> _media = [...?widget.trip?.media];
  final List<_Upload> _uploads = [];
  bool _saving = false;
  ApiException? _error;

  @override
  void dispose() {
    for (final c in [_title, _destination, _count, _story]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {
      'tripId': _tripId,
      'title': _title.text.trim(),
      'destination': _destination.text.trim(),
      'travelledOn': toIsoDate(_travelledOn),
      'travellerCount': int.tryParse(_count.text),
      'story': _story.text.trim(),
      'isFeatured': _featured,
      'isPublished': _published,
      'sortOrder': widget.trip?.sortOrder ?? 0,
    };
    try {
      final api = ref.read(apiProvider);
      final saved = widget.trip == null
          ? await api.post('/api/admin/past-trips', (d) => PastTripDetail.fromJson(asJson(d)), body: body)
          : await api.put('/api/admin/past-trips/${widget.trip!.id}', (d) => PastTripDetail.fromJson(asJson(d)), body: body);
      ref.invalidate(adminPastTripsProvider);
      if (!mounted) return;
      showSnack(context, 'Album saved.');
      if (widget.trip == null) context.go('/admin/past-trips/${saved.id}');
    } catch (e) {
      setState(() => _error = ApiException.from(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Drag-and-drop style multi-upload: one request per file, each with its own progress bar.
  Future<void> _pickAndUpload() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.media, allowMultiple: true, withData: true);
    if (picked == null || !mounted) return;
    final api = ref.read(apiProvider);
    for (final f in picked.files) {
      final upload = _Upload(f.name);
      setState(() => _uploads.add(upload));
      final type = _contentType(f.extension);
      if (f.bytes == null) {
        setState(() => upload.error = 'Could not read the file');
        continue;
      }
      if (type.startsWith('video/') && f.size > _maxVideoBytes) {
        setState(() => upload.error = 'Video is over 50 MB – please trim or compress it');
        continue;
      }
      try {
        final media = await api.upload(
          '/api/admin/past-trips/${widget.trip!.id}/media',
          (d) => PastTripMedia.fromJson(asJson(d)),
          bytes: f.bytes!,
          filename: f.name,
          contentType: type,
          onProgress: (p) => setState(() => upload.progress = p),
        );
        setState(() {
          upload.done = true;
          _media = [..._media, media];
        });
      } catch (e) {
        setState(() => upload.error = ApiException.from(e).message);
      }
    }
    ref.invalidate(adminPastTripsProvider);
  }

  Future<void> _saveOrder() async {
    await runAction(
      context,
      () => ref.read(apiProvider).put('/api/admin/past-trips/${widget.trip!.id}/media/order', (_) {},
          body: [for (var i = 0; i < _media.length; i++) {'id': _media[i].id, 'sortOrder': i, 'caption': _media[i].caption}]),
      success: 'Order saved.',
    );
  }

  Future<void> _deleteMedia(PastTripMedia m) async {
    final ok = await runAction(context, () => ref.read(apiProvider).delete('/api/admin/past-trips/${widget.trip!.id}/media/${m.id}'));
    if (ok) setState(() => _media = _media.where((x) => x.id != m.id).toList());
  }

  Future<void> _editTestimonial(Testimonial? t) async {
    final name = TextEditingController(text: t?.customerName);
    final quote = TextEditingController(text: t?.quote);
    var rating = t?.rating ?? 5;
    var published = t?.isPublished ?? false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(t == null ? 'Add testimonial' : 'Edit testimonial'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Customer name')),
              const SizedBox(height: 12),
              TextField(controller: quote, maxLines: 4, decoration: const InputDecoration(labelText: 'What they said')),
              Row(children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(onPressed: () => set(() => rating = i), icon: Icon(i <= rating ? Icons.star : Icons.star_border, color: AppColors.coral)),
              ]),
              SwitchListTile(
                value: published,
                onChanged: (v) => set(() => published = v),
                title: const Text('Published'),
                subtitle: const Text('Only publish real words from real customers, with their permission.'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final body = {'customerName': name.text.trim(), 'quote': quote.text.trim(), 'rating': rating, 'isPublished': published};
    final api = ref.read(apiProvider);
    final base = '/api/admin/past-trips/${widget.trip!.id}/testimonials';
    final done = await runAction(context, () => t == null ? api.post(base, (_) {}, body: body) : api.put('$base/${t.id}', (_) {}, body: body));
    if (done) ref.invalidate(adminPastTripProvider(widget.trip!.id));
  }

  Future<void> _deleteTestimonial(Testimonial t) async {
    final done = await runAction(context, () => ref.read(apiProvider).delete('/api/admin/past-trips/${widget.trip!.id}/testimonials/${t.id}'));
    if (done) ref.invalidate(adminPastTripProvider(widget.trip!.id));
  }

  @override
  Widget build(BuildContext context) {
    final trips = ref.watch(adminTripsProvider).valueOrNull?.items ?? const [];
    final trip = widget.trip;
    return Form(
      key: _form,
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          IconButton(onPressed: () => context.go('/admin/past-trips'), icon: const Icon(Icons.arrow_back)),
          Expanded(child: Text(trip == null ? 'New album' : trip.title, style: Theme.of(context).textTheme.headlineSmall)),
          FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save), label: Text(_saving ? 'Saving…' : 'Save')),
        ]),
        if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(error: _error!)],
        SwitchListTile(value: _published, onChanged: (v) => setState(() => _published = v), title: const Text('Published')),
        SwitchListTile(value: _featured, onChanged: (v) => setState(() => _featured = v), title: const Text('Featured (shown first)')),
        TextFormField(controller: _title, decoration: const InputDecoration(labelText: 'Title, e.g. "Cape Town – April 2025"'), validator: _required),
        const SizedBox(height: 12),
        TextFormField(controller: _destination, decoration: const InputDecoration(labelText: 'Destination'), validator: _required),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date travelled'),
              subtitle: Text(formatDateOnly(toIsoDate(_travelledOn))),
              trailing: const Icon(Icons.edit_calendar),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _travelledOn, firstDate: DateTime(2015), lastDate: DateTime.now());
                if (d != null) setState(() => _travelledOn = d);
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(controller: _count, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Number of travellers'))),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          value: trips.any((t) => t.id == _tripId) ? _tripId : null,
          decoration: const InputDecoration(labelText: 'Link to a trip (optional)', helperText: 'Customers see "We\'ve done this trip before" and can book it'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Not linked')),
            for (final t in trips) DropdownMenuItem<String?>(value: t.id, child: Text(t.title)),
          ],
          onChanged: (v) => setState(() => _tripId = v),
        ),
        const SizedBox(height: 12),
        TextFormField(controller: _story, maxLines: 5, decoration: const InputDecoration(labelText: 'Story / highlights')),

        if (trip != null) ...[
          SectionTitle('Photos and videos',
              trailing: Wrap(spacing: 8, children: [
                OutlinedButton(onPressed: _saveOrder, child: const Text('Save order')),
                FilledButton.icon(onPressed: _pickAndUpload, icon: const Icon(Icons.upload), label: const Text('Upload')),
              ])),
          const Text('Photos are resized automatically. Videos up to 50 MB. Drag to reorder.', style: TextStyle(color: AppColors.secondaryText)),
          const SizedBox(height: 8),
          for (final u in _uploads.where((u) => !u.done || u.error != null))
            ListTile(
              dense: true,
              leading: Icon(u.error == null ? Icons.cloud_upload_outlined : Icons.error_outline, color: u.error == null ? AppColors.teal : AppColors.error),
              title: Text(u.name),
              subtitle: u.error != null ? Text(u.error!, style: const TextStyle(color: AppColors.error)) : LinearProgressIndicator(value: u.progress),
            ),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: true,
            onReorder: (from, to) => setState(() {
              final list = [..._media];
              final item = list.removeAt(from);
              list.insert(to > from ? to - 1 : to, item);
              _media = list;
            }),
            children: [
              for (final m in _media)
                ListTile(
                  key: ValueKey(m.id),
                  leading: Stack(alignment: Alignment.center, children: [
                    NetImage(m.thumbnailUrl ?? (m.isVideo ? null : m.url), width: 72, height: 54, radius: 6),
                    if (m.isVideo) const Icon(Icons.play_circle, color: AppColors.white),
                  ]),
                  title: TextFormField(
                    initialValue: m.caption,
                    decoration: const InputDecoration(hintText: 'Caption (optional)', isDense: true),
                    onChanged: (v) {
                      final i = _media.indexWhere((x) => x.id == m.id);
                      _media[i] = PastTripMedia.fromJson({
                        'id': m.id,
                        'mediaType': m.mediaType,
                        'url': m.url,
                        'thumbnailUrl': m.thumbnailUrl,
                        'caption': v,
                        'sortOrder': m.sortOrder,
                      });
                    },
                  ),
                  trailing: IconButton(onPressed: () => _deleteMedia(m), icon: const Icon(Icons.delete_outline, color: AppColors.error)),
                ),
            ],
          ),
          SectionTitle('Testimonials',
              trailing: TextButton.icon(onPressed: () => _editTestimonial(null), icon: const Icon(Icons.add), label: const Text('Add'))),
          for (final t in trip.testimonials)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text('"${t.quote}"'),
                subtitle: Text('– ${t.customerName}${t.rating == null ? '' : ' · ${'★' * t.rating!}'}'),
                leading: Pill(t.isPublished ? 'Published' : 'Hidden', tone: t.isPublished ? PillTone.success : PillTone.neutral),
                onTap: () => _editTestimonial(t),
                trailing: IconButton(onPressed: () => _deleteTestimonial(t), icon: const Icon(Icons.delete_outline)),
              ),
            ),
        ] else
          const Padding(padding: EdgeInsets.only(top: 24), child: Text('Save the album first, then upload photos and videos.')),
        const SizedBox(height: 48),
      ]),
    );
  }

  static String _contentType(String? ext) => switch ((ext ?? '').toLowerCase()) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'heic' => 'image/heic',
        'mp4' => 'video/mp4',
        'mov' => 'video/quicktime',
        'webm' => 'video/webm',
        _ => 'image/jpeg',
      };

  static String? _required(String? v) => (v ?? '').trim().isEmpty ? 'Required' : null;
}
