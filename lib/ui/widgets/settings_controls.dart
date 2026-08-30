import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Section heading inside the settings panel.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 9.5,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: palette.textTertiary,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}

/// A label/control row with an optional explanatory second line.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    required this.control,
    this.description,
  });

  final String label;
  final Widget control;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                    color: palette.textPrimary,
                    letterSpacing: -0.1,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    description!,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.3,
                      color: palette.textTertiary,
                      letterSpacing: -0.05,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          control,
        ],
      ),
    );
  }
}

/// A compact switch scaled down to suit the popover's density.
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
    final palette = context.palette;
    return SizedBox(
      height: 20,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: palette.surface,
          activeTrackColor: palette.accentPositive,
          inactiveThumbColor: palette.textSecondary,
          inactiveTrackColor: palette.track,
          trackOutlineColor: WidgetStateProperty.all(palette.border),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
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
      fontSize: 11,
      height: 1.2,
      color: palette.textPrimary,
      letterSpacing: -0.05,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(7),
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
            size: 12,
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

/// A single-line text field styled to match the panel.
class SettingsTextField extends StatelessWidget {
  const SettingsTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.obscure = false,
    this.width = 132,
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
      fontSize: 11,
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
        cursorHeight: 12,
        cursorColor: palette.textPrimary,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText,
          hintStyle: style.copyWith(color: palette.textTertiary),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          filled: true,
          fillColor: palette.surfaceRaised,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide(color: palette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide(color: palette.textSecondary),
          ),
        ),
      ),
    );
  }
}
