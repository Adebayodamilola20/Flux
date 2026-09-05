import 'package:flutter/material.dart';

/// The DevNotch icon.
///
/// The same artwork the app is signed with and the Dock shows, so the mark
/// the user clicked to launch it is the mark they meet inside it — and the
/// one macOS puts on the Keychain prompt when DevNotch asks to read Claude
/// Code's stored session.
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      // The artwork carries its own rounded corners; this only stops the
      // bitmap's edge showing square against a light panel.
      borderRadius: BorderRadius.circular(size * 0.2237),
      child: Image.asset(
        'assets/brand/devnotch-mark-512.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        // Decoded at the size it is drawn, rather than at 512 square.
        cacheWidth: (size * 3).round(),
      ),
    );
  }
}
