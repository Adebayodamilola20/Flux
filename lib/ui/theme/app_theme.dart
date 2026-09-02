import 'package:flutter/material.dart';

/// Palette and metrics for the popover.
///
/// Two variants, light and dark, sharing one visual language: a soft-elevated
/// card, hairline border, restrained type, and a single accent that shifts with
/// how much quota is left.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.track,
    required this.accentNormal,
    required this.accentWarning,
    required this.accentCritical,
    required this.accentPositive,
    required this.shadow,
    required this.railFill,
    required this.railBorder,
    required this.railShadow,
    required this.accentSystem,
  });

  final Color surface;
  final Color surfaceRaised;
  final Color border;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color track;
  final Color accentNormal;
  final Color accentWarning;
  final Color accentCritical;
  final Color accentPositive;
  final Color shadow;

  /// The rail's own surface.
  ///
  /// Separate from [surface] because the rail is not a panel: it sits flush
  /// against the bezel and reads as part of the display, so it is denser and
  /// more opaque than anything floating above the desktop. It still follows
  /// the theme — a black bar on a light desktop reads as a bug, which is
  /// exactly how it was reported.
  final Color railFill;
  final Color railBorder;
  final Color railShadow;

  /// macOS system blue — what a native switch, a selected segment and a
  /// focused field use. Not one of the quota accents: those mean "how close to
  /// the limit", and reusing one here would make a toggle look like a warning.
  final Color accentSystem;

  static const AppPalette dark = AppPalette(
    surface: Color(0xFF121214),
    surfaceRaised: Color(0xFF1B1B1F),
    border: Color(0x1AFFFFFF),
    divider: Color(0x14FFFFFF),
    textPrimary: Color(0xFFF2F2F4),
    textSecondary: Color(0x8CFFFFFF),
    textTertiary: Color(0x59FFFFFF),
    track: Color(0x1FFFFFFF),
    accentNormal: Color(0xFF00E58A),
    accentWarning: Color(0xFFD7FF2F),
    accentCritical: Color(0xFFFF5A1F),
    accentPositive: Color(0xFF00E58A),
    shadow: Color(0x99000000),
    railFill: Color(0xFF000000),
    railBorder: Color(0xFF000000),
    railShadow: Color(0x99000000),
    accentSystem: Color(0xFF0A84FF),
  );

  static const AppPalette light = AppPalette(
    surface: Color(0xFFFCFCFD),
    surfaceRaised: Color(0xFFF2F2F5),
    border: Color(0x14000000),
    divider: Color(0x0F000000),
    textPrimary: Color(0xFF16161A),
    textSecondary: Color(0x99000000),
    textTertiary: Color(0x66000000),
    track: Color(0x14000000),
    accentNormal: Color(0xFF059669),
    accentWarning: Color(0xFF8A9908),
    accentCritical: Color(0xFFD84A16),
    accentPositive: Color(0xFF059669),
    shadow: Color(0x2E000000),
    // Not pure white: the rail needs to separate from a light desktop the way
    // the black one separates from a dark desktop.
    railFill: Color(0xFFF7F7F9),
    railBorder: Color(0x14000000),
    railShadow: Color(0x38000000),
    accentSystem: Color(0xFF007AFF),
  );

  /// Accent for a usage fraction. Thresholds are chosen so a mid-range value
  /// reads as "watch this" rather than "fine", which matches how quota
  /// pressure actually feels.
  Color accentFor(double? fraction) {
    if (fraction == null) return textTertiary;
    if (fraction >= 0.7) return accentCritical;
    if (fraction >= 0.45) return accentWarning;
    return accentNormal;
  }

  @override
  AppPalette copyWith({
    Color? surface,
    Color? surfaceRaised,
    Color? border,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? track,
    Color? accentNormal,
    Color? accentWarning,
    Color? accentCritical,
    Color? accentPositive,
    Color? shadow,
    Color? railFill,
    Color? railBorder,
    Color? railShadow,
    Color? accentSystem,
  }) {
    return AppPalette(
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      track: track ?? this.track,
      accentNormal: accentNormal ?? this.accentNormal,
      accentWarning: accentWarning ?? this.accentWarning,
      accentCritical: accentCritical ?? this.accentCritical,
      accentPositive: accentPositive ?? this.accentPositive,
      shadow: shadow ?? this.shadow,
      railFill: railFill ?? this.railFill,
      railBorder: railBorder ?? this.railBorder,
      railShadow: railShadow ?? this.railShadow,
      accentSystem: accentSystem ?? this.accentSystem,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      surface: mix(surface, other.surface),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      border: mix(border, other.border),
      divider: mix(divider, other.divider),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textTertiary: mix(textTertiary, other.textTertiary),
      track: mix(track, other.track),
      accentNormal: mix(accentNormal, other.accentNormal),
      accentWarning: mix(accentWarning, other.accentWarning),
      accentCritical: mix(accentCritical, other.accentCritical),
      accentPositive: mix(accentPositive, other.accentPositive),
      shadow: mix(shadow, other.shadow),
      railFill: mix(railFill, other.railFill),
      railBorder: mix(railBorder, other.railBorder),
      railShadow: mix(railShadow, other.railShadow),
      accentSystem: mix(accentSystem, other.accentSystem),
    );
  }
}

