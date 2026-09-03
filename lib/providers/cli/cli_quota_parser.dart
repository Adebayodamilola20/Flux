import '../../models/usage_source.dart';
import '../../models/usage_window.dart';
import 'terminal_text.dart';

/// What a CLI's usage panel said.
class CliQuotaReading {
  const CliQuotaReading({
    required this.windows,
    this.planLabel,
    this.accountLabel,
  });

  final List<UsageWindow> windows;

  /// The tier the CLI named, e.g. "Antigravity Starter Quota".
  final String? planLabel;

  /// The signed-in account the CLI named.
  final String? accountLabel;

  bool get isEmpty => windows.isEmpty;
}

/// Reads quota figures out of an official CLI's usage panel.
///
/// Built to survive the CLI changing its layout. These panels are not an API:
/// labels get reworded, columns get reordered, and a version bump can move
/// everything. So nothing here matches a whole line against a fixed template.
/// Instead each line is scanned for the *shapes* a quota takes — `45 / 100`,
/// `62%`, `resets in 3h 12m` — and the surrounding words become the label.
///
/// The cost of that tolerance is that a line can be misread. Everything this
/// produces is therefore labelled [UsageSource.interactiveCli], which the UI
/// presents as weaker than an API figure.
abstract final class CliQuotaParser {
  /// `45 / 100`, `45/100`, `45 of 100`, `45 out of 100`.
  static final RegExp _fraction = RegExp(
    r'([\d][\d,_\.]*)\s*(?:/|of|out\s+of)\s*([\d][\d,_\.]*)',
    caseSensitive: false,
  );

  /// `62%`, `62.5 %`.
  static final RegExp _percent = RegExp(r'([\d]{1,3}(?:\.\d+)?)\s*%');

  /// `resets in 3h 12m`, `Resets at 2:00 AM`, `renews on Mar 3`.
  static final RegExp _reset = RegExp(
    r'(?:resets?|renews?|refreshes?)\s*(?:in|at|on)?\s*[:\-]?\s*(.{0,28})',
    caseSensitive: false,
  );

  /// `3h 12m`, `45m`, `2d 4h`, `90 minutes`.
  static final RegExp _duration = RegExp(
    r'(\d+)\s*(d|day|days|h|hr|hrs|hour|hours|m|min|mins|minute|minutes)\b',
    caseSensitive: false,
  );

  /// The plan or tier a CLI prints in its header.
  static final RegExp _plan = RegExp(
    r'\(([^)]*\b(?:quota|plan|tier|subscription)\b[^)]*)\)',
    caseSensitive: false,
  );

  static final RegExp _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+');

  /// The characters CLIs draw progress bars out of.
  ///
  /// These carry no information the numbers beside them do not, and left in a
  /// label they produce rows called `[█████████░]`.
  static final RegExp _barRun = RegExp(r'[\[\]▀-▟=#·.\-–—_]{3,}');

  /// A section title in capitals, e.g. `GEMINI MODELS`. Rows underneath one of
  /// these are usually drawn with no label of their own.
  static final RegExp _groupHeading = RegExp(r'^[^a-z\d]*[A-Z][A-Z &/+]{2,}$');

  /// Acronyms worth keeping in capitals when a shouted heading is folded back
  /// into sentence case.
  static const List<String> _acronyms = ['GPT', 'AI', 'API', 'CLI', 'LLM'];

  /// Words that make an otherwise plain line a quota sub-heading, e.g.
  /// `Weekly Limit Remaining`.
  static const List<String> _headingWords = [
    'limit', 'quota', 'usage', 'remaining', 'allowance', 'credits',
  ];

  /// Words that mean the line is a quota row rather than prose.
  static const List<String> _unitWords = [
    'request', 'requests',
    'credit', 'credits',
    'token', 'tokens',
    'message', 'messages',
    'prompt', 'prompts',
    'call', 'calls',
    'quota', 'limit', 'used', 'remaining',
  ];

  /// Lines that look like a quota but are really instructions or errors.
  static const List<String> _rejectWords = [
    'upgrade', 'learn more', 'documentation', 'http://', 'https://',
    'press ', 'esc ', '↑/↓', 'shortcuts',
  ];

