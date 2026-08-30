/// A provider-related process or session currently active on this machine.
///
/// Only what is needed to name the session is collected: the process, the
/// terminal hosting it, and its working directory. Terminal contents are never
/// read.
class ActiveSession {
  const ActiveSession({
    required this.title,
    this.host,
    this.command,
    this.pid,
    this.lastActivity,
    this.isBusy = false,
  });

  /// Primary label — typically the project or workspace name.
  final String title;

  /// Where it is running: "Terminal", "iTerm2", "VS Code"…
  final String? host;

  /// The tool that is running, as the user would name it ("Claude Code").
  final String? command;

  /// Process identifier, when the session was found by scanning processes.
  final int? pid;

  /// Timestamp of the most recent observed activity.
  final DateTime? lastActivity;

  /// True while the session appears to be actively working.
  final bool isBusy;

  /// Secondary line for the UI: "Terminal · my-project".
  String subtitle(String fallback) {
    final h = host;
    if (h == null || h.isEmpty) return fallback;
    return '$h · $fallback';
  }

  ActiveSession copyWith({
    String? title,
    String? host,
    String? command,
    int? pid,
    DateTime? lastActivity,
    bool? isBusy,
  }) {
    return ActiveSession(
      title: title ?? this.title,
      host: host ?? this.host,
      command: command ?? this.command,
      pid: pid ?? this.pid,
      lastActivity: lastActivity ?? this.lastActivity,
      isBusy: isBusy ?? this.isBusy,
    );
  }

  @override
  String toString() => 'ActiveSession($title, host: $host, busy: $isBusy)';

  @override
  bool operator ==(Object other) =>
      other is ActiveSession &&
      other.title == title &&
      other.host == host &&
      other.command == command &&
      other.pid == pid &&
      other.lastActivity == lastActivity &&
      other.isBusy == isBusy;

  @override
  int get hashCode =>
      Object.hash(title, host, command, pid, lastActivity, isBusy);
}
