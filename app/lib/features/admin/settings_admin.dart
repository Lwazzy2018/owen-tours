import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../company/data.dart';
import '../trips/models.dart';
import 'trips_admin.dart';

// ============================ Specials ============================

final adminSpecialsProvider = FutureProvider.autoDispose<List<Special>>((ref) {
  return ref.watch(apiProvider).get('/api/admin/specials', (d) => asList(d, Special.fromJson));
});

class AdminSpecialsScreen extends ConsumerWidget {
  const AdminSpecialsScreen({super.key});

  static const _typeLabels = {
    'percentage': '% off selected trips',
    'student': 'Student discount (ID checked)',
    'group': 'Group discount',
    'promo_code': 'Promo code',
  };

  Future<void> _edit(BuildContext context, WidgetRef ref, Special? s) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _SpecialDialog(special: s));
    if (saved == true) ref.invalidate(adminSpecialsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final specials = ref.watch(adminSpecialsProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('New special'),
      ),
      body: AsyncView(
        value: specials,
        onRetry: () => ref.invalidate(adminSpecialsProvider),
        data: (list) => ListView(padding: const EdgeInsets.all(20), children: [
          Text('Specials and discounts', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const Text('Only one discount applies per booking – the one that saves the customer the most.'),
          const SizedBox(height: 12),
          for (final s in list)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text('${s.name} · ${s.percentOff}% off'),
                subtitle: Text([
                  _typeLabels[s.type] ?? s.type,
                  if (s.minTravellers != null) '${s.minTravellers}+ travellers',
                  if (s.promoCode != null) 'Code ${s.promoCode} (${s.timesUsed}${s.maxUses == null ? '' : '/${s.maxUses}'} used)',
                  '${formatDate(s.startsAt)} – ${formatDate(s.endsAt)}',
                  '${s.tripIds.length} trips',
                ].join(' · ')),
                trailing: Wrap(spacing: 4, children: [
                  Pill(s.isActive ? 'Active' : 'Off', tone: s.isActive ? PillTone.success : PillTone.neutral),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete (or switch off if already used)',
                    onPressed: () async {
                      final ok = await runAction(context, () => ref.read(apiProvider).delete('/api/admin/specials/${s.id}'));
                      if (ok) ref.invalidate(adminSpecialsProvider);
                    },
                  ),
                ]),
                onTap: () => _edit(context, ref, s),
              ),
            ),
          if (list.isEmpty) const EmptyView(icon: Icons.local_offer_outlined, title: 'No specials yet'),
        ]),
      ),
    );
  }
}

class _SpecialDialog extends ConsumerStatefulWidget {
  const _SpecialDialog({required this.special});
  final Special? special;

  @override
  ConsumerState<_SpecialDialog> createState() => _SpecialDialogState();
}

