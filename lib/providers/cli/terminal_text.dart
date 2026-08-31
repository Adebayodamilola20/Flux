/// Turns raw pseudo-terminal bytes into the lines a person would have seen.
///
/// A TUI does not emit a document. It emits a stream of cursor moves, colour
/// changes, and partial redraws — the same line is often rewritten a dozen
/// times as a spinner turns or a panel animates in. Parsing that stream
/// directly is how a parser ends up matching a half-drawn frame.
///
/// Everything here is pure string work so the provider parsers can be tested
/// against recorded fixtures with no process, no PTY, and no platform.
abstract final class TerminalText {
  /// CSI sequences (colour, cursor movement, erase), OSC strings (window
  /// titles, hyperlinks), and the two-byte escapes.
  ///
  /// The CSI parameter class is the full `0x30-0x3F` range, not just digits and
  /// `?`. Modern TUIs open with private sequences like `\x1B[>4m` and
  /// `\x1B[=1;1u` to negotiate keyboard protocols, and a narrower pattern
  /// leaves that gibberish sitting in front of the first real line.
  static final RegExp _ansi = RegExp(
    r'\x1B\[[0-?]*[ -/]*[@-~]'
    r'|\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)'
    r'|\x1B[@-Z\\-_]',
  );

  /// Control characters that survive escape-stripping and would otherwise end
  /// up inside matched values. Tab and newline are handled separately.
  static final RegExp _controls = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');

  /// Box-drawing, block, and Braille runs. Braille is how Go and Node CLIs
  /// draw spinners; block characters are how they draw progress bars. Both are
  /// noise once the numbers beside them have been read.
  static final RegExp _decoration = RegExp(
    r'[─-╿▀-▟⠀-⣿■-◿]+',
  );

  /// Removes escape sequences and control characters, leaving printable text.
  static String stripAnsi(String raw) {
    return raw
        .replaceAll(_ansi, '')
        .replaceAll('\t', ' ')
        .replaceAll(_controls, '');
  }

  /// The distinct lines a redrawing TUI actually put on screen.
  ///
  /// Carriage returns are treated as line breaks rather than cursor-to-column-
  /// zero, which is a deliberate simplification: it turns each redraw into its
  /// own line instead of overwriting in place, and the duplicate pass below
  /// then collapses them. The alternative — emulating a full screen buffer —
  /// is far more code for output we only ever grep.
  ///
  /// Order is preserved and the *first* occurrence of a line is kept, so a
  /// panel that is drawn once and then scrolled off is still visible.
  static List<String> screenLines(String raw) {
    final cleaned = stripAnsi(raw)
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    final seen = <String>{};
    final lines = <String>[];

    for (final line in cleaned.split('\n')) {
      final trimmed = line.trimRight();
      final key = trimmed.trim();
      if (key.isEmpty) continue;
      if (!seen.add(key)) continue;
      lines.add(trimmed);
    }

    return lines;
  }

  /// [screenLines] with box-drawing and spinner characters removed, and runs of
  /// whitespace collapsed — the form the parsers match against.
  static List<String> readableLines(String raw) {
    final result = <String>[];
    // Deduplicate *after* stripping decoration, not before. A spinner redraws
    // the same sentence behind a different Braille frame each tick, so the
    // lines only become identical once the animation characters are gone.
    final seen = <String>{};

    for (final line in screenLines(raw)) {
      final cleaned = line
          .replaceAll(_decoration, ' ')
          .replaceAll(RegExp(r'\s{2,}'), '  ')
          .trim();
      if (cleaned.isEmpty) continue;
      if (!seen.add(cleaned)) continue;
      result.add(cleaned);
    }
    return result;
  }

  /// True when the captured text shows the CLI waiting on a yes/no prompt.
  ///
  /// These gates swallow the keystrokes meant for the panel, so a probe has to
  /// notice them rather than assume its input landed.
  static bool looksLikePrompt(String raw) {
    final text = stripAnsi(raw).toLowerCase();
    return text.contains('do you trust') ||
        text.contains('yes, i trust') ||
        text.contains('(y/n)') ||
        text.contains('[y/n]');
  }

  /// True when the CLI says, in any of its usual phrasings, that nobody is
  /// signed in.
  static bool looksSignedOut(String raw) {
    final text = stripAnsi(raw).toLowerCase();
    return text.contains('not signed in') ||
        text.contains('not logged in') ||
        text.contains('please sign in') ||
        text.contains('please log in') ||
        text.contains('authentication required') ||
        text.contains('run `login`') ||
        text.contains('/login');
  }
}
