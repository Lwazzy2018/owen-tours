import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../auth/auth.dart';
import 'data.dart';

Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).valueOrNull;
    final signedIn = ref.watch(sessionProvider) != null;
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: Constrained(
        child: ListView(children: [
          if (signedIn && me != null)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.warmSand,
                child: Text(me.fullName.isEmpty ? '?' : me.fullName[0], style: const TextStyle(color: AppColors.deepBlue)),
              ),
              title: Text(me.fullName.isEmpty ? 'My account' : me.fullName),
              subtitle: Text(me.email ?? ''),
            )
          else
            ListTile(
              leading: const Icon(Icons.login),
              title: const Text('Sign in or create an account'),
              onTap: () => context.push('/login'),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.map_outlined, color: AppColors.teal),
            title: const Text('Plan a trip with us'),
            subtitle: const Text('Flights, accommodation, visas, travel insurance – free consultation'),
            onTap: () => context.push('/plan-trip'),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline, color: AppColors.teal),
            title: const Text('About us and contact'),
            onTap: () => context.push('/about'),
          ),
          if (me?.isAdmin == true)
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined, color: AppColors.coral),
              title: const Text('Admin panel'),
              onTap: () => context.go('/admin'),
            ),
          if (signedIn)
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () async {
                await Supabase.instance.client.auth.signOut();
                if (context.mounted) context.go('/');
              },
            ),
        ]),
      ),
    );
  }
}

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(companyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('About us')),
      body: AsyncView(
        value: company,
        onRetry: () => ref.invalidate(companyProvider),
        data: (c) => Constrained(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            SandBox(
              child: Column(children: [
                const Icon(Icons.travel_explore, size: 56, color: AppColors.teal),
                const SizedBox(height: 8),
                Text(c.companyName, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                if (c.tagline != null) Text(c.tagline!, style: const TextStyle(color: AppColors.teal, fontWeight: FontWeight.w600)),
                if (c.registeredName != null) Text(c.registeredName!, style: const TextStyle(color: AppColors.secondaryText)),
              ]),
            ),
            if (c.aboutText != null) ...[const SizedBox(height: 16), Text(c.aboutText!, style: const TextStyle(height: 1.5))],
            const SectionTitle('Get in touch'),
            if (c.whatsappLink != null)
              CtaButton(label: 'Chat on WhatsApp', icon: Icons.chat_outlined, onPressed: () => _open(c.whatsappLink!)),
            const SizedBox(height: 8),
            if (c.phone != null)
              ListTile(leading: const Icon(Icons.call_outlined), title: Text(c.phone!), onTap: () => _open('tel:${c.phone}')),
            if (c.email != null)
              ListTile(leading: const Icon(Icons.email_outlined), title: Text(c.email!), onTap: () => _open('mailto:${c.email}')),
            if (c.address != null) ListTile(leading: const Icon(Icons.place_outlined), title: Text(c.address!)),
            const SectionTitle('Follow us'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (c.instagramUrl != null)
                OutlinedButton.icon(onPressed: () => _open(c.instagramUrl!), icon: const Icon(Icons.camera_alt_outlined), label: const Text('Instagram')),
              if (c.facebookUrl != null)
                OutlinedButton.icon(onPressed: () => _open(c.facebookUrl!), icon: const Icon(Icons.facebook), label: const Text('Facebook')),
              if (c.tiktokUrl != null)
                OutlinedButton.icon(onPressed: () => _open(c.tiktokUrl!), icon: const Icon(Icons.music_note_outlined), label: const Text('TikTok')),
            ]),
          ]),
        ),
      ),
    );
  }
}

class EnquiryScreen extends ConsumerStatefulWidget {
  const EnquiryScreen({super.key});

  @override
  ConsumerState<EnquiryScreen> createState() => _EnquiryScreenState();
}

class _EnquiryScreenState extends ConsumerState<EnquiryScreen> {
  static const _services = {
    'tour_package': 'Tour package',
    'flights': 'Flights',
    'accommodation': 'Accommodation',
    'visa': 'Visa assistance',
    'travel_insurance': 'Travel insurance',
    'consultation': 'Free consultation',
  };

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _destination = TextEditingController();
  final _people = TextEditingController(text: '1');
  final _budget = TextEditingController();
  final _message = TextEditingController();
  final Set<String> _selected = {'consultation'};
  DateTimeRange? _dates;
  bool _sending = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    final me = ref.read(meProvider).valueOrNull;
    if (me != null) {
      _name.text = me.fullName;
      _phone.text = me.phone ?? '';
      _email.text = me.email ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _destination, _people, _budget, _message]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      String? date(DateTime? d) => d == null ? null : d.toIso8601String().substring(0, 10);
      final budgetRands = int.tryParse(_budget.text.replaceAll(RegExp(r'\D'), ''));
      await ref.read(apiProvider).post('/api/enquiries', (_) {}, body: {
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'services': _selected.toList(),
        'destination': _destination.text.trim(),
        'travelFrom': date(_dates?.start),
        'travelTo': date(_dates?.end),
        'people': int.tryParse(_people.text),
        'budgetCents': budgetRands == null ? null : budgetRands * 100,
        'message': _message.text.trim(),
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Thank you!'),
          content: const Text("We've received your request and will contact you soon, usually on WhatsApp."),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
        ),
      );
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = ApiException.from(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plan a trip with us')),
      body: Form(
        key: _form,
        child: Constrained(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const SandBox(child: Text("Tell us what you'd like and we'll plan it with you. Consultations are free.")),
            const SizedBox(height: 16),
            if (_error != null) ...[ErrorBanner(error: _error!), const SizedBox(height: 12)],
            const Text('What do you need?', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in _services.entries)
                FilterChip(
                  label: Text(e.value),
                  selected: _selected.contains(e.key),
                  onSelected: (v) => setState(() => v ? _selected.add(e.key) : _selected.remove(e.key)),
                ),
            ]),
            const SizedBox(height: 16),
            TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Your name'), validator: _required),
            const SizedBox(height: 12),
            TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Cellphone / WhatsApp'),
                validator: _required),
            const SizedBox(height: 12),
            TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email (optional)')),
            const SizedBox(height: 12),
            TextFormField(controller: _destination, decoration: const InputDecoration(labelText: 'Where would you like to go?')),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range),
              label: Text(_dates == null
                  ? 'Travel dates (optional)'
                  : '${MaterialLocalizations.of(context).formatShortDate(_dates!.start)} – ${MaterialLocalizations.of(context).formatShortDate(_dates!.end)}'),
              onPressed: () async {
                final now = DateTime.now();
                final picked = await showDateRangePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 730)));
                if (picked != null) setState(() => _dates = picked);
              },
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(controller: _people, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'People')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                    controller: _budget, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Budget (R, optional)')),
              ),
            ]),
            const SizedBox(height: 12),
            TextFormField(controller: _message, maxLines: 4, decoration: const InputDecoration(labelText: 'Anything else we should know?')),
            const SizedBox(height: 20),
            FilledButton(onPressed: _sending ? null : _send, child: Text(_sending ? 'Sending…' : 'Send request')),
            const SizedBox(height: 32),
          ]),
        ),
      ),
    );
  }

  static String? _required(String? v) => (v ?? '').trim().isEmpty ? 'Required' : null;
}
