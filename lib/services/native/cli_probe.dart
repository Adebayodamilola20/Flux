/// One scripted keystroke in a CLI probe.
class CliProbeStep {
  const CliProbeStep({required this.at, required this.keys});

  /// Seconds after launch to send [keys].
  final double at;

  /// Exactly what to type. Include the carriage return.
  final String keys;

  Map<String, Object?> toJson() => {'at': at, 'keys': keys};

  /// Types a slash command and runs it.
  factory CliProbeStep.command(double at, String command) =>
      CliProbeStep(at: at, keys: '$command\r');

  /// Accepts whatever a yes/no gate has highlighted.
  ///
  /// These CLIs put a workspace-trust prompt in front of the session, and it
  /// swallows the first thing typed. Answering it explicitly is what lets the
  /// command that follows actually reach the prompt.
  factory CliProbeStep.confirm(double at) =>
      CliProbeStep(at: at, keys: '\r');

  /// Leaves the session without waiting for a shutdown animation.
  factory CliProbeStep.quit(double at) =>
      CliProbeStep(at: at, keys: '');
}

/// What a probe of an official CLI produced.
class CliProbeResult {
  const CliProbeResult({
    required this.output,
    required this.launched,
    required this.timedOut,
    this.exitCode,
    this.failure,
  });

  /// Everything the CLI drew, escape sequences and all. Interpreting it is the
  /// caller's job — keeping the raw bytes means a recorded fixture exercises
  /// exactly the same path as a live session.
  final String output;

  /// False when the CLI is not installed or could not be started.
  final bool launched;

  /// True when the budget ran out before the session finished. The output may
  /// still be usable; a panel that drew before the timeout is still a panel.
  final bool timedOut;

  final int? exitCode;

  /// Why the probe could not run at all.
  final String? failure;

  bool get hasOutput => output.trim().isNotEmpty;

  static const CliProbeResult unavailable = CliProbeResult(
    output: '',
    launched: false,
    timedOut: false,
    failure: 'The command-line tool is not installed.',
  );

  static CliProbeResult? fromMap(Object? value) {
    if (value is! Map) return null;
    return CliProbeResult(
      output: (value['output'] as String?) ?? '',
      launched: value['launched'] as bool? ?? false,
      timedOut: value['timedOut'] as bool? ?? false,
      exitCode: value['exitCode'] as int?,
      failure: value['failure'] as String?,
    );
  }
}
