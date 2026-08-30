import 'package:ai_usage_monitor/core/formatting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Format.compactNumber', () {
    test('leaves small numbers alone', () {
      expect(Format.compactNumber(0), '0');
      expect(Format.compactNumber(999), '999');
    });

    test('abbreviates thousands, millions, and billions', () {
      expect(Format.compactNumber(1000), '1K');
      expect(Format.compactNumber(12400), '12.4K');
      expect(Format.compactNumber(3700000), '3.7M');
      expect(Format.compactNumber(1200000000), '1.2B');
    });

    test('drops a trailing zero decimal', () {
      expect(Format.compactNumber(12000), '12K');
      expect(Format.compactNumber(5000000), '5M');
    });
  });

  group('Format.consumption', () {
    test('shows the ceiling when one is known', () {
      expect(Format.consumption(12400, 8000000, 'tokens'),
          '12.4K of 8M tokens');
    });

    test('omits the ceiling when it is unknown', () {
      expect(Format.consumption(12400, null, 'tokens'), '12.4K tokens');
    });
  });

  group('Format.relativeTime', () {
    final now = DateTime(2026, 6, 15, 12, 0);

    test('collapses the last minute to "just now"', () {
      expect(
        Format.relativeTime(now.subtract(const Duration(seconds: 5)), now: now),
        'just now',
      );
    });

    test('handles clock skew into the future gracefully', () {
      expect(
        Format.relativeTime(now.add(const Duration(minutes: 5)), now: now),
        'just now',
      );
    });

    test('uses minutes, hours, then days', () {
      expect(
        Format.relativeTime(now.subtract(const Duration(minutes: 4)), now: now),
        '4m ago',
      );
      expect(
        Format.relativeTime(now.subtract(const Duration(hours: 2)), now: now),
        '2h ago',
      );
      expect(
        Format.relativeTime(now.subtract(const Duration(days: 3)), now: now),
        '3d ago',
      );
    });

    test('falls back to an absolute date beyond a week', () {
      final result =
          Format.relativeTime(now.subtract(const Duration(days: 20)), now: now);
      expect(result, contains('May'));
    });
  });

  group('Format.resetTime', () {
    final now = DateTime(2026, 6, 15, 12, 0); // A Monday.

    test('shows only the time for today', () {
      expect(Format.resetTime(DateTime(2026, 6, 15, 20, 39), now: now),
          '8:39 PM');
    });

    test('labels tomorrow explicitly', () {
      expect(
        Format.resetTime(DateTime(2026, 6, 16, 23, 59), now: now),
        'Tomorrow 11:59 PM',
      );
    });

    test('uses a weekday name later in the week', () {
      expect(
        Format.resetTime(DateTime(2026, 6, 17, 23, 59), now: now),
        'Wed 11:59 PM',
      );
    });

    test('uses a full date beyond a week', () {
      expect(
        Format.resetTime(DateTime(2026, 6, 30, 9, 15), now: now),
        contains('Jun 30'),
      );
    });
  });

  group('Format.interval', () {
    test('renders minutes and hours', () {
      expect(Format.interval(const Duration(minutes: 5)), '5 min');
      expect(Format.interval(const Duration(minutes: 30)), '30 min');
      expect(Format.interval(const Duration(hours: 1)), '1 hour');
      expect(Format.interval(const Duration(hours: 3)), '3 hours');
    });
  });
}