  /// Parses a captured panel.
  ///
  /// [now] anchors relative reset times and is injectable so the tests do not
  /// depend on the clock.
  static CliQuotaReading parse(String raw, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final lines = TerminalText.readableLines(raw);

    final windows = <UsageWindow>[];
    String? planLabel;
    String? accountLabel;
    final usedIds = <String>{};

    // Panels increasingly draw a heading, then an unlabelled bar underneath it,
    // then a restatement of the same figure with the reset time. Reading each
    // line in isolation turns that into one window with a label made of block
    // characters and a second, duplicate window. Carrying the heading forward
    // and folding the restatement back in is what makes such a panel read as
    // the one quota it is.
    String? groupHeading;
    String? rowHeading;

    // Where the current section's window landed, so a restatement merges into
    // it rather than appending a near-duplicate.
    int? openWindow;

    // A group heading deliberately does not clear the sub-heading above it.
    // [TerminalText.readableLines] drops repeated lines, because a TUI redraws
    // the same rows many times per second — so a panel that prints "Weekly
    // Limit Remaining" over every group only shows it once, and the later
    // groups would otherwise lose the word that says their figure counts
    // downwards. A section that means something different states so, and that
    // statement overwrites this.

    for (final line in lines) {
      planLabel ??= _plan.firstMatch(line)?.group(1)?.trim();
      accountLabel ??= _email.firstMatch(line)?.group(0);

      final heading = _headingFor(line);
      if (heading != null) {
        if (heading.isGroup) {
          groupHeading = heading.text;
        } else {
          rowHeading = heading.text;
        }
        openWindow = null;
        continue;
      }

      final row = _parseLine(
        line,
        reference,
        usedIds,
        sectionLabel: _sectionLabel(groupHeading, rowHeading),
        sectionMeansRemaining: _meansRemaining(rowHeading) ||
            _meansRemaining(groupHeading),
      );
      if (row == null) continue;

      if (row.isContinuation && openWindow != null) {
        windows[openWindow] = _merge(windows[openWindow], row.window);
        continue;
      }

      openWindow = windows.length;
      windows.add(row.window);
    }

    return CliQuotaReading(
      windows: windows,
      planLabel: planLabel,
      accountLabel: accountLabel,
    );
  }

  /// Folds a restated figure into the window it restates.
  ///
  /// The restatement usually carries the reset time and a rounded percentage,
  /// while the bar above it carries the precise one. Each contributes what it
  /// actually knows; neither overwrites the other with less.
  static UsageWindow _merge(UsageWindow existing, UsageWindow restatement) {
    return UsageWindow(
      id: existing.id,
      label: existing.label,
      consumed: existing.consumed,
      limit: existing.limit,
      unit: existing.unit,
      resetsAt: existing.resetsAt ?? restatement.resetsAt,
      source: existing.source,
    );
  }

  /// A heading, when this line is one.
  static _Heading? _headingFor(String line) {
    final text = line.trim().replaceAll(RegExp(r'^[\s•·*>|└├─┌│:]+'), '').trim();
    if (text.isEmpty) return null;

    // Anything with a figure in it is a row, not a heading.
    if (_percent.hasMatch(text) || _fraction.hasMatch(text)) return null;
    if (_rejectWords.any(text.toLowerCase().contains)) return null;
    if (text.length > 48) return null;

    if (_groupHeading.hasMatch(text)) {
      return _Heading(_sentenceCase(text), isGroup: true);
    }

    final lower = text.toLowerCase();
    if (!_headingWords.any((w) => RegExp('\\b$w\\b').hasMatch(lower))) {
      return null;
    }
    // A sub-heading is a short phrase. A sentence that happens to mention a
    // limit is prose.
    if (text.split(RegExp(r'\s+')).length > 5) return null;
    return _Heading(text, isGroup: false);
  }

  /// `GEMINI MODELS` reads as a shout in a list of rows; `Gemini models` does
  /// not. Acronyms are kept as the CLI wrote them.
  static String _sentenceCase(String heading) {
    final words = heading.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final out = <String>[];

    for (final word in words) {
      if (_acronyms.contains(word)) {
        out.add(word);
      } else if (out.isEmpty) {
        out.add(word[0].toUpperCase() + word.substring(1).toLowerCase());
      } else {
        out.add(word.toLowerCase());
      }
    }

    return out.join(' ');
  }

