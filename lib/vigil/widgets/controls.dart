import 'package:flutter/material.dart';

import '../theme/vigil_tokens.dart';
import 'vigil_icon.dart';
import '../../services/haptics.dart';

/// Threat levels used across objectives, alerts and capture.
enum Threat { crit, high, routine }

/// CRIT (critical fill) · HIGH (signal outline) · ROUTINE (neutral outline).
class ThreatTag extends StatelessWidget {
  const ThreatTag(this.threat, {super.key, this.width});

  final Threat threat;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final (Color bg, Color fg, Color bd, String label, String spoken) = switch (threat) {
      Threat.crit => (c.critical, c.onSignal, c.critical, 'CRIT', 'critical'),
      Threat.high => (Colors.transparent, c.signal, c.signal, 'HIGH', 'high'),
      Threat.routine => (Colors.transparent, c.textMuted, c.neutral, 'ROUTINE', 'routine'),
    };
    return Semantics(
      label: 'Threat level $spoken',
      excludeSemantics: true,
      child: Container(
        height: 22,
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, border: Border.all(color: bd)),
        child: Text(label, style: t.micro.copyWith(color: fg, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// Square checkbox: 20 px box inside a 44 px hit area.
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
    final Color border = value ? c.signal : (critical ? c.critical : c.neutral);
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
                color: value ? c.signal : Colors.transparent,
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
        ..strokeJoin = StrokeJoin.miter,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.color != color;
}

/// Square switch: 44 × 24 track, 16 px square knob, inside a 52 × 44 hit area.
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
          width: 52,
          height: VigilSize.touch,
          child: Center(
            child: AnimatedContainer(
              duration: VigilMotion.fast,
              curve: VigilMotion.curve,
              width: 44,
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: value ? c.signalTint(0.15) : Colors.transparent,
                border: Border.all(color: value ? c.signal : c.neutral),
              ),
              child: AnimatedAlign(
                duration: VigilMotion.fast,
                curve: VigilMotion.curve,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: SizedBox.square(
                  dimension: 16,
                  child: ColoredBox(color: value ? c.signal : c.textFaint),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Two- or three-way view switch under a screen title (OBJECTIVES | TIMELINE).
/// The selected segment fills with signal.
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
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(border: Border.all(color: c.lineStrong)),
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
                  onTap: () => onSelected(value),
                  child: AnimatedContainer(
                    duration: VigilMotion.fast,
                    height: VigilSize.button,
                    alignment: Alignment.center,
                    color: value == selected ? c.signal : Colors.transparent,
                    child: Text(
                      label.toUpperCase(),
                      style: t.button.copyWith(
                        color: value == selected ? c.onSignal : c.textMuted,
                        fontWeight: value == selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Filter chip (ALL · WORK · HOME…). 44 px tall; selected = text-colour outline.
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
        child: Container(
          height: VigilSize.button,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(border: Border.all(color: selected ? c.text : c.lineStrong)),
          child: Text(label.toUpperCase(), style: t.button.copyWith(color: selected ? c.text : c.textMuted, fontWeight: FontWeight.w400)),
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
          decoration: BoxDecoration(border: Border.all(color: bd)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(border: Border(right: BorderSide(color: bd))),
                child: Text(keyLabel.toUpperCase(), style: t.meta.copyWith(color: c.textFaint)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(value.toUpperCase(), style: t.meta.copyWith(color: c.text)),
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
              decoration: BoxDecoration(border: Border.all(color: c.lineStrong)),
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
