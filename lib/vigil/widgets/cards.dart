import 'package:flutter/material.dart';

import '../theme/vigil_tokens.dart';
import 'hud.dart';

/// Base card: surface fill, 1 px line border, square corners.
/// [brackets] adds the HUD corner brackets (hero + intel cards only).
class VigilCard extends StatelessWidget {
  const VigilCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.brackets = false,
    this.bracketColor,
    this.borderColor,
    this.color,
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool brackets;
  final Color? bracketColor;
  final Color? borderColor;
  final Color? color;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    Widget card = Material(
      color: color ?? c.surface,
      shape: VigilShapes.square(BorderSide(color: borderColor ?? c.line)),
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
    if (brackets) card = CornerBrackets(color: bracketColor, child: card);
    if (semanticLabel != null || onTap != null) {
      card = Semantics(container: true, button: onTap != null, label: semanticLabel, child: card);
    }
    return card;
  }
}

/// UPPERCASE mono section label with an optional trailing label.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.color, this.trailingColor});

  final String text;
  final String? trailing;
  final Color? color;
  final Color? trailingColor;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    return Semantics(
      header: true,
      child: Row(
        children: <Widget>[
          Expanded(child: Text(text.toUpperCase(), style: t.label.copyWith(color: color ?? c.textFaint))),
          if (trailing != null)
            Text(trailing!.toUpperCase(), style: t.meta.copyWith(color: trailingColor ?? c.textMuted)),
        ],
      ),
    );
  }
}

enum IntelTone { normal, alert }

/// "VIGIL // INTEL" card: tag, timestamp, one-sentence message, up to two actions.
class IntelCard extends StatelessWidget {
  const IntelCard({
    super.key,
    required this.message,
    this.tag = 'VIGIL // INTEL',
    this.time,
    this.actions = const <Widget>[],
    this.tone = IntelTone.normal,
  });

  final String message;
  final String tag;
  final String? time;
  final List<Widget> actions;
  final IntelTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final Color tagColor = tone == IntelTone.alert ? c.critical : c.signal;
    return VigilCard(
      brackets: true,
      bracketColor: tagColor,
      borderColor: c.lineStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(tag.toUpperCase(), style: t.label.copyWith(color: tagColor))),
              if (time != null) Text(time!, style: t.meta.copyWith(color: c.textFaint)),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(liveRegion: true, child: Text(message, style: t.body)),
          if (actions.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    );
  }
}

/// Small metric tile: label, big value, optional caption.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.caption, this.valueColor, this.onTap});

  final String label;
  final String value;
  final String? caption;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    return VigilCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      semanticLabel: '$label $value${caption != null ? ', $caption' : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label.toUpperCase(), style: t.micro.copyWith(color: c.textFaint, letterSpacing: 1.4)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, maxLines: 1, style: t.metric.copyWith(color: valueColor ?? c.text)),
          ),
          if (caption != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(caption!.toUpperCase(), style: t.meta.copyWith(color: c.textMuted)),
          ],
        ],
      ),
    );
  }
}

/// Label + value over a 4 px progress bar (Command readiness stats).
class StatBar extends StatelessWidget {
  const StatBar({super.key, required this.label, required this.value, required this.fraction, this.color, this.thickness = 4});

  final String label;
  final String value;
  final double fraction;
  final Color? color;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    return Semantics(
      label: '$label $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(label.toUpperCase(), style: t.meta.copyWith(color: c.textFaint, letterSpacing: 1.3))),
              Text(value, style: t.meta.copyWith(color: c.text, fontWeight: FontWeight.w500, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 5),
          SegmentBar(fraction: fraction, color: color ?? c.signal, thickness: thickness),
        ],
      ),
    );
  }
}

/// Flat progress bar with optional marker (budget pace, limits).
class SegmentBar extends StatelessWidget {
  const SegmentBar({
    super.key,
    required this.fraction,
    this.color,
    this.trackColor,
    this.thickness = 4,
    this.marker,
    this.markerColor,
  });

  final double fraction;
  final Color? color;
  final Color? trackColor;
  final double thickness;

  /// 0–1 position of a 2 px vertical marker that overhangs the bar by 4 px.
  final double? marker;
  final Color? markerColor;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    return SizedBox(
      height: thickness + (marker != null ? 8 : 0),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final double w = box.maxWidth;
          final double top = marker != null ? 4 : 0;
          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned(left: 0, right: 0, top: top, height: thickness, child: ColoredBox(color: trackColor ?? c.line)),
              Positioned(
                left: 0,
                top: top,
                height: thickness,
                width: w * fraction.clamp(0.0, 1.0),
                child: ColoredBox(color: color ?? c.signal),
              ),
              if (marker != null)
                Positioned(
                  left: (w * marker!.clamp(0.0, 1.0)) - 1,
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: ColoredBox(color: markerColor ?? c.text),
                ),
            ],
          );
        },
      ),
    );
  }
}
