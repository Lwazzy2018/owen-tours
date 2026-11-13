import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../theme/app_theme.dart';

/// Shows loading, error (with retry) and data states for any AsyncValue.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.data, this.onRetry, this.loading});

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final Widget? loading;

  @override
  Widget build(BuildContext context) => value.when(
        data: data,
        loading: () => loading ?? const LoadingView(),
        error: (e, _) => ErrorView(message: ApiException.from(e).message, onRetry: onRetry),
      );
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            if (message != null) ...[const SizedBox(height: 16), Text(message!, textAlign: TextAlign.center)],
          ]),
        ),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 48, color: AppColors.secondaryText),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
            ],
          ]),
        ),
      );
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: AppColors.teal),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.secondaryText)),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

/// A list of problems from the API, shown above a form.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.error});
  final ApiException error;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFDECEC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.error),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final m in error.allMessages)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.error_outline, size: 18, color: AppColors.error),
                const SizedBox(width: 8),
                Expanded(child: Text(m, style: const TextStyle(color: AppColors.deepBlue))),
              ]),
            ),
        ]),
      );
}

class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover, this.height, this.width, this.radius = 0});
  final String? url;
  final BoxFit fit;
  final double? height, width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      height: height,
      width: width,
      color: AppColors.warmSand,
      alignment: Alignment.center,
      child: const Icon(Icons.landscape_outlined, color: AppColors.teal, size: 36),
    );
    final image = url == null || url!.isEmpty
        ? placeholder
        : CachedNetworkImage(
            imageUrl: url!,
            fit: fit,
            height: height,
            width: width,
            placeholder: (_, __) => placeholder,
            errorWidget: (_, __, ___) => placeholder,
          );
    return radius == 0 ? image : ClipRRect(borderRadius: BorderRadius.circular(radius), child: image);
  }
}

/// Small rounded label, e.g. "Free cancellation", "Paid", "Transport".
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.icon, this.tone = PillTone.neutral});
  final String label;
  final IconData? icon;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      PillTone.success => (AppColors.greenTint, AppColors.deepBlue),
      PillTone.accent => (AppColors.coral, AppColors.deepBlue),
      PillTone.info => (AppColors.tealTint, AppColors.deepBlue),
      PillTone.warning => (const Color(0xFFFFF4D6), AppColors.deepBlue),
      PillTone.danger => (const Color(0xFFFDECEC), AppColors.error),
      PillTone.sand => (AppColors.warmSand, AppColors.deepBlue),
      PillTone.neutral => (const Color(0xFFF1F4F5), AppColors.deepBlue),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
        Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

enum PillTone { neutral, success, accent, info, warning, danger, sand }

PillTone toneForStatus(String status) => switch (status) {
      'paid' => PillTone.success,
      'confirmed' => PillTone.success,
      'pending' => PillTone.warning,
      'cancelled' || 'expired' => PillTone.danger,
      'overdue' => PillTone.danger,
      'due' => PillTone.info,
      _ => PillTone.neutral,
    };

String statusLabel(String status) => switch (status) {
      'pending' => 'Awaiting payment',
      'confirmed' => 'Confirmed',
      'paid' => 'Paid',
      'cancelled' => 'Cancelled',
      'expired' => 'Expired',
      'due' => 'Due',
      'overdue' => 'Overdue',
      'pending_verification' => 'Waiting for review',
      'applied' => 'Applied',
      'rejected' => 'Not approved',
      _ => status,
    };

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Highlighted info box on Warm Sand (Deep Blue text).
class SandBox extends StatelessWidget {
  const SandBox({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(color: AppColors.warmSand, borderRadius: BorderRadius.circular(16)),
        child: DefaultTextStyle.merge(style: const TextStyle(color: AppColors.deepBlue), child: child),
      );
}

class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key, this.bold = false, this.valueColor});
  final String label, value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: valueColor);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400))),
        Text(value, style: style),
      ]),
    );
  }
}

/// Max-width wrapper so screens look good on tablets and the web admin.
class Constrained extends StatelessWidget {
  const Constrained({super.key, required this.child, this.maxWidth = 820});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) =>
      Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child));
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? AppColors.error : AppColors.green,
  ));
}

/// Shared helper: run an API action, show success/failure, return true on success.
Future<bool> runAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (context.mounted && success != null) showSnack(context, success);
    return true;
  } catch (e) {
    if (context.mounted) showSnack(context, ApiException.from(e).allMessages.join('\n'), error: true);
    return false;
  }
}