/// Fixed metrics for the rail. The widget is small and deliberately so — it
/// sits on the edge of a screen someone is working on.
///
/// Sizes that the native window also depends on come from `RailMetrics` over
/// the channel instead; these are the values only Flutter needs.
abstract final class AppMetrics {
  /// Outer padding inside a card.
  static const double cardPadding = 14;

  /// Card corner radius. Matches the curvature macOS uses for floating panels
  /// at this size.
  static const double cardRadius = 16;

  /// Diameter of a provider's usage ring.
  static const double ringDiameter = 32;

  /// Stroke width of that ring.
  static const double ringStroke = 2.8;

  /// The collapsed state: a sliver against the screen edge, small enough to
  /// forget about and large enough to find. Anything bigger stops being a hint
  /// and starts being a widget parked on top of the user's work.
  static const double nubWidth = 7;
  static const double nubHeight = 84;
  static const double nubRadius = 3.5;

  /// Width of the hover card.
  static const double calloutWidth = 218;

  /// Gap between the card's tail and the rail.
  static const double calloutGap = 2;

  /// Expansion. Fast enough to feel like it was already there, eased so it
  /// arrives rather than stops.
  /// Long enough for the rings to arrive one at a time and be seen doing it.
  ///
  /// At a quarter of a second the stagger existed but was over before the eye
  /// could follow it, so the rail still read as one slab appearing. This is
  /// close to a SwiftUI spring's settling time, which is the pace the motion
  /// was being compared against.
  static const Duration expand = Duration(milliseconds: 560);

  /// Closing stays brisk. It runs as one motion, and a slow exit holds
  /// attention the user has already moved on from.
  static const Duration collapse = Duration(milliseconds: 240);

  static const Duration progressAnimation = Duration(milliseconds: 520);
  static const Duration fadeAnimation = Duration(milliseconds: 180);

  /// How long the hover card takes to travel between rings. Slower than
  /// the content cross-fade so the movement is what the eye follows.
  static const Duration calloutMove = Duration(milliseconds: 260);
}

abstract final class AppTheme {
  /// macOS system font, so the popover matches native chrome.
  static const String _fontFamily = '.AppleSystemUIFont';

  static ThemeData of(Brightness brightness) {
    final palette = brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;

    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      fontFamily: _fontFamily,
      scaffoldBackgroundColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.compact,
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.accentNormal,
        brightness: brightness,
      ),
    );

    return base.copyWith(
      extensions: [palette],
      textTheme: base.textTheme.apply(
        bodyColor: palette.textPrimary,
        displayColor: palette.textPrimary,
      ),
    );
  }
}

extension PaletteAccess on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}
