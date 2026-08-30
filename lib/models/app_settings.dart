import 'package:flutter/material.dart' show ThemeMode;

import 'rail_placement.dart';

/// User preferences, persisted locally. Contains no secrets — provider
/// credentials live in the macOS Keychain, never here.
class AppSettings {
  const AppSettings({
    this.refreshInterval = const Duration(minutes: 5),
    this.launchAtLogin = false,
    this.recordHistory = true,
    this.railEdge = RailEdge.right,
    this.railOffset = RailOffset.centered,
    this.railExpansion = RailExpansion.onHover,
    this.railVisible = true,
    this.screenId,
    this.themeMode = ThemeMode.system,
    this.showMenuBarIcon = true,
    this.showMenuBarPercent = false,
    this.onboardingComplete = false,
    this.sessionTokenBudget = defaultSessionTokenBudget,
    this.weeklyTokenBudget = defaultWeeklyTokenBudget,
  });

  /// Starting points for local estimation, not published limits — Anthropic
  /// does not publish plan limits as token counts, so there is no authoritative
  /// number to use here. Settings says so plainly and lets the user calibrate.
  ///
  /// The magnitudes are set for the token totals Claude Code actually produces,
  /// which are dominated by cache reads: a heavy five-hour session runs into
  /// the hundreds of millions of tokens once cached input is counted.
  static const int defaultSessionTokenBudget = 250000000;
  static const int defaultWeeklyTokenBudget = 1500000000;

  static const List<Duration> refreshIntervalOptions = [
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(hours: 1),
  ];

  /// How often usage is refreshed automatically.
  final Duration refreshInterval;

  /// Register the app as a macOS login item.
  final bool launchAtLogin;

  /// Persist periodic usage snapshots for the history view.
  final bool recordHistory;

  /// Which screen edge the rail clings to.
  final RailEdge railEdge;

  /// Where along that edge the rail sits.
  final RailOffset railOffset;

  /// Hover, click, or always-open.
  final RailExpansion railExpansion;

  /// Whether the rail is on screen at all. The menu-bar item can toggle this.
  final bool railVisible;

  /// Stable identifier of the display the rail lives on. Null means "the
  /// screen with the menu bar", which is also the fallback when a remembered
  /// display is disconnected.
  final String? screenId;

  final ThemeMode themeMode;

  /// The menu bar is a fallback control, so its icon is on by default and its
  /// percentage is off — the rail is where numbers belong.
  final bool showMenuBarIcon;
  final bool showMenuBarPercent;

  /// False until the user has been through the connect screen once.
  final bool onboardingComplete;

  /// Token ceiling used to convert locally tracked session usage into a
  /// percentage. Only applied to locally tracked windows.
  final int sessionTokenBudget;

  /// Token ceiling for the rolling weekly window.
  final int weeklyTokenBudget;

  /// The menu bar must show something if it is shown at all.
  bool get effectiveShowMenuBarIcon =>
      showMenuBarIcon || !showMenuBarPercent;

  AppSettings copyWith({
    Duration? refreshInterval,
    bool? launchAtLogin,
    bool? recordHistory,
    RailEdge? railEdge,
    RailOffset? railOffset,
    RailExpansion? railExpansion,
    bool? railVisible,
    String? screenId,
    bool clearScreenId = false,
    ThemeMode? themeMode,
    bool? showMenuBarIcon,
    bool? showMenuBarPercent,
    bool? onboardingComplete,
    int? sessionTokenBudget,
    int? weeklyTokenBudget,
  }) {
    return AppSettings(
      refreshInterval: refreshInterval ?? this.refreshInterval,
      launchAtLogin: launchAtLogin ?? this.launchAtLogin,
      recordHistory: recordHistory ?? this.recordHistory,
      railEdge: railEdge ?? this.railEdge,
      railOffset: railOffset ?? this.railOffset,
      railExpansion: railExpansion ?? this.railExpansion,
      railVisible: railVisible ?? this.railVisible,
      screenId: clearScreenId ? null : (screenId ?? this.screenId),
      themeMode: themeMode ?? this.themeMode,
      showMenuBarIcon: showMenuBarIcon ?? this.showMenuBarIcon,
      showMenuBarPercent: showMenuBarPercent ?? this.showMenuBarPercent,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      sessionTokenBudget: sessionTokenBudget ?? this.sessionTokenBudget,
      weeklyTokenBudget: weeklyTokenBudget ?? this.weeklyTokenBudget,
    );
  }

