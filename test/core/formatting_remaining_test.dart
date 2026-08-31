import 'package:ai_usage_monitor/core/formatting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a percentage window says what is left', () {
    test('reconciles with a CLI that reports remaining', () {
      // `agy` says "78.42% remaining"; the ring says 22% used. Both are true,
      // and the card now shows the figure the CLI showed so the two do not
      // look like a disagreement.
      expect(Format.consumption(21.58, 100, '%'), '78% left');
      expect(Format.consumption(0, 100, '%'), '100% left');
      expect(Format.consumption(100, 100, '%'), '0% left');
    });

    test('leaves other units alone', () {
      expect(Format.consumption(45, 100, 'requests'), '45 of 100 requests');
      expect(Format.consumption(12.5, null, 'USD'), '13 USD');
      expect(Format.remaining(45, 100, 'requests'), isNull);
    });

    test('never reports a negative remainder', () {
      expect(Format.consumption(120, 100, '%'), '0% left');
    });
  });
}
