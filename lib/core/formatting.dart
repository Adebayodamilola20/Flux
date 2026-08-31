import 'package:intl/intl.dart';

/// Formatting helpers shared by the popover and settings UI.
///
/// Kept free of Flutter imports so they are trivially unit-testable.
abstract final class Format {
  static final DateFormat _timeOfDay = DateFormat('h:mm a');
  static final DateFormat _weekdayTime = DateFormat('EEE h:mm a');
  static final DateFormat _dateTime = DateFormat('MMM d, h:mm a');

  /// Reset time, phrased relative to [now] the way a person would say it:
  /// "8:39 PM" today, "Sat 8:39 PM" this week, a full date beyond that.
  static String resetTime(DateTime resetsAt, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final days = _calendarDaysBetween(reference, resetsAt);

    if (days == 0) return _timeOfDay.format(resetsAt);
    if (days == 1) return 'Tomorrow ${_timeOfDay.format(resetsAt)}';
    if (days > 1 && days < 7) return _weekdayTime.format(resetsAt);
    return _dateTime.format(resetsAt);
  }

  /// Compact elapsed time: "just now", "4m ago", "2h ago", "3d ago".
  static String relativeTime(DateTime timestamp, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final delta = reference.difference(timestamp);

    if (delta.isNegative) return 'just now';
    if (delta.inSeconds < 45) return 'just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    if (delta.inDays < 7) return '${delta.inDays}d ago';
    return _dateTime.format(timestamp);
  }

  /// Abbreviates large counts: 940, 12.4K, 3.7M, 1.2B.
  static String compactNumber(num value) {
    final v = value.abs();
    if (v < 1000) return value.toStringAsFixed(0);
    if (v < 1000000) return '${_oneDecimal(value / 1000)}K';
    if (v < 1000000000) return '${_oneDecimal(value / 1000000)}M';
    return '${_oneDecimal(value / 1000000000)}B';
  }

  /// "12.4K of 8.0M tokens" — the detail line under a progress bar.
  static String consumption(num consumed, num? limit, String unit) {
    // A percentage reads as what is left, not as "21.58 of 100 %".
    //
    // Worth stating explicitly rather than leaving to arithmetic: the CLIs and
    // dashboards these figures come from mostly report what *remains*, while a
    // ring has to fill as you consume. Showing "22%" beside a CLI saying "78%
    // remaining" looks like a disagreement until you do the subtraction, so the
    // card does it.
    final left = remaining(consumed, limit, unit);
    if (left != null) return left;

    final used = compactNumber(consumed);
    if (limit == null) return '$used $unit';
    return '$used of ${compactNumber(limit)} $unit';
  }

  /// What is left of a window measured as a percentage, or null when the window
  /// is measured in something else.
  static String? remaining(num consumed, num? limit, String unit) {
    if (unit != '%' || limit == null || limit <= 0) return null;
    final left = (limit - consumed).clamp(0, limit);
    return '${left.round()}% left';
  }

  /// A refresh interval as a short label: "5 min", "1 hour".
  static String interval(Duration duration) {
    if (duration.inMinutes < 60) {
      final m = duration.inMinutes;
      return '$m min';
    }
    final h = duration.inHours;
    return h == 1 ? '1 hour' : '$h hours';
  }

  static String _oneDecimal(double value) {
    final rounded = (value * 10).round() / 10;
    // Drop a trailing ".0" so "12.0K" reads as "12K".
    return rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
  }

  /// Whole-day distance between two instants, ignoring time of day.
  static int _calendarDaysBetween(DateTime a, DateTime b) {
    final dayA = DateTime(a.year, a.month, a.day);
    final dayB = DateTime(b.year, b.month, b.day);
    return dayB.difference(dayA).inDays;
  }
}