  Map<String, dynamic> toJson() => {
        'refreshIntervalSeconds': refreshInterval.inSeconds,
        'launchAtLogin': launchAtLogin,
        'recordHistory': recordHistory,
        'railEdge': railEdge.name,
        'railOffset': railOffset.fraction,
        'railExpansion': railExpansion.name,
        'railVisible': railVisible,
        'screenId': screenId,
        'themeMode': themeMode.name,
        'showMenuBarIcon': showMenuBarIcon,
        'showMenuBarPercent': showMenuBarPercent,
        'onboardingComplete': onboardingComplete,
        'sessionTokenBudget': sessionTokenBudget,
        'weeklyTokenBudget': weeklyTokenBudget,
      };

  static AppSettings fromJson(Map<String, dynamic> json) {
    const fallback = AppSettings();
    final seconds = json['refreshIntervalSeconds'];
    final offset = json['railOffset'];
    return AppSettings(
      refreshInterval: seconds is int && seconds >= 30
          ? Duration(seconds: seconds)
          : fallback.refreshInterval,
      launchAtLogin: json['launchAtLogin'] as bool? ?? fallback.launchAtLogin,
      recordHistory: json['recordHistory'] as bool? ?? fallback.recordHistory,
      railEdge: RailEdge.values.firstWhere(
        (e) => e.name == json['railEdge'],
        orElse: () => fallback.railEdge,
      ),
      railOffset: offset is num && offset >= 0 && offset <= 1
          ? RailOffset(offset.toDouble())
          : fallback.railOffset,
      railExpansion: RailExpansion.values.firstWhere(
        (e) => e.name == json['railExpansion'],
        orElse: () => fallback.railExpansion,
      ),
      railVisible: json['railVisible'] as bool? ?? fallback.railVisible,
      screenId: json['screenId'] as String?,
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == json['themeMode'],
        orElse: () => fallback.themeMode,
      ),
      showMenuBarIcon:
          json['showMenuBarIcon'] as bool? ?? fallback.showMenuBarIcon,
      showMenuBarPercent:
          json['showMenuBarPercent'] as bool? ?? fallback.showMenuBarPercent,
      onboardingComplete:
          json['onboardingComplete'] as bool? ?? fallback.onboardingComplete,
      sessionTokenBudget: _positiveInt(
        json['sessionTokenBudget'],
        fallback.sessionTokenBudget,
      ),
      weeklyTokenBudget: _positiveInt(
        json['weeklyTokenBudget'],
        fallback.weeklyTokenBudget,
      ),
    );
  }

  static int _positiveInt(Object? value, int fallback) {
    if (value is int && value > 0) return value;
    if (value is num && value > 0) return value.toInt();
    return fallback;
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.refreshInterval == refreshInterval &&
      other.launchAtLogin == launchAtLogin &&
      other.recordHistory == recordHistory &&
      other.railEdge == railEdge &&
      other.railOffset == railOffset &&
      other.railExpansion == railExpansion &&
      other.railVisible == railVisible &&
      other.screenId == screenId &&
      other.themeMode == themeMode &&
      other.showMenuBarIcon == showMenuBarIcon &&
      other.showMenuBarPercent == showMenuBarPercent &&
      other.onboardingComplete == onboardingComplete &&
      other.sessionTokenBudget == sessionTokenBudget &&
      other.weeklyTokenBudget == weeklyTokenBudget;

  @override
  int get hashCode => Object.hash(
        refreshInterval,
        launchAtLogin,
        recordHistory,
        railEdge,
        railOffset,
        railExpansion,
        railVisible,
        screenId,
        themeMode,
        showMenuBarIcon,
        showMenuBarPercent,
        onboardingComplete,
        Object.hash(sessionTokenBudget, weeklyTokenBudget),
      );
}
