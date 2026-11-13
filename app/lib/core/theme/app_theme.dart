import 'package:flutter/material.dart';

/// Owen Tours and Travel colour palette. Use these through the theme – never hard-code colours in widgets.
class AppColors {
  AppColors._();

  /// Primary brand colour: app bar, navigation, headings, main text.
  static const deepBlue = Color(0xFF063B4C);

  /// Secondary: primary buttons, links, active tabs, selected filters, icons, progress bars.
  static const teal = Color(0xFF007C91);

  /// Accent, used sparingly: "Book now", "Only X seats left", featured labels, promotions.
  /// Text on coral is always Deep Blue (white on coral is too low contrast).
  static const coral = Color(0xFFFF7657);

  /// Warm holiday feel: hero banners, previous trips section, testimonial cards, info boxes, splash.
  static const warmSand = Color(0xFFF7E7CE);

  /// Success and nature: Paid/Confirmed badges, success messages, completed instalments, hiking tags.
  /// White text on green only when bold and 14pt+.
  static const green = Color(0xFF4F8A6D);

  static const white = Color(0xFFFFFFFF);
  static const border = Color(0xFFE3EAED);
  static const secondaryText = Color(0xFF5B6B73);
  static const warning = Color(0xFFF9A825);
  static const error = Color(0xFFC62828);

  /// Light green tint for small text badges (with Deep Blue text).
  static const greenTint = Color(0xFFE3EFE8);
  static const coralTint = Color(0xFFFFE6DF);
  static const tealTint = Color(0xFFDDF1F4);
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.deepBlue,
      onPrimary: AppColors.white,
      secondary: AppColors.teal,
      onSecondary: AppColors.white,
      tertiary: AppColors.coral,
      onTertiary: AppColors.deepBlue,
      error: AppColors.error,
      onError: AppColors.white,
      surface: AppColors.white,
      onSurface: AppColors.deepBlue,
      surfaceContainerHighest: AppColors.warmSand,
      outline: AppColors.border,
      onSurfaceVariant: AppColors.secondaryText,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: AppColors.white);
    final text = base.textTheme.apply(bodyColor: AppColors.deepBlue, displayColor: AppColors.deepBlue);

    return base.copyWith(
      textTheme: text.copyWith(
        headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.deepBlue,
        foregroundColor: AppColors.white,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.white,
        indicatorColor: AppColors.tealTint,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.teal : AppColors.secondaryText),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
            color: s.contains(WidgetState.selected) ? AppColors.deepBlue : AppColors.secondaryText,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.teal,
          foregroundColor: AppColors.white,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.teal,
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: AppColors.teal),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: AppColors.teal)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.teal, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error)),
        labelStyle: const TextStyle(color: AppColors.secondaryText),
      ),
      cardTheme: CardThemeData(
        color: AppColors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.border)),
      ),
      chipTheme: base.chipTheme.copyWith(
        selectedColor: AppColors.tealTint,
        checkmarkColor: AppColors.teal,
        side: const BorderSide(color: AppColors.border),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.teal, linearTrackColor: AppColors.border),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
    );
  }
}

/// Coral call-to-action button ("Book now"). Deep Blue text for contrast.
class CtaButton extends StatelessWidget {
  const CtaButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: AppColors.coral,
      foregroundColor: AppColors.deepBlue,
      disabledBackgroundColor: AppColors.border,
    );
    return icon == null
        ? FilledButton(style: style, onPressed: onPressed, child: Text(label))
        : FilledButton.icon(style: style, onPressed: onPressed, icon: Icon(icon), label: Text(label));
  }
}
