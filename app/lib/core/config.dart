/// Settings passed at build/run time, e.g.
/// flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=... --dart-define=API_BASE_URL=http://10.0.2.2:5080
///
/// Only the PUBLIC anon key belongs in the app. Never the service role key.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:5080');

  /// The payment pages the API redirects to after PayFast. The app closes the payment screen on these.
  static String get paymentReturnPath => '/api/payments/return';
  static String get paymentCancelPath => '/api/payments/cancel';

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
