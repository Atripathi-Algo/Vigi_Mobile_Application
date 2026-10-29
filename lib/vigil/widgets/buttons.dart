import 'package:flutter/material.dart';

import '../theme/vigil_colors.dart';
import '../theme/vigil_tokens.dart';
import 'hud.dart';
import 'vigil_icon.dart';
import '../../services/haptics.dart';

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
  /// 38 dp pill, for tight spots (diff chips, inline actions).
  small,

  /// 48 dp pill, Inter 13.5 label.
  regular,

  /// 54 dp pill, Sora 16 label (setup, full-width actions).
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
    final bool small = size == VigilButtonSize.small;
    final bool enabled = onPressed != null;

    final (Color bg, Color fg, BorderSide side) = switch (variant) {
      VigilButtonVariant.primary => (Colors.transparent, c.onSignal, BorderSide.none),
      VigilButtonVariant.critical => (Colors.transparent, c.onSignal, BorderSide.none),
      VigilButtonVariant.secondary => (c.surface, c.text, BorderSide(color: c.lineStrong)),
      VigilButtonVariant.accent => (Colors.transparent, c.signal2, BorderSide(color: c.signal2)),
      VigilButtonVariant.ghost => (Colors.transparent, c.signal2, BorderSide.none),
    };
    final bool filled = variant == VigilButtonVariant.primary || variant == VigilButtonVariant.critical;
    final OutlinedBorder shape = VigilShapes.pill(side);
    final TextStyle style = (large ? t.cta : t.button).copyWith(color: fg);
    final Gradient? gradient = switch (variant) {
      VigilButtonVariant.primary => KGradients.primary,
      VigilButtonVariant.critical => KGradients.destructive,
      _ => null,
    };

    final Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          VigilIcon(icon!, size: large ? 20 : 16, color: fg),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(label, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );

    Widget button = Material(
      color: bg,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      shadowColor: Colors.transparent,
      child: Ink(
        decoration: ShapeDecoration(gradient: gradient, shape: shape, shadows: filled && enabled ? c.actionShadow : null),
        child: InkWell(
        onTap: enabled
            ? () {
                Haptics.tick();
                onPressed!();
              }
            : null,
        customBorder: shape,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: large ? VigilSize.buttonLarge : (small ? VigilSize.buttonSmall : VigilSize.button),
            minWidth: small ? 0 : VigilSize.touch,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: large ? 24 : 20),
            child: Center(widthFactor: expand ? null : 1, child: content),
          ),
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

/// 48 × 48 rounded icon button with a line border on the card colour (header actions).
class VigilIconButton extends StatelessWidget {
  const VigilIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.badge = false,
    this.size = 48,
  });

  final VigilIcons icon;
  final VoidCallback? onPressed;
  final String semanticLabel;

  /// Small magenta dot in the top-right (unread alerts).
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
        shape: VigilShapes.field(BorderSide(color: c.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: size,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                VigilIcon(icon, size: 20, color: c.text),
                if (badge)
                  Positioned(top: 11, right: 12, child: DecoratedBox(decoration: BoxDecoration(color: c.magenta, shape: BoxShape.circle), child: const SizedBox.square(dimension: 8))),
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
        color: color ?? Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: ShapeDecoration(gradient: color == null ? KGradients.primary : null, shape: shape, shadows: onPressed == null ? null : c.actionShadow),
          child: InkWell(
          customBorder: shape,
          onTap: onPressed == null
              ? null
              : () {
                  Haptics.tap();
                  onPressed!();
                },
          child: SizedBox.square(
            dimension: size,
            child: Center(child: child ?? VigilIcon(VigilIcons.plus, size: 24, color: c.onSignal)),
          ),
        ),
        ),
      ),
    );
  }
}

/// A round gradient action button (send, mic). The K octagon stays the one hard shape.
class CircleButton extends StatelessWidget {
  const CircleButton({super.key, required this.onPressed, required this.semanticLabel, required this.child, this.size = 52});

  final VoidCallback? onPressed;
  final String semanticLabel;
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: ShapeDecoration(gradient: KGradients.primary, shape: const CircleBorder(), shadows: c.actionShadow),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed == null
                ? null
                : () {
                    Haptics.tap();
                    onPressed!();
                  },
            child: SizedBox.square(dimension: size, child: Center(child: child)),
          ),
        ),
      ),
    );
  }
}

/// The K button content: the white K mark on the gradient octagon.
class CoreEmblem extends StatelessWidget {
  const CoreEmblem({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    return VigilEmblem(size: 32, outline: c.onSignal, visor: c.onSignal, showPupil: false, semanticLabel: null);
  }
}
