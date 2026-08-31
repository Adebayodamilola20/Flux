import 'package:ai_usage_monitor/providers/cli/terminal_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stripAnsi', () {
    test('removes colour and cursor sequences', () {
      const raw = '\x1B[32mReady\x1B[0m\x1B[2K\x1B[1;1H';
      expect(TerminalText.stripAnsi(raw), 'Ready');
    });

    test('removes the terminal-mode queries a TUI opens with', () {
      // Exactly what agy emits on startup.
      const raw = '\x1B[>4m\x1B[=0;1u\x1B[>4;2m\x1B[=1;1uWelcome';
      expect(TerminalText.stripAnsi(raw), 'Welcome');
    });

    test('removes OSC window-title strings', () {
      const raw = '\x1B]0;some title\x07Usage';
      expect(TerminalText.stripAnsi(raw), 'Usage');
    });

    test('keeps the characters a value is made of', () {
      const raw = '\x1B[1m45 / 100\x1B[0m requests (62.5%)';
      expect(TerminalText.stripAnsi(raw), '45 / 100 requests (62.5%)');
    });
  });

  group('screenLines', () {
    test('collapses a spinner redrawn on the same line', () {
      const raw = '⣾ Signing in...\r⣷ Signing in...\r⣯ Signing in...\r';
      // One distinct line of information, not three frames of animation.
      expect(TerminalText.readableLines(raw), ['Signing in...']);
    });

    test('keeps distinct lines in the order they were drawn', () {
      const raw = 'Header\nFirst 10/20 requests\nSecond 5/20 requests\n';
      expect(TerminalText.screenLines(raw), [
        'Header',
        'First 10/20 requests',
        'Second 5/20 requests',
      ]);
    });

    test('drops blank and whitespace-only lines', () {
      expect(TerminalText.screenLines('a\n\n   \n\nb'), ['a', 'b']);
    });
  });

  group('readableLines', () {
    test('strips box drawing and progress blocks', () {
      const raw = '│ Daily ████████░░░░ 45/100 requests │';
      expect(TerminalText.readableLines(raw).single,
          contains('45/100 requests'));
      expect(TerminalText.readableLines(raw).single, isNot(contains('█')));
    });

    test('strips the horizontal rules a TUI draws between panes', () {
      expect(TerminalText.readableLines('────────────'), isEmpty);
    });
  });

  group('state detection', () {
    test('recognises the workspace-trust gate', () {
      const raw = 'Do you trust the contents of this project?\n'
          '> Yes, I trust this folder\n  No, exit';
      expect(TerminalText.looksLikePrompt(raw), isTrue);
    });

    test('recognises a signed-out CLI', () {
      const raw = 'Welcome to the Antigravity CLI. '
          'You are currently not signed in.';
      expect(TerminalText.looksSignedOut(raw), isTrue);
    });

    test('does not call a signed-in session signed out', () {
      const raw = 'someone@example.com (Antigravity Starter Quota)';
      expect(TerminalText.looksSignedOut(raw), isFalse);
      expect(TerminalText.looksLikePrompt(raw), isFalse);
    });
  });
}