  /// The label rows in the current section inherit.
  static String? _sectionLabel(String? group, String? row) {
    if (group == null) return row;

    // The group names *what* is limited — "Gemini models" — and the row
    // heading above it names *over what period* — "Weekly Limit Remaining".
    // Returning the group alone dropped the period, so a weekly allowance
    // appeared on the rail as an unqualified figure and there was no way to
    // tell it from a per-session one. The CLI states it; so does this.
    final period = _periodOf(row);
    return period == null ? group : '$group ($period)';
  }

  /// The period a heading names, if it names one.
  ///
  /// Matched against whole words so "weekly" is found and "biweekly" is not
  /// mistaken for it, and ordered longest-first so "5-hour" wins over "hour".
  static String? _periodOf(String? heading) {
    if (heading == null) return null;
    final lower = heading.toLowerCase();
    for (final period in const [
      'weekly',
      'monthly',
      'daily',
      'hourly',
      'per week',
      'per day',
      'per month',
    ]) {
      if (RegExp('\\b${RegExp.escape(period)}\\b').hasMatch(lower)) {
        // Normalised, so "per week" and "weekly" do not read as two different
        // things on two different rows of the same rail.
        return switch (period) {
          'per week' => 'weekly',
          'per day' => 'daily',
          'per month' => 'monthly',
          _ => period,
        };
      }
    }
    return null;
  }

  static bool _meansRemaining(String? text) {
    if (text == null) return false;
    final lower = text.toLowerCase();
    return lower.contains('remaining') || lower.contains('left');
  }

  static _Row? _parseLine(
    String line,
    DateTime now,
    Set<String> usedIds, {
    String? sectionLabel,
    bool sectionMeansRemaining = false,
  }) {
    final lower = line.toLowerCase();

    if (_rejectWords.any(lower.contains)) return null;

    final fraction = _fraction.firstMatch(line);
    final percent = _percent.firstMatch(line);
    if (fraction == null && percent == null) return null;

    // A bare number pair with no vocabulary around it is as likely to be a
    // version string or a date as a quota.
    final hasUnitWord = _unitWords.any(
      (word) => RegExp('\\b$word\\b').hasMatch(lower),
    );
    if (!hasUnitWord && percent == null) return null;

    num consumed;
    num? limit;

    if (fraction != null) {
      final used = _number(fraction.group(1));
      final total = _number(fraction.group(2));
      if (used == null || total == null || total <= 0) return null;
      // `45 / 100` in these panels means "45 used of 100", but some CLIs print
      // remaining instead. There is no way to tell from the numbers alone, so
      // the reading is taken at face value and the label carries the nuance.
      if (used > total) return null;
      consumed = used;
      limit = total;
    } else {
      final value = double.tryParse(percent!.group(1)!);
      if (value == null || value > 100) return null;
      // A percentage with no absolute numbers is expressed against 100 so the
      // generic model still has a fraction to draw.
      consumed = value;
      limit = 100;

      // "30% remaining" and "30% used" are the same sentence with opposite
      // meanings. The row says which when it can; when the row is just a bar,
      // the heading above it is the only thing that does.
      if (_meansRemaining(lower) || sectionMeansRemaining) {
        consumed = 100 - value;
      }
    }

    // A row drawn as nothing but a bar has no label of its own and belongs to
    // whatever heading it sits under.
    final ownLabel = _labelFor(line, fraction ?? percent!);
    final isContinuation = ownLabel.isEmpty;
    final label = ownLabel.isNotEmpty ? ownLabel : (sectionLabel ?? '');
    if (label.isEmpty) return null;

    var id = _idFor(label);
    var suffix = 2;
    while (!usedIds.add(id)) {
      id = '${_idFor(label)}_${suffix++}';
    }

    return _Row(
      window: UsageWindow(
        id: id,
        label: label,
        consumed: consumed,
        limit: limit,
        unit: _unitFor(lower),
        resetsAt: _resetFor(line, now),
        source: UsageSource.interactiveCli,
      ),
      isContinuation: isContinuation,
    );
  }

  /// The words around the numbers, cleaned up into a label.
  ///
  /// Empty means the row names nothing of its own — either it is a bare bar, or
  /// it only restates a figure already given. Both belong to the heading above
  /// them, which the caller supplies.
  static String _labelFor(String line, RegExpMatch match) {
    var label = _cleanLabel(line.substring(0, match.start));

    if (label.isEmpty) {
      // Some panels put the label after the numbers: "45/100 requests today".
      label = _cleanLabel(_stripQualifiers(line.substring(match.end)));
    }

    if (label.length > 40) label = label.substring(0, 40).trim();
    return label;
  }

