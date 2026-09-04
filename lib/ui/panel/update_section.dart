import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/formatting.dart';
import '../../services/native/native_bridge.dart';
import '../../services/update_checker.dart';
import '../theme/app_theme.dart';
import '../widgets/pill_button.dart';
import '../widgets/settings_controls.dart';

/// The version installed, whether a newer one exists, and the way to get it.
///
/// Lives on the About page, which is where people look for a version number.
/// When an update is out the row says so and offers the download; the app
/// does not replace itself (see [UpdateChecker] for why).
class UpdateSection extends StatelessWidget {
  const UpdateSection({super.key, required this.version});

  /// The marketing version, e.g. `1.0.0`.
  final String version;

  @override
  Widget build(BuildContext context) {
    final checker = context.watch<UpdateChecker>();
    final palette = context.palette;
    final update = checker.available;

    return SettingsSection(
      title: 'Software update',
      footnote: _footnote(checker),
      children: [
        SettingsRow(
          label: update == null
              ? 'DevNotch $version'
              : 'DevNotch ${update.version} is available',
          description: update == null
              ? _installedLine(checker.installedBuild)
              : (update.notes ?? 'Download the new build to update.'),
          control: update == null
              ? PillButton(
                  label: checker.isChecking ? 'Checking…' : 'Check for updates',
                  onPressed: checker.isChecking ? null : () => checker.check(),
                )
              : PillButton(
                  label: 'Download',
                  emphasised: true,
                  onPressed: () =>
                      context.read<NativeBridge>().openUrl(update.downloadUrl),
                ),
        ),
        if (update != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Quit DevNotch, open the disk image and drag the new copy over '
              'the old one in Applications. Your slots and settings stay.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: palette.textSecondary,
              ),
            ),
          ),
      ],
    );
  }

  static String _installedLine(String build) {
    if (!UpdateInfo.isBuildStamp(build)) return 'Development build.';
    final stamp = DateTime.utc(
      int.parse(build.substring(0, 4)),
      int.parse(build.substring(4, 6)),
      int.parse(build.substring(6, 8)),
      int.parse(build.substring(8, 10)),
      int.parse(build.substring(10, 12)),
    ).toLocal();
    return 'Build from ${DateFormat('d MMM yyyy, h:mm a').format(stamp)}.';
  }

  static String? _footnote(UpdateChecker checker) {
    final error = checker.lastError;
    if (error != null) return error;
    final at = checker.lastChecked;
    if (at == null) return 'Checks once after launch and every few hours.';
    return 'Last checked ${Format.relativeTime(at)}.';
  }
}
