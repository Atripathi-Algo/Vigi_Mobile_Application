import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../vigil/vigil.dart';
import 'providers.dart';

/// Bottom padding that clears the tab bar and the raised core button.
/// Under the shell's `extendBody`, the body's bottom padding already equals the
/// full nav-bar height (bar + raised button + inset), so only add breathing room.
double tabBottomPad(BuildContext context) => math.max(MediaQuery.paddingOf(context).bottom, VigilSize.navBar + VigilSize.coreLift + VigilSize.navMinInset) + 24;

extension WidgetRefNow on WidgetRef {
  DateTime get now => watch(clockProvider).value ?? DateTime.now();
}

void showVigilSnack(BuildContext context, String message, {String? action, VoidCallback? onAction}) {
  final ScaffoldMessengerState m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    // The snackbar is dark in both themes, so its text is always light.
    content: Text(message, style: context.vtype.body.copyWith(color: const Color(0xFFF1F2FF), fontSize: 13.5)),
    duration: const Duration(seconds: 4),
    // A snackbar with an action stays until dismissed unless told not to (Flutter 3.29+): these are short notices.
    persist: false,
    action: action == null ? null : SnackBarAction(label: action, textColor: VigilPalette.signal2, onPressed: onAction ?? () {}),
  ));
}

/// Group label with an 8 px square (Objectives, Protocols).
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.text, {super.key, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(children: <Widget>[
        SizedBox(width: 8, height: 8, child: ColoredBox(color: color)),
        const SizedBox(width: 8),
        Text(text, style: context.vtype.label.copyWith(color: color)),
      ]),
    );
  }
}

/// One card holding rows split by 1 px rules (handoff 9.7).
class RowList extends StatelessWidget {
  const RowList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    return VigilCard(
      padding: EdgeInsets.zero,
      child: Column(children: <Widget>[
        for (int i = 0; i < children.length; i++) ...<Widget>[
          if (i > 0) Divider(height: 1, color: c.line),
          children[i],
        ],
      ]),
    );
  }
}

/// Centered empty state: emblem + line + optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.action, this.onAction});

  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        const VigilEmblem(size: 40, semanticLabel: ''),
        const SizedBox(height: 14),
        Text(message, style: context.vtype.body.copyWith(color: context.vigil.textMuted), textAlign: TextAlign.center),
        if (action != null) ...<Widget>[
          const SizedBox(height: 16),
          VigilButton(label: action!, onPressed: onAction),
        ],
      ]),
    );
  }
}

/// Small colored status chip with a 6 px square (LINKED / ON / ASK).
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.on = false, this.color});

  final String label;
  final bool on;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final Color col = color ?? (on ? c.signal : c.textMuted);
    return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
      SizedBox(width: 6, height: 6, child: ColoredBox(color: col)),
      const SizedBox(width: 6),
      Text(label, style: context.vtype.meta.copyWith(color: col)),
    ]);
  }
}

/// Segmented view switch that navigates between sibling routes.
class RouteSegmented extends StatelessWidget {
  const RouteSegmented({super.key, required this.segments, required this.current, required this.onSelected});

  final List<(String, String)> segments;
  final String current;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return VigilSegmented<String>(segments: segments, selected: current, onSelected: onSelected);
  }
}

/// Wraps screens that need a store: `ConsumerWidget` helper.
typedef StoreBuilder = Widget Function(BuildContext context, WidgetRef ref, dynamic store);

/// Bordered mono text-field used across screens (48 high, hidden or external label).
class VigilField extends StatelessWidget {
  const VigilField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.semanticLabel,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
    this.prefix,
    this.height = VigilSize.input,
    this.autofocus = false,
    this.fillColor,
    this.focusNode,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final String? semanticLabel;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int maxLines;
  final Widget? prefix;
  final double height;
  final bool autofocus;
  final Color? fillColor;
  final FocusNode? focusNode;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final Widget field = Semantics(
      label: semanticLabel ?? label ?? hint,
      textField: true,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        maxLines: obscure ? 1 : maxLines,
        obscureText: obscure,
        keyboardType: keyboardType,
        autocorrect: !obscure,
        enableSuggestions: !obscure,
        style: t.body,
        cursorColor: c.signal,
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          prefixIcon: prefix,
          suffixIcon: suffix,
          fillColor: fillColor,
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: maxLines > 1 ? 12 : (height - 22) / 2),
        ),
      ),
    );
    if (label == null) return field;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text(label!, style: t.label.copyWith(color: c.textFaint)),
      const SizedBox(height: 6),
      field,
    ]);
  }
}

Future<TimeOfDay?> pickVigilTime(BuildContext context, int minutes) {
  return showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: (minutes ~/ 60) % 24, minute: minutes % 60),
    builder: (BuildContext ctx, Widget? child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  );
}
