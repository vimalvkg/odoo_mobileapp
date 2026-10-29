import 'package:flutter/material.dart';

const appName = 'ERP Mobile';

/// Used until the signed-in company's colour is known.
const defaultBrandColor = Color(0xFF0E7C86);

/// The connected company's colour (`res.company.primary_color`). The whole
/// app re-themes when it changes.
final brandColor = ValueNotifier<Color>(defaultBrandColor);

final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

/// [brandColor] for widgets that paint it directly; also subscribes them to
/// theme changes so they repaint when the brand changes.
Color brandOf(BuildContext context) {
  Theme.of(context);
  return brandColor.value;
}

/// Parses Odoo's `#RRGGBB` colour strings.
Color? parseHexColor(dynamic value) {
  if (value is! String) return null;
  final hex = value.trim().replaceFirst('#', '');
  if (hex.length != 6) return null;
  final rgb = int.tryParse(hex, radix: 16);
  return rgb == null ? null : Color(0xFF000000 | rgb);
}

/// The app's neutral palette (ground, cards, hairlines, text), light or dark.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color ground;
  final Color card;
  final Color border;
  final Color ink;
  final Color muted;

  /// Fill of search fields, segmented controls and image placeholders.
  final Color soft;

  const AppColors({
    required this.ground,
    required this.card,
    required this.border,
    required this.ink,
    required this.muted,
    required this.soft,
  });

  static const light = AppColors(
    ground: Color(0xFFF5F6F8),
    card: Colors.white,
    border: Color(0xFFE3E6EB),
    ink: Color(0xFF14161B),
    muted: Color(0xFF5B6270),
    soft: Color(0xFFEEF0F3),
  );

  static const dark = AppColors(
    ground: Color(0xFF111317),
    card: Color(0xFF1B1E24),
    border: Color(0xFF2C3038),
    ink: Color(0xFFF1F2F4),
    muted: Color(0xFFA3A9B5),
    soft: Color(0xFF252931),
  );

  static AppColors of(BuildContext context) => Theme.of(context).extension<AppColors>() ?? light;

  @override
  AppColors copyWith({Color? ground, Color? card, Color? border, Color? ink, Color? muted, Color? soft}) => AppColors(
        ground: ground ?? this.ground,
        card: card ?? this.card,
        border: border ?? this.border,
        ink: ink ?? this.ink,
        muted: muted ?? this.muted,
        soft: soft ?? this.soft,
      );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      ground: Color.lerp(ground, other.ground, t)!,
      card: Color.lerp(card, other.card, t)!,
      border: Color.lerp(border, other.border, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      soft: Color.lerp(soft, other.soft, t)!,
    );
  }
}

ThemeData buildTheme(Brightness brightness, Color brand) {
  final dark = brightness == Brightness.dark;
  final c = dark ? AppColors.dark : AppColors.light;
  final onBrand = brand.computeLuminance() > 0.5 ? const Color(0xFF14161B) : Colors.white;
  // Keep the company's exact colour as primary; the seed fills in the rest.
  final scheme = ColorScheme.fromSeed(seedColor: brand, brightness: brightness).copyWith(
    primary: dark ? Color.lerp(brand, Colors.white, 0.25) : brand,
    onPrimary: dark ? const Color(0xFF14161B) : onBrand,
    surface: c.card,
    onSurface: c.ink,
    onSurfaceVariant: c.muted,
    outline: c.muted,
    outlineVariant: c.border,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final text = base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink);
  final buttonText = text.labelLarge!.copyWith(fontSize: 15, fontWeight: FontWeight.w600);
  final radius = BorderRadius.circular(14);

  return base.copyWith(
    textTheme: text,
    extensions: [c],
    scaffoldBackgroundColor: c.ground,
    appBarTheme: AppBarTheme(
      backgroundColor: c.ground,
      foregroundColor: c.ink,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleMedium!.copyWith(fontWeight: FontWeight.w600, color: c.ink),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: c.card,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: c.border)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? c.soft : const Color(0xFFF5F6F8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.border)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.border)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.primary, width: 1.6)),
      labelStyle: TextStyle(color: c.muted),
      hintStyle: TextStyle(color: c.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 50),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 50),
        foregroundColor: c.ink,
        backgroundColor: c.card,
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: buttonText,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: c.border),
      backgroundColor: c.card,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: 0.12),
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? scheme.primary : c.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: states.contains(WidgetState.selected) ? scheme.primary : c.muted),
      ),
    ),
    dividerTheme: DividerThemeData(color: c.border, space: 1),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.card, surfaceTintColor: Colors.transparent),
  );
}

/// Soft tile colours (background, foreground) used for app and record
/// initials, picked per name so the same name always looks the same.
const _soft = [
  (Color(0xFFE6F2F3), Color(0xFF0E7C86)),
  (Color(0xFFEEEAF8), Color(0xFF5B3FB0)),
  (Color(0xFFFCEFE3), Color(0xFFA04A00)),
  (Color(0xFFE5EEFB), Color(0xFF1D5BBF)),
  (Color(0xFFE7F4EA), Color(0xFF1E7A3A)),
  (Color(0xFFFBE9EC), Color(0xFFB0264A)),
  (Color(0xFFF0F1F4), Color(0xFF3B414D)),
];

int _hash(String text) {
  var hash = 0;
  for (final unit in text.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash;
}

/// A stable accent colour per name.
Color colorFor(String text) => _soft[_hash(text) % _soft.length].$2;

/// Background/foreground of a soft tile for [text], in light or dark mode.
(Color, Color) softColorsFor(String text, Brightness brightness) {
  final (bg, fg) = _soft[_hash(text) % _soft.length];
  return brightness == Brightness.dark ? (fg.withValues(alpha: 0.22), Color.lerp(fg, Colors.white, 0.45)!) : (bg, fg);
}

/// Background/foreground for a status badge, guessed from Odoo's usual state
/// keys (draft, done, cancel, ...) so badges read the same in every module.
(Color, Color) statusColors(dynamic key, ColorScheme scheme) {
  final k = key is String ? key.toLowerCase() : '';
  final dark = scheme.brightness == Brightness.dark;
  (Color, Color) pick(Color bg, Color fg) => dark ? (fg.withValues(alpha: 0.22), Color.lerp(fg, Colors.white, 0.5)!) : (bg, fg);
  if (const {
    'done', 'won', 'paid', 'posted', 'sale', 'confirmed', 'approved', 'validate', 'validated', 'active', 'open',
    'in_payment', 'purchase',
  }.contains(k)) {
    return pick(const Color(0xFFE2F2E6), const Color(0xFF1E5A2E));
  }
  if (const {'cancel', 'cancelled', 'lost', 'refused', 'rejected', 'blocked', 'expired'}.contains(k)) {
    return pick(const Color(0xFFFBE4E2), const Color(0xFF8C1D18));
  }
  if (const {'draft', 'new', 'waiting', 'pending', 'to_approve', 'confirm', 'sent', 'qualified', 'assigned', 'partial'}
      .contains(k)) {
    return pick(const Color(0xFFFBF0D9), const Color(0xFF6A4A00));
  }
  return pick(const Color(0xFFEEF0F3), const Color(0xFF3B414D));
}

/// Up to two initials ("Azure Interior" → "AI").
String initialsOf(String text) {
  final words = text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty && RegExp(r'\w').hasMatch(w[0])).toList();
  if (words.isEmpty) return text.trim().isEmpty ? '?' : text.trim().characters.first.toUpperCase();
  final first = words.first.characters.first;
  final second = words.length > 1 ? words[1].characters.first : '';
  return (first + second).toUpperCase();
}
