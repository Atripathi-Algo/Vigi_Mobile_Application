import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/vigil_tokens.dart';
import 'hud.dart';
import 'vigil_icon.dart';

enum VigilButtonVariant {
  /// Signal fill, chamfered. One per view.
  primary,

  /// Outline in lineStrong, muted label (SNOOZE, UNDO, ADJUST).
  secondary,

  /// Outline + label in signal (→ FRI, GRANT MIC).
  accent,

  /// Text only.
  ghost,

  /// Critical fill — only for destructive confirmations.
  critical,
}

enum VigilButtonSize {
  /// 44 px, mono 12 label.
  regular,

  /// 54 px, Chakra 16 label, 12 px chamfer (INITIATE, COMMIT, STAND DOWN).
  large,
}

class VigilButton extends StatelessWidget {
  const VigilButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = VigilButtonVariant.primary,
    this.size = VigilButtonSize.regular,
    this.icon,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final VigilButtonVariant variant;
  final VigilButtonSize size;
  final VigilIcons? icon;

  /// Fill the available width.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final bool large = size == VigilButtonSize.large;
    final bool enabled = onPressed != null;

    final (Color bg, Color fg, BorderSide side) = switch (variant) {
      VigilButtonVariant.primary => (c.signal, c.onSignal, BorderSide.none),
      VigilButtonVariant.critical => (c.critical, c.onSignal, BorderSide.none),
      VigilButtonVariant.secondary => (Colors.transparent, c.textMuted, BorderSide(color: c.lineStrong)),
      VigilButtonVariant.accent => (Colors.transparent, c.signal, BorderSide(color: c.signal)),
      VigilButtonVariant.ghost => (Colors.transparent, c.textMuted, BorderSide.none),
    };
    final bool filled = variant == VigilButtonVariant.primary || variant == VigilButtonVariant.critical;
    final OutlinedBorder shape = filled ? VigilShapes.chamfer(large ? 12 : 10) : VigilShapes.square(side);
    final TextStyle style = (large ? t.cta : t.button).copyWith(color: fg);

    final Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          VigilIcon(icon!, size: large ? 20 : 16, color: fg),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(label.toUpperCase(), style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );

    Widget button = Material(
      color: bg,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onPressed!();
              }
            : null,
        customBorder: shape,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: large ? VigilSize.buttonLarge : VigilSize.button,
            minWidth: VigilSize.touch,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: large ? 20 : 16),
            child: Center(widthFactor: expand ? null : 1, child: content),
          ),
        ),
      ),
    );

    if (expand) button = SizedBox(width: double.infinity, child: button);

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Opacity(opacity: enabled ? 1 : 0.4, child: button),
    );
  }
}

/// 44 × 44 square icon button with a line border on surface (header actions).
class VigilIconButton extends StatelessWidget {
  const VigilIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.badge = false,
    this.size = 44,
  });

  final VigilIcons icon;
  final VoidCallback? onPressed;
  final String semanticLabel;

  /// Small critical square in the top-right (unread alerts).
  final bool badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: VigilShapes.square(BorderSide(color: c.line)),
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: size,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                VigilIcon(icon, size: 20, color: c.text),
                if (badge)
                  Positioned(top: 9, right: 10, child: SizedBox.square(dimension: 7, child: ColoredBox(color: c.critical))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Octagonal action button: the FAB (56) and the raised core VIGIL button (58).
class OctagonButton extends StatelessWidget {
  const OctagonButton({
    super.key,
    required this.onPressed,
    required this.semanticLabel,
    this.size = VigilSize.fab,
    this.child,
    this.color,
  });

  final VoidCallback? onPressed;
  final String semanticLabel;
  final double size;
  final Widget? child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final OutlinedBorder shape = VigilShapes.octagon(size);
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: color ?? c.signal,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: shape,
          onTap: onPressed == null
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  onPressed!();
                },
          child: SizedBox.square(
            dimension: size,
            child: Center(child: child ?? VigilIcon(VigilIcons.plus, size: 24, color: c.onSignal)),
          ),
        ),
      ),
    );
  }
}

/// The core VIGIL button content: dark emblem on signal.
class CoreEmblem extends StatelessWidget {
  const CoreEmblem({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    return VigilEmblem(size: 30, outline: c.onSignal, visor: c.onSignal, showPupil: false, semanticLabel: null);
  }
}
