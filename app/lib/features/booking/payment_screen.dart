import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';

enum PaymentOutcome { returned, cancelled, unknown }

/// Opens the PayFast checkout. On phones it's an in-app WebView that closes itself when PayFast
/// sends the customer back; on the web it opens a new browser tab.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.checkoutUrl, required this.amountLabel});
  final String checkoutUrl;
  final String amountLabel;

  /// Returns what happened. The booking itself is only updated by PayFast's server notification,
  /// so the caller should refresh the booking afterwards.
  static Future<PaymentOutcome> open(BuildContext context, {required String checkoutUrl, required String amountLabel}) async {
    if (kIsWeb) {
      await launchUrl(Uri.parse(checkoutUrl), webOnlyWindowName: '_blank');
      if (!context.mounted) return PaymentOutcome.unknown;
      final done = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: const Text('Complete your payment'),
          content: const Text('The secure PayFast page opened in a new tab. Come back here once you\'ve paid.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('I cancelled')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text("I've paid")),
          ],
        ),
      );
      return done == true ? PaymentOutcome.returned : PaymentOutcome.cancelled;
    }
    final result = await Navigator.of(context).push<PaymentOutcome>(
      MaterialPageRoute(builder: (_) => PaymentScreen(checkoutUrl: checkoutUrl, amountLabel: amountLabel), fullscreenDialog: true),
    );
    return result ?? PaymentOutcome.cancelled;
  }

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late final WebViewController _controller;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _progress = p),
        onNavigationRequest: (req) {
          final path = Uri.tryParse(req.url)?.path ?? '';
          if (path.endsWith(AppConfig.paymentReturnPath)) {
            Navigator.of(context).pop(PaymentOutcome.returned);
            return NavigationDecision.prevent;
          }
          if (path.endsWith(AppConfig.paymentCancelPath)) {
            Navigator.of(context).pop(PaymentOutcome.cancelled);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Pay ${widget.amountLabel}'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context, PaymentOutcome.cancelled)),
      ),
      body: Column(children: [
        if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
        Container(
          width: double.infinity,
          color: AppColors.warmSand,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: const Row(children: [
            Icon(Icons.lock_outline, size: 16, color: AppColors.deepBlue),
            SizedBox(width: 6),
            Expanded(child: Text('Secure payment by PayFast. Owen Tours never sees your card details.', style: TextStyle(fontSize: 12))),
          ]),
        ),
        Expanded(child: WebViewWidget(controller: _controller)),
      ]),
    );
  }
}

/// After returning from PayFast, waits for the payment notification to update the booking.
class PaymentPendingDialog extends StatelessWidget {
  const PaymentPendingDialog({super.key});

  @override
  Widget build(BuildContext context) => const AlertDialog(
        content: LoadingView(message: 'Confirming your payment…'),
      );
}
