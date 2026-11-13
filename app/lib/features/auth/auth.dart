import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';

class Me {
  Me.fromJson(Json j)
      : id = j['id'] as String,
        fullName = (j['fullName'] ?? '') as String,
        phone = j['phone'] as String?,
        role = (j['role'] ?? 'customer') as String,
        email = j['email'] as String?;
  final String id, fullName, role;
  final String? phone, email;
  bool get isAdmin => role == 'admin';
}

final authStateProvider = StreamProvider<AuthState>((ref) => Supabase.instance.client.auth.onAuthStateChange);

final sessionProvider = Provider<Session?>((ref) {
  ref.watch(authStateProvider);
  return Supabase.instance.client.auth.currentSession;
});

final meProvider = FutureProvider<Me?>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return null;
  return ref.watch(apiProvider).get('/api/me', (d) => Me.fromJson(asJson(d)));
});

/// Lets go_router re-check redirects when the user signs in or out.
class AuthRefresh extends ChangeNotifier {
  AuthRefresh() {
    Supabase.instance.client.auth.onAuthStateChange.listen((_) => notifyListeners());
  }
}

String authMessage(Object e) {
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) return 'That email and password don\'t match. Please try again.';
    if (m.contains('email not confirmed')) return 'Please confirm your email first – check your inbox for our link.';
    if (m.contains('already registered')) return 'An account with this email already exists. Try signing in.';
    return e.message;
  }
  return ApiException.from(e).message;
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.from});
  final String? from;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
      if (mounted) context.go(widget.from ?? '/');
    } catch (e) {
      setState(() => _error = authMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Type your email address above first, then tap "Forgot password".');
      return;
    }
    await runAction(context, () => Supabase.instance.client.auth.resetPasswordForEmail(email),
        success: 'We\'ve emailed you a link to reset your password.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Constrained(
        maxWidth: 460,
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const _Brand(),
            const SizedBox(height: 24),
            if (_error != null) ...[ErrorBanner(error: ApiException(_error!)), const SizedBox(height: 16)],
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) => (v ?? '').contains('@') ? null : 'Enter your email address',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Password'),
              validator: (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
              onFieldSubmitted: (_) => _signIn(),
            ),
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _forgot, child: const Text('Forgot password?'))),
            const SizedBox(height: 8),
            FilledButton(onPressed: _busy ? null : _signIn, child: Text(_busy ? 'Signing in…' : 'Sign in')),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.go('/register${widget.from == null ? '' : '?from=${Uri.encodeComponent(widget.from!)}'}'),
              child: const Text('Create an account'),
            ),
          ]),
        ),
      ),
    );
  }
}

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.from});
  final String? from;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
        data: {'full_name': _name.text.trim(), 'phone': _phone.text.trim()},
      );
      if (!mounted) return;
      if (res.session == null) {
        showSnack(context, 'Almost done! Check your email and tap the link to confirm your account.');
        context.go('/login');
      } else {
        context.go(widget.from ?? '/');
      }
    } catch (e) {
      setState(() => _error = authMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create an account')),
      body: Constrained(
        maxWidth: 460,
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const _Brand(),
            const SizedBox(height: 24),
            if (_error != null) ...[ErrorBanner(error: ApiException(_error!)), const SizedBox(height: 16)],
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your full name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: const InputDecoration(labelText: 'Cellphone number', hintText: 'e.g. 076 123 4567'),
              validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length < 9 ? 'Enter your cellphone number' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) => (v ?? '').contains('@') ? null : 'Enter your email address',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'Password', helperText: 'At least 8 characters'),
              validator: (v) => (v ?? '').length < 8 ? 'Use at least 8 characters' : null,
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _busy ? null : _register, child: Text(_busy ? 'Creating account…' : 'Create account')),
            TextButton(onPressed: () => context.go('/login'), child: const Text('I already have an account')),
          ]),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => Column(children: [
        const Icon(Icons.travel_explore, size: 56, color: AppColors.teal),
        const SizedBox(height: 8),
        Text('Owen Tours and Travel', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const Text('Explore the World', style: TextStyle(color: AppColors.secondaryText)),
      ]);
}
