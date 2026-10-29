import 'package:flutter/material.dart';

import '../theme/vigil_colors.dart';
import '../theme/vigil_tokens.dart';
import 'vigil_icon.dart';
import '../../services/haptics.dart';

/// Threat levels used across objectives, alerts and capture.
enum Threat { crit, high, routine }

/// Threat tag: a diamond and CRIT / HIGH / ROUTINE, in a pill. Never colour alone.
class ThreatTag extends StatelessWidget {
  const ThreatTag(this.threat, {super.key, this.width});

  final Threat threat;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final (Color bg, Color fg, Color bd, String label, String spoken) = switch (threat) {
      Threat.crit => (c.critical.withValues(alpha: 0.12), c.critical, c.critical.withValues(alpha: 0.4), 'Urgent', 'urgent'),
      Threat.high => (c.warning.withValues(alpha: 0.12), c.warning, c.warning.withValues(alpha: 0.4), 'High', 'high'),
      Threat.routine => (Colors.transparent, c.textMuted, c.lineStrong, 'Normal', 'normal'),
    };
    return Semantics(
      label: 'Priority $spoken',
      excludeSemantics: true,
      child: Container(
        height: 22,
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, border: Border.all(color: bd), borderRadius: BorderRadius.circular(KRadius.pill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Transform.rotate(angle: 0.785398, child: SizedBox.square(dimension: 6, child: ColoredBox(color: fg))),
          const SizedBox(width: 5),
          Text(label, style: t.micro.copyWith(color: fg, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        ]),
      ),
    );
  }
}

/// Checkbox: 22 dp box, radius 7, inside a 48 dp hit area. Done = gradient fill and a white check.
class VigilCheckbox extends StatelessWidget {
  const VigilCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    this.critical = false,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;