class _SpecialDialogState extends ConsumerState<_SpecialDialog> {
  Special? get s => widget.special;
  late final _name = TextEditingController(text: s?.name);
  late final _description = TextEditingController(text: s?.description);
  late final _percent = TextEditingController(text: '${s?.percentOff ?? 10}');
  late final _minTravellers = TextEditingController(text: '${s?.minTravellers ?? 5}');
  late final _code = TextEditingController(text: s?.promoCode);
  late final _maxUses = TextEditingController(text: s?.maxUses?.toString());
  late String _type = s?.type ?? 'percentage';
  late bool _active = s?.isActive ?? true;
  late bool _public = s?.isPublic ?? true;
  late DateTimeRange _dates = DateTimeRange(
    start: s == null ? DateTime.now() : toSast(s!.startsAt),
    end: s == null ? DateTime.now().add(const Duration(days: 30)) : toSast(s!.endsAt),
  );
  late final Set<String> _tripIds = {...?s?.tripIds};
  ApiException? _error;
  bool _saving = false;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    String utc(DateTime d, {bool end = false}) =>
        DateTime.utc(d.year, d.month, d.day, end ? 23 : 0, end ? 59 : 0).subtract(const Duration(hours: 2)).toIso8601String();
    final body = {
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'type': _type,
      'percentOff': int.tryParse(_percent.text) ?? 0,
      'minTravellers': _type == 'group' ? int.tryParse(_minTravellers.text) : null,
      'promoCode': _type == 'promo_code' ? _code.text.trim() : null,
      'isPublic': _public,
      'maxUses': int.tryParse(_maxUses.text),
      'startsAt': utc(_dates.start),
      'endsAt': utc(_dates.end, end: true),
      'isActive': _active,
      'tripIds': _tripIds.toList(),
    };
    try {
      final api = ref.read(apiProvider);
      if (s == null) {
        await api.post('/api/admin/specials', (_) {}, body: body);
      } else {
        await api.put('/api/admin/specials/${s!.id}', (_) {}, body: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = ApiException.from(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trips = ref.watch(adminTripsProvider).valueOrNull?.items ?? const <TripSummary>[];
    return AlertDialog(
      title: Text(s == null ? 'New special' : 'Edit special'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_error != null) ...[ErrorBanner(error: _error!), const SizedBox(height: 12)],
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name, e.g. "Youth Month Special"')),
            const SizedBox(height: 12),
            TextField(controller: _description, decoration: const InputDecoration(labelText: 'Description (shown to customers)')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [for (final e in AdminSpecialsScreen._typeLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 12),
            TextField(controller: _percent, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Percent off', suffixText: '%')),
            if (_type == 'group') ...[
              const SizedBox(height: 12),
              TextField(controller: _minTravellers, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minimum travellers')),
            ],
            if (_type == 'promo_code') ...[
              const SizedBox(height: 12),
              TextField(controller: _code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Code')),
              const SizedBox(height: 12),
              TextField(controller: _maxUses, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Maximum uses (optional)')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _public,
                onChanged: (v) => setState(() => _public = v),
                title: const Text('Show this special publicly'),
                subtitle: const Text('The code itself is never shown – customers must type it.'),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range),
              label: Text('${formatDateOnly(toIsoDate(_dates.start))} – ${formatDateOnly(toIsoDate(_dates.end))}'),
              onPressed: () async {
                final picked = await showDateRangePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime(2035), initialDateRange: _dates);
                if (picked != null) setState(() => _dates = picked);
              },
            ),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v), title: const Text('Active')),
            const Text('Applies to these trips', style: TextStyle(fontWeight: FontWeight.w600)),
            for (final t in trips)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _tripIds.contains(t.id),
                onChanged: (v) => setState(() => v == true ? _tripIds.add(t.id) : _tripIds.remove(t.id)),
                title: Text(t.title),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
      ],
    );
  }
}

// ============================ Student IDs ============================

class PendingDiscount {
  PendingDiscount.fromJson(Json j)
      : id = j['id'] as String,
        bookingId = j['bookingId'] as String,
        bookingReference = j['bookingReference'] as String,
        customerName = j['customerName'] as String,
        specialName = j['specialName'] as String,
        percentOff = asInt(j['percentOff']),
        discountCents = asInt(j['discountCents']),
        studentIdUrl = j['studentIdUrl'] as String?;
  final String id, bookingId, bookingReference, customerName, specialName;
  final int percentOff, discountCents;
  final String? studentIdUrl;
}

final pendingDiscountsProvider = FutureProvider.autoDispose<List<PendingDiscount>>((ref) {
  return ref.watch(apiProvider).get('/api/admin/discounts/pending', (d) => asList(d, PendingDiscount.fromJson));
});

class AdminStudentIdsScreen extends ConsumerWidget {
  const AdminStudentIdsScreen({super.key});

  Future<void> _review(BuildContext context, WidgetRef ref, PendingDiscount p, bool approve) async {
    final note = TextEditingController();
    if (!approve) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Reject student ID'),
          content: TextField(controller: note, decoration: const InputDecoration(labelText: 'Reason (sent to the customer)')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Back')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Reject')),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!context.mounted) return;
    final done = await runAction(
      context,
      () => ref.read(apiProvider).put('/api/admin/discounts/${p.id}', (_) {}, body: {'approve': approve, 'note': note.text.trim()}),
      success: approve ? 'Discount approved and applied.' : 'Discount rejected.',
    );
    if (done) ref.invalidate(pendingDiscountsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(pendingDiscountsProvider);
    return AsyncView(
      value: list,
      onRetry: () => ref.invalidate(pendingDiscountsProvider),
      data: (items) => ListView(padding: const EdgeInsets.all(20), children: [
        Text('Student IDs to check', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const Text('Photos are private and links expire after 15 minutes.'),
        const SizedBox(height: 12),
        for (final p in items)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                p.studentIdUrl == null
                    ? Container(width: 180, height: 120, color: AppColors.warmSand, alignment: Alignment.center, child: const Text('Not uploaded yet'))
                    : InkWell(
                        onTap: () => launchUrl(Uri.parse(p.studentIdUrl!)),
                        child: NetImage(p.studentIdUrl, width: 180, height: 120, radius: 8, fit: BoxFit.contain),
                      ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${p.customerName} · ${p.bookingReference}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${p.specialName}: ${p.percentOff}% = ${rand(p.discountCents)} off'),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, children: [
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.green),
                        onPressed: p.studentIdUrl == null ? null : () => _review(context, ref, p, true),
                        child: const Text('Approve'),
                      ),
                      OutlinedButton(onPressed: () => _review(context, ref, p, false), child: const Text('Reject')),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        if (items.isEmpty) const EmptyView(icon: Icons.verified_outlined, title: 'All caught up', message: 'No student IDs waiting.'),
      ]),
    );
  }
}

// ============================ Enquiries ============================

class Enquiry {
  Enquiry.fromJson(Json j)
      : id = j['id'] as String,
        name = j['name'] as String,
        phone = j['phone'] as String,
        email = j['email'] as String?,
        services = asStrings(j['services']),
        destination = j['destination'] as String?,
        travelFrom = j['travelFrom'] as String?,
        travelTo = j['travelTo'] as String?,
        people = asIntOrNull(j['people']),
        budgetCents = asIntOrNull(j['budgetCents']),
        message = j['message'] as String?,
        status = j['status'] as String,
        staffNotes = j['staffNotes'] as String?,
        createdAt = DateTime.parse(j['createdAt'] as String),
        whatsappLink = j['whatsappLink'] as String;
  final String id, name, phone, status, whatsappLink;
  final String? email, destination, travelFrom, travelTo, message, staffNotes;
  final List<String> services;
  final int? people, budgetCents;
  final DateTime createdAt;
}

final enquiriesProvider = FutureProvider.autoDispose.family<Paged<Enquiry>, String?>((ref, status) {
  return ref.watch(apiProvider).get('/api/admin/enquiries', (d) => Paged.fromJson(d, Enquiry.fromJson), query: {'status': status, 'pageSize': 50});
});

class AdminEnquiriesScreen extends ConsumerStatefulWidget {
  const AdminEnquiriesScreen({super.key});

  @override
  ConsumerState<AdminEnquiriesScreen> createState() => _AdminEnquiriesScreenState();
}

class _AdminEnquiriesScreenState extends ConsumerState<AdminEnquiriesScreen> {
  String? _status = 'new';

  Future<void> _update(Enquiry e, String status, String? notes) async {
    final ok = await runAction(context,
        () => ref.read(apiProvider).put('/api/admin/enquiries/${e.id}', (_) {}, body: {'status': status, 'staffNotes': notes}),
        success: 'Updated.');
    if (ok) ref.invalidate(enquiriesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(enquiriesProvider(_status));
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Enquiries', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        for (final s in const [null, 'new', 'contacted', 'quoted', 'closed'])
          ChoiceChip(label: Text(s == null ? 'All' : titleCase(s)), selected: _status == s, onSelected: (_) => setState(() => _status = s)),
      ]),
      const SizedBox(height: 12),
      AsyncView(
        value: list,
        onRetry: () => ref.invalidate(enquiriesProvider(_status)),
        data: (page) => Column(children: [
          for (final e in page.items)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                title: Text('${e.name} · ${e.services.map(titleCase).join(', ')}'),
                subtitle: Text('${formatDateTime(e.createdAt)} · ${e.destination ?? 'Anywhere'} · ${titleCase(e.status)}'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Phone: ${e.phone}${e.email == null ? '' : ' · ${e.email}'}'),
                  if (e.travelFrom != null) Text('Dates: ${formatDateOnly(e.travelFrom!)}${e.travelTo == null ? '' : ' – ${formatDateOnly(e.travelTo!)}'}'),
                  if (e.people != null) Text('People: ${e.people}'),
                  if (e.budgetCents != null) Text('Budget: ${rand(e.budgetCents!)}'),
                  if (e.message != null && e.message!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(e.message!)),
                  const SizedBox(height: 12),
                  _EnquiryActions(enquiry: e, onUpdate: (status, notes) => _update(e, status, notes)),
                ],
              ),
            ),
          if (page.items.isEmpty) const EmptyView(icon: Icons.inbox_outlined, title: 'No enquiries here'),
        ]),
      ),
    ]);
  }
}