  /// Strips table decoration, bullets and progress bars.
  static String _cleanLabel(String raw) {
    var text = raw.replaceAll(_barRun, ' ');
    text = text.replaceAll(RegExp(r'^[\s•·*\-–—>|:\[\]]+'), '');
    text = text.replaceAll(RegExp(r'[\s:|\[\]]+$'), '');
    return text.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  /// Removes the words that qualify a figure rather than name it.
  ///
  /// `99% remaining · Refreshes in 145h 16m` describes the quota above it; it
  /// is not a quota called "remaining · Refreshes in 145h 16m". Taking the
  /// qualifiers out is what leaves nothing behind, which is how such a line is
  /// recognised as a restatement.
  static String _stripQualifiers(String tail) {
    var text = tail.replaceAll(_reset, ' ');
    text = text.replaceAll(
      RegExp(r'\b(used|remaining|left|available|free)\b', caseSensitive: false),
      ' ',
    );
    return text.replaceAll(RegExp(r'[·|,;]+'), ' ');
  }

  static String _idFor(String label) {
    final slug = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? 'window' : slug;
  }

  static String _unitFor(String lower) {
    for (final unit in const [
      'requests', 'credits', 'tokens', 'messages', 'prompts', 'calls',
    ]) {
      if (lower.contains(unit)) return unit;
    }
    return 'requests';
  }

  /// Resolves a reset phrase to an instant, absolute or relative.
  static DateTime? _resetFor(String line, DateTime now) {
    final match = _reset.firstMatch(line);
    if (match == null) return null;
    final phrase = match.group(1) ?? '';

    // Relative first: "in 3h 12m" is unambiguous, where a bare "2:00" is not.
    final durations = _duration.allMatches(phrase).toList();
    if (durations.isNotEmpty && RegExp(r'\bin\b', caseSensitive: false)
        .hasMatch(match.group(0)!)) {
      var total = Duration.zero;
      for (final d in durations) {
        final value = int.tryParse(d.group(1)!) ?? 0;
        total += switch (d.group(2)!.toLowerCase()) {
          'd' || 'day' || 'days' => Duration(days: value),
          'h' || 'hr' || 'hrs' || 'hour' || 'hours' => Duration(hours: value),
          _ => Duration(minutes: value),
        };
      }
      return total == Duration.zero ? null : now.add(total);
    }

    return _absoluteTime(phrase, now);
  }

  /// `2:00 AM`, `11:59 PM`, `14:30`.
  static DateTime? _absoluteTime(String phrase, DateTime now) {
    final match = RegExp(
      r'(\d{1,2}):(\d{2})\s*(am|pm)?',
      caseSensitive: false,
    ).firstMatch(phrase);
    if (match == null) return null;

    var hour = int.tryParse(match.group(1)!) ?? 0;
    final minute = int.tryParse(match.group(2)!) ?? 0;
    if (minute > 59) return null;

    final meridiem = match.group(3)?.toLowerCase();
    if (meridiem == 'pm' && hour < 12) hour += 12;
    if (meridiem == 'am' && hour == 12) hour = 0;
    if (hour > 23) return null;

    var resets = DateTime(now.year, now.month, now.day, hour, minute);
    // A reset time that has already passed today refers to tomorrow.
    if (!resets.isAfter(now)) resets = resets.add(const Duration(days: 1));
    return resets;
  }

  static num? _number(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.replaceAll(RegExp(r'[,_]'), '');
    return num.tryParse(cleaned);
  }
}

/// A section title found in a panel.
class _Heading {
  const _Heading(this.text, {required this.isGroup});

  final String text;

  /// True for a top-level title in capitals, which starts a new section.
  /// False for a sub-heading, which qualifies the rows under the current one.
  final bool isGroup;
}

/// One parsed row, and whether it stands alone.
class _Row {
  const _Row({required this.window, required this.isContinuation});

  final UsageWindow window;

  /// True when the row named nothing of its own, so it either belongs to the
  /// heading above it or restates the row before it.
  final bool isContinuation;
}