  /// Unchecked border turns critical (CRIT objectives, at-risk protocols).
  final bool critical;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final Color border = value ? Colors.transparent : (critical ? c.critical : c.lineStrong);
    return Semantics(
      checked: value,
      enabled: onChanged != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkResponse(
        radius: 22,
        onTap: onChanged == null
            ? null
            : () {
                Haptics.tick();
                onChanged!(!value);
              },
        child: SizedBox.square(
          dimension: VigilSize.touch,
          child: Center(
            child: AnimatedContainer(
              duration: VigilMotion.fast,
              curve: VigilMotion.curve,
              width: VigilSize.checkbox,
              height: VigilSize.checkbox,
              decoration: BoxDecoration(
                gradient: value ? KGradients.primary : null,
                borderRadius: BorderRadius.circular(KRadius.checkbox),
                border: Border.all(color: border, width: 1.5),
              ),
              child: value ? CustomPaint(painter: _CheckPainter(c.onSignal)) : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width / 24;
    final Path p = Path()
      ..moveTo(5 * s, 12 * s)
      ..lineTo(10 * s, 17 * s)
      ..lineTo(19 * s, 7 * s);
    canvas.drawPath(
      p,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.color != color;
}

/// Switch: 50 × 30 pill. On = gradient track and a white knob.
class VigilSwitch extends StatelessWidget {
  const VigilSwitch({super.key, required this.value, required this.onChanged, required this.semanticLabel});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null
            ? null
            : () {
                Haptics.tick();
                onChanged!(!value);
              },
        child: SizedBox(
          width: 58,
          height: VigilSize.touch,
          child: Center(
            child: AnimatedContainer(
              duration: VigilMotion.fast,
              curve: VigilMotion.curve,
              width: 50,
              height: 30,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                gradient: value ? KGradients.primary : null,
                color: value ? null : c.surfaceHigh,
                border: Border.all(color: value ? Colors.transparent : c.lineStrong),
                borderRadius: BorderRadius.circular(KRadius.pill),
              ),
              child: AnimatedAlign(
                duration: VigilMotion.fast,
                curve: VigilMotion.curve,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: SizedBox.square(
                  dimension: 22,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: value ? Colors.white : c.textFaint,
                      shape: BoxShape.circle,
                      boxShadow: value ? const <BoxShadow>[BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1))] : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Two- to four-way view switch under a screen title (Tasks | Timeline).
/// Pill track; the selected segment fills with the primary gradient.
class VigilSegmented<T> extends StatelessWidget {
  const VigilSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelected,
  });

  final List<(T, String)> segments;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.surfaceHigh, borderRadius: BorderRadius.circular(KRadius.pill), border: Border.all(color: c.line)),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
        children: <Widget>[
          for (final (T value, String label) in segments)
            Expanded(
              child: Semantics(
                selected: value == selected,
                button: true,
                label: label,
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(KRadius.pill),
                  onTap: () => onSelected(value),
                  child: AnimatedContainer(
                    duration: VigilMotion.fast,
                    height: VigilSize.button - 6,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: value == selected ? KGradients.primary : null,
                      borderRadius: BorderRadius.circular(KRadius.pill),
                      boxShadow: value == selected ? c.actionShadow : null,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.button.copyWith(color: value == selected ? c.onSignal : c.textMuted),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Filter chip (All, Work, Home). 32 dp pill inside a 48 dp hit area; selected = soft gradient and a violet edge.
class VigilFilterChip extends StatelessWidget {
  const VigilFilterChip({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              gradient: selected ? c.softGradient : null,
              color: selected ? null : c.surface,
              border: Border.all(color: selected ? c.violet : c.lineStrong),
              borderRadius: BorderRadius.circular(KRadius.pill),
            ),
            child: Center(widthFactor: 1, child: Text(label, style: t.button.copyWith(fontSize: 12.5, fontWeight: FontWeight.w500, color: selected ? c.text : c.textMuted))),
          ),
        ),
      ),
    );
  }
}

/// Key | value chip used for VIGIL-parsed capture fields (WHEN | FRI 23 OCT · 18:00).
class ParsedChip extends StatelessWidget {
  const ParsedChip({super.key, required this.keyLabel, required this.value, this.uncertain = false, this.onTap});

  final String keyLabel;
  final String value;

  /// Amber outline when the rules parser and the model disagree.
  final bool uncertain;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final Color bd = uncertain ? c.signal : c.lineStrong;
    return Semantics(
      label: '$keyLabel: $value${uncertain ? ', please confirm' : ''}',
      button: onTap != null,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 32,
          decoration: BoxDecoration(border: Border.all(color: bd), borderRadius: BorderRadius.circular(KRadius.pill)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(border: Border(right: BorderSide(color: bd))),
                child: Text(keyLabel, style: t.meta.copyWith(color: c.textMuted)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(value, style: t.meta.copyWith(color: c.text)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// − value + stepper (sleep need, bed/wake ±15). Buttons are 44 × 44.
class VigilStepper extends StatelessWidget {
  const VigilStepper({
    super.key,
    required this.valueLabel,
    required this.onDecrement,
    required this.onIncrement,
    required this.semanticName,
    this.valueWidth = 76,
  });

  final String valueLabel;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;
  final String semanticName;
  final double valueWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    Widget btn(VigilIcons icon, VoidCallback? onTap, String label) => Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: InkWell(
            onTap: onTap,
            child: Container(
              width: VigilSize.touch,
              height: VigilSize.touch,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border.all(color: c.lineStrong), borderRadius: BorderRadius.circular(KRadius.field), color: c.surface),
              child: VigilIcon(icon, size: 16, color: c.text),
            ),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        btn(VigilIcons.minus, onDecrement, 'Decrease $semanticName'),
        SizedBox(
          width: valueWidth,
          child: Semantics(
            liveRegion: true,
            label: '$semanticName $valueLabel',
            excludeSemantics: true,
            child: Text(valueLabel, textAlign: TextAlign.center, style: t.metric),
          ),
        ),
        btn(VigilIcons.plus, onIncrement, 'Increase $semanticName'),
      ],
    );
  }
}
