import 'package:flutter/material.dart';

const appName = 'ERP Mobile';

/// Odoo's brand purple, so the app feels at home next to the web client.
const brandColor = Color(0xFF714B67);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: brandColor, brightness: brightness);
  final dark = brightness == Brightness.dark;
  final background = dark ? scheme.surface : const Color(0xFFF5F4F7);
  final radius = BorderRadius.circular(12);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final text = base.textTheme;
  final buttonText = text.labelLarge!.copyWith(fontSize: 15, fontWeight: FontWeight.w600);

  return base.copyWith(
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleLarge!.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? scheme.surfaceContainer : Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? scheme.surfaceContainerHighest : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.outlineVariant)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.outlineVariant)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.primary, width: 1.6)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 46),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 46),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: buttonText,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5), space: 1),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
  );
}

const _palette = [
  Color(0xFF714B67),
  Color(0xFF017E84),
  Color(0xFFE46F3A),
  Color(0xFF3F6AD8),
  Color(0xFF2E9D5B),
  Color(0xFFC0397B),
  Color(0xFF8E6BD6),
  Color(0xFFD99A1E),
];

/// A stable colour per name, so the same record or app always gets the same
/// avatar colour.
Color colorFor(String text) {
  var hash = 0;
  for (final unit in text.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _palette[hash % _palette.length];
}

/// Background/foreground for a status badge, guessed from Odoo's usual state
/// keys (draft, done, cancel, ...) so badges read the same in every module.
(Color, Color) statusColors(dynamic key, ColorScheme scheme) {
  final k = key is String ? key.toLowerCase() : '';
  const green = Color(0xFF2E9D5B);
  const red = Color(0xFFD14343);
  const amber = Color(0xFFC77C0E);
  if (const {'done', 'won', 'paid', 'posted', 'sale', 'confirmed', 'approved', 'validate', 'validated', 'active', 'open', 'in_payment'}
      .contains(k)) {
    return (green.withValues(alpha: 0.14), green);
  }
  if (const {'cancel', 'cancelled', 'lost', 'refused', 'rejected', 'blocked', 'expired'}.contains(k)) {
    return (red.withValues(alpha: 0.12), red);
  }
  if (const {'waiting', 'pending', 'to_approve', 'confirm', 'sent', 'qualified', 'assigned', 'partial'}.contains(k)) {
    return (amber.withValues(alpha: 0.14), amber);
  }
  return (scheme.secondaryContainer, scheme.onSecondaryContainer);
}