class _EnquiryActions extends StatefulWidget {
  const _EnquiryActions({required this.enquiry, required this.onUpdate});
  final Enquiry enquiry;
  final Future<void> Function(String status, String? notes) onUpdate;

  @override
  State<_EnquiryActions> createState() => _EnquiryActionsState();
}

class _EnquiryActionsState extends State<_EnquiryActions> {
  late final _notes = TextEditingController(text: widget.enquiry.staffNotes);
  late String _status = widget.enquiry.status;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Staff notes')),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          DropdownButton<String>(
            value: _status,
            items: [for (final s in const ['new', 'contacted', 'quoted', 'closed']) DropdownMenuItem(value: s, child: Text(titleCase(s)))],
            onChanged: (v) => setState(() => _status = v!),
          ),
          FilledButton(onPressed: () => widget.onUpdate(_status, _notes.text.trim()), child: const Text('Save')),
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse(widget.enquiry.whatsappLink), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.chat_outlined),
            label: const Text('WhatsApp'),
          ),
          if (widget.enquiry.email != null)
            OutlinedButton.icon(
              onPressed: () => launchUrl(Uri.parse('mailto:${widget.enquiry.email}?subject=${Uri.encodeComponent('Your trip enquiry – Owen Tours and Travel')}')),
              icon: const Icon(Icons.email_outlined),
              label: const Text('Email'),
            ),
        ]),
      ]);
}

