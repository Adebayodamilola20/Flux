import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/usage_provider.dart';
import '../../services/shell_controller.dart';
import '../../services/usage_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/provider_glyph.dart';
import 'panel_chrome.dart';

/// Chooses which provider fills an empty rail position.
///
/// The rail starts empty and every position is interchangeable, so this is the
/// only place a provider gets onto it. Picking one connects it there and then:
/// these providers read a tool already signed in on this Mac, so a Connect
/// button behind this list would ask the user to confirm something the app can
/// simply do.
class SlotPickerView extends StatelessWidget {
  const SlotPickerView({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final shell = context.watch<ShellController>();
    final usage = context.watch<UsageController>();

    final slotIndex = shell.slotIndex ?? 0;
    final available = usage.unassigned;

    return PanelChrome(
      title: 'Add to slot ${slotIndex + 1}',
      subtitle: available.isEmpty
          ? 'Everything this build supports is already on your rail.'
          : 'Pick what belongs here. Any app can go in any position.',
      onClose: shell.showRail,
      child: available.isEmpty
          ? _NothingLeft(palette: palette)
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: available.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final state = available[i];
                return _ProviderChoice(
                  descriptor: state.descriptor,
                  onTap: () async {
                    await usage.assignSlot(slotIndex, state.id);
                    await shell.showRail();
                  },
                );
              },
            ),
    );
  }
}

class _ProviderChoice extends StatefulWidget {
  const _ProviderChoice({required this.descriptor, required this.onTap});

  final ProviderDescriptor descriptor;
  final Future<void> Function() onTap;

  @override
  State<_ProviderChoice> createState() => _ProviderChoiceState();
}

class _ProviderChoiceState extends State<_ProviderChoice> {
  bool _hovered = false;
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = Color(widget.descriptor.accent);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _working
            ? null
            : () async {
                setState(() => _working = true);
                await widget.onTap();
                if (mounted) setState(() => _working = false);
              },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMetrics.fadeAnimation,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered
                  ? accent.withValues(alpha: 0.5)
                  : palette.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: ProviderGlyph(
                    providerId: widget.descriptor.id,
                    color: accent,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.descriptor.displayName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.descriptor.tagline,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: palette.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (_working)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: palette.textTertiary,
                  ),
                )
              else
                Icon(
                  Icons.add_rounded,
                  size: 17,
                  color: _hovered ? accent : palette.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NothingLeft extends StatelessWidget {
  const _NothingLeft({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Remove one from the rail first, or add support for another tool.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: palette.textTertiary,
        ),
      ),
    );
  }
}
