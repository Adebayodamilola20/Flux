import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/settings_service.dart';
import '../../services/shell_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/pill_button.dart';

/// First run, before the widget has ever been on screen.
///
/// Two pages and no decisions. The rail is arranged by filling empty slots, so
/// anything asked here would be asked again in a better place — the job is to
/// say what the thing is and what an empty slot is for, then get out of the
/// way. Settings opens behind it, which is where the arranging happens.
class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key});

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  int _page = 0;

  Future<void> _finish() async {
    final settingsService = context.read<SettingsService>();
    final shell = context.read<ShellController>();

    await settingsService.update(
      settingsService.settings.copyWith(onboardingComplete: true),
    );
    await shell.openPanel(ShellSurface.settings);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.all(18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(AppMetrics.cardRadius + 2),
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 34, 30, 26),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.06, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: _page == 0
                ? _WelcomePage(
                    key: const ValueKey('onboarding-welcome'),
                    onStart: () => setState(() => _page = 1),
                  )
                : _SlotsPage(
                    key: const ValueKey('onboarding-slots'),
                    onNext: _finish,
                  ),
          ),
        ),
      ),
    );
  }
}

/// The name, and one button.
class _WelcomePage extends StatelessWidget {
  const _WelcomePage({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Wordmark(),
        const Spacer(),
        Text(
          'Your AI usage,\nat the edge of the screen.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 21,
            height: 1.3,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'No sign-in. It reads the tools already '
          'authenticated on this Mac.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: palette.textTertiary,
          ),
        ),
        const Spacer(),
        Center(
          child: PillButton(
            label: 'Start',
            emphasised: true,
            onPressed: onStart,
          ),
        ),
      ],
    );
  }
}

/// What a slot is, and how one gets filled.
class _SlotsPage extends StatelessWidget {
  const _SlotsPage({super.key, required this.onNext});

  final Future<void> Function() onNext;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Wordmark(),
        const Spacer(),
        const Center(child: _SlotIllustration()),
        const SizedBox(height: 28),
        Text(
          'Three slots. Fill them yourself.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 19,
            height: 1.3,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'The rail starts empty. Click a plus, pick a tool, '
          'and its usage appears as a ring you can read from '
          'across the room.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: palette.textTertiary,
          ),
        ),
        const Spacer(),
        Center(
          child: PillButton(label: 'Next', emphasised: true, onPressed: onNext),
        ),
      ],
    );
  }
}

/// The product name, set as a mark rather than as a heading.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Dev',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w300,
            letterSpacing: -0.6,
            color: palette.textSecondary,
          ),
        ),
        Text(
          'Notch',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: palette.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// The rail with one slot filled and two waiting.
///
/// Drawn rather than shipped as an asset so it follows the theme, and so it
/// stays true to the rail's real proportions if those change — the point of
/// the page is that the plus is the thing to click.
class _SlotIllustration extends StatelessWidget {
  const _SlotIllustration();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: 250,
      height: 190,
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Stack(
        children: [
          // The screen edge the rail sits against.
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: Container(width: 3, color: palette.border),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            right: 3,
            child: Center(
              child: Container(
                width: 62,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(18),
                  ),
                  border: Border.all(color: palette.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _FilledSlot(color: palette.accentNormal),
                    const SizedBox(height: 12),
                    const _EmptySlotMark(),
                    const SizedBox(height: 12),
                    const _EmptySlotMark(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A slot in use: a ring with a figure under it.
class _FilledSlot extends StatelessWidget {
  const _FilledSlot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            value: 0.62,
            strokeWidth: 3,
            backgroundColor: palette.track,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '62%',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// An empty slot: the plus the page is pointing at.
class _EmptySlotMark extends StatelessWidget {
  const _EmptySlotMark();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: palette.textTertiary, width: 1.4),
      ),
      child: Icon(Icons.add_rounded, size: 15, color: palette.textTertiary),
    );
  }
}
