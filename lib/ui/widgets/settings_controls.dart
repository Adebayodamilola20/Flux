import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One group of settings, drawn the way macOS System Settings draws them.
///
/// The shape matters more than it sounds. macOS groups controls into an inset
/// rounded card with the heading *outside* it, above and to the left, and
/// hairline dividers between rows that stop short of the left edge. Explanatory
/// text sits below the card, not inside. Anything else — a flat list, a heading
/// inside the box, full-width rules — reads as an app that drew its own idea of
/// a settings screen, which is exactly what this replaced.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.children,
    this.title,
    this.footnote,
    this.trailing,
  });

  /// Heading above the card. Sentence case, as macOS uses.
  final String? title;

  final List<Widget> children;

  /// Explanatory text below the card.
  final String? footnote;

  /// Optional status shown at the right of the heading, e.g. a badge.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title!,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: palette.textSecondary,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ],
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Padding(
                    // Inset from the left only, the way macOS insets a
                    // separator to line up with the label above it.
                    padding: const EdgeInsets.only(left: 14),
                    child: Container(height: 1, color: palette.divider),
                  ),
                children[i],
              ],
            ],
          ),
        ),
        if (footnote != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6),
            child: Text(
              footnote!,
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: palette.textTertiary,
                letterSpacing: -0.05,
              ),
            ),
          ),
      ],
    );
  }
}

/// A label and its control, as one row inside a [SettingsSection].
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    this.control,
    this.description,
    this.below,
  });

  final String label;

  /// Trailing control. Null for a row that is only a label and a description.
  final Widget? control;

  final String? description;

  /// A control that needs the full width — a slider, say — placed under the
  /// label rather than squeezed against the right edge.
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        color: palette.textPrimary,
                        letterSpacing: -0.1,
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        description!,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: palette.textTertiary,
                          letterSpacing: -0.05,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (control != null) ...[
                const SizedBox(width: 12),
                control!,
              ],
            ],
          ),
          if (below != null) ...[
            const SizedBox(height: 8),
            below!,
          ],
        ],
      ),
    );
  }
}

/// The macOS switch.
///
/// Cupertino rather than Material: the capsule switch on macOS is the same
/// control as on iOS, and Material's rounded-square thumb is unmistakably not
/// it.
class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.8,
      alignment: Alignment.centerRight,
      child: CupertinoSwitch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: context.palette.accentSystem,
      ),
    );
  }
}

/// The macOS segmented control — a pill of options with the selected one
/// filled, as used for System / Custom.
class SettingsSegmented<T> extends StatelessWidget {
  const SettingsSegmented({
    super.key,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  final T value;
  final List<T> items;
  final String Function(T) labelBuilder;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: palette.track,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in items)
            GestureDetector(
              onTap: () => onChanged(item),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                decoration: BoxDecoration(
                  color: item == value
                      ? palette.accentSystem
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  labelBuilder(item),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight:
                        item == value ? FontWeight.w600 : FontWeight.w400,
                    color: item == value
                        ? Colors.white
                        : palette.textSecondary,
                    letterSpacing: -0.05,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A macOS slider with its value shown at the right of the label.
class SettingsSlider extends StatelessWidget {
  const SettingsSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.activeColor,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: activeColor ?? palette.accentSystem,
        inactiveTrackColor: palette.track,
        thumbColor: Colors.white,
        overlayShape: SliderComponentShape.noOverlay,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 1),
        activeTickMarkColor: palette.textTertiary,
        inactiveTickMarkColor: palette.textTertiary,
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
      ),
    );
  }
}

/// A borderless dropdown sized for the settings panel.
class SettingsDropdown<T> extends StatelessWidget {
  const SettingsDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  final T value;
  final List<T> items;
  final String Function(T) labelBuilder;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = TextStyle(
      fontSize: 12.5,
      height: 1.2,
      color: palette.textPrimary,
      letterSpacing: -0.05,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: palette.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          borderRadius: BorderRadius.circular(8),
          dropdownColor: palette.surfaceRaised,
          style: style,
          icon: Icon(
            Icons.unfold_more,
            size: 13,
            color: palette.textTertiary,
          ),
          onChanged: onChanged,
          items: [
            for (final item in items)
              DropdownMenuItem<T>(
                value: item,
                child: Text(labelBuilder(item), style: style),
              ),
          ],
        ),
      ),
    );
  }
}

/// A small status badge, as macOS uses beside a connection heading.
class SettingsBadge extends StatelessWidget {
  const SettingsBadge({super.key, required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tint = color ?? palette.textTertiary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: tint,
          letterSpacing: -0.05,
        ),
      ),
    );
  }
}

/// A single-line text field styled to match the panel.
class SettingsTextField extends StatelessWidget {
  const SettingsTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.obscure = false,
    this.width = 150,
    this.keyboardType,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? hintText;
  final bool obscure;
  final double width;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = TextStyle(
      fontSize: 12.5,
      height: 1.3,
      color: palette.textPrimary,
      letterSpacing: -0.05,
    );

    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: style,
        cursorHeight: 13,
        cursorColor: palette.textPrimary,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText,
          hintStyle: style.copyWith(color: palette.textTertiary),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          filled: true,
          fillColor: palette.surface,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: palette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: palette.accentSystem),
          ),
        ),
      ),
    );
  }
}