// ============================ Company & staff ============================

class StaffMember {
  StaffMember.fromJson(Json j)
      : id = j['id'] as String,
        fullName = j['fullName'] as String,
        phone = j['phone'] as String?;
  final String id, fullName;
  final String? phone;
}

final staffProvider = FutureProvider.autoDispose<List<StaffMember>>((ref) {
  return ref.watch(apiProvider).get('/api/admin/staff', (d) => asList(d, StaffMember.fromJson));
});

class AdminSettingsScreen extends ConsumerWidget {
  const AdminSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(companyProvider);
    final staff = ref.watch(staffProvider);
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Company and staff', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SectionTitle('Contact details'),
      AsyncView(value: company, onRetry: () => ref.invalidate(companyProvider), data: (c) => _CompanyForm(company: c)),
      SectionTitle('Admins',
          trailing: FilledButton.icon(
            onPressed: () => _invite(context, ref),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Invite admin'),
          )),
      const Text('Only admins can add other admins. Nobody can sign up as an admin.'),
      const SizedBox(height: 8),
      AsyncView(
        value: staff,
        onRetry: () => ref.invalidate(staffProvider),
        data: (list) => Card(
          child: Column(children: [
            for (final s in list)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: Text(s.fullName),
                subtitle: s.phone == null ? null : Text(s.phone!),
                trailing: IconButton(
                  tooltip: 'Remove admin access',
                  icon: const Icon(Icons.person_remove_outlined),
                  onPressed: () async {
                    final ok = await runAction(context, () => ref.read(apiProvider).delete('/api/admin/staff/${s.id}'), success: 'Admin access removed.');
                    if (ok) ref.invalidate(staffProvider);
                  },
                ),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 48),
    ]);
  }

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    final email = TextEditingController();
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Invite an admin'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
          const SizedBox(height: 12),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
          const SizedBox(height: 8),
          const Text('They get an email to set their password.', style: TextStyle(color: AppColors.secondaryText)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Send invite')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final done = await runAction(context,
        () => ref.read(apiProvider).post('/api/admin/staff', (_) {}, body: {'email': email.text.trim(), 'fullName': name.text.trim()}),
        success: 'Invite sent.');
    if (done) ref.invalidate(staffProvider);
  }
}

class _CompanyForm extends ConsumerStatefulWidget {
  const _CompanyForm({required this.company});
  final Company company;

  @override
  ConsumerState<_CompanyForm> createState() => _CompanyFormState();
}

class _CompanyFormState extends ConsumerState<_CompanyForm> {
  late final Map<String, TextEditingController> _c = {
    for (final e in widget.company.toJson().entries) e.key: TextEditingController(text: e.value as String?),
  };
  static const _labels = {
    'companyName': 'Company name (shown in the app)',
    'registeredName': 'Registered name',
    'tagline': 'Tagline',
    'phone': 'Phone (e.g. +27762422251)',
    'whatsapp': 'WhatsApp number',
    'email': 'Email',
    'address': 'Office address',
    'facebookUrl': 'Facebook link',
    'instagramUrl': 'Instagram link',
    'tiktokUrl': 'TikTok link',
    'aboutText': 'About us text',
  };
  ApiException? _error;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    try {
      await ref.read(apiProvider).put('/api/admin/company', (_) {}, body: {
        for (final e in _c.entries) e.key: e.value.text.trim().isEmpty ? null : e.value.text.trim(),
      });
      ref.invalidate(companyProvider);
      if (mounted) showSnack(context, 'Company details saved.');
    } catch (e) {
      setState(() => _error = ApiException.from(e));
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            if (_error != null) ...[ErrorBanner(error: _error!), const SizedBox(height: 12)],
            for (final e in _labels.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(controller: _c[e.key], maxLines: e.key == 'aboutText' ? 4 : 1, decoration: InputDecoration(labelText: e.value)),
              ),
            Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: _save, child: const Text('Save details'))),
          ]),
        ),
      );
}
