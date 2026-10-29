import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/common.dart';
import '../app/fmt.dart';
import '../app/providers.dart';
import '../data/capture_parser.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/sfx.dart';
import '../vigil/vigil.dart';
import '../services/haptics.dart';

Future<void> showCaptureSheet(BuildContext context, {String? type, String? initialText}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: context.vigil.surface,
    shape: VigilShapes.sheet(BorderSide(color: context.vigil.signal, width: 2)),
    builder: (BuildContext ctx) => CaptureSheet(initialType: type, initialText: initialText),
  );
}

/// 04 · Quick Capture
class CaptureSheet extends ConsumerStatefulWidget {
  const CaptureSheet({super.key, this.initialType, this.initialText});

  final String? initialType;
  final String? initialText;

  @override
  ConsumerState<CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends ConsumerState<CaptureSheet> {
  final TextEditingController _ctl = TextEditingController();
  CaptureDraft _draft = CaptureDraft();
  CaptureType? _override;
  Threat _threat = Threat.routine;
  bool _remind = true;

  @override
  void initState() {
    super.initState();
    _override = switch (widget.initialType) {
      'objective' => CaptureType.obj,
      'event' => CaptureType.event,
      'note' => CaptureType.note,
      'spend' => CaptureType.spend,
      'habit' => CaptureType.habit,
      _ => null,
    };
    if (widget.initialText != null) {
      _ctl.text = widget.initialText!;
      _ctl.selection = TextSelection.collapsed(offset: _ctl.text.length);
      _draft = CaptureParser.parse(_ctl.text);
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  CaptureType get _type => _override ?? _draft.type;

  void _onChanged(String v) => setState(() => _draft = CaptureParser.parse(v));

  /// A spend needs an amount; everything else needs only words.
  bool get _canCommit => _ctl.text.trim().isNotEmpty && (_type != CaptureType.spend || (_draft.paise ?? 0) > 0);

  void _commit() {
    final VigilStore s = ref.read(storeProvider);
    _draft.type = _type;
    Haptics.tap();
    final VoidCallback? undo = s.commitCapture(_draft, _threat);
    if (undo == null) return;
    SfxService.play(Sfx.clear);
    final DateTime day = VigilStore.dateForLabel(_draft.whenLabel, DateTime.now());
    final String when = <String>[
      if (_draft.whenLabel != null && _draft.whenLabel != 'TODAY') Fmt.dayStamp(day) else if (_draft.when != null) 'TODAY',
      if (_draft.when != null) Fmt.hm(_draft.when!),
      if (_draft.type == CaptureType.spend && _draft.paise != null) Fmt.money(_draft.paise!),
    ].join(' ');
    final NavigatorState nav = Navigator.of(context);
    final ScaffoldMessengerState m = ScaffoldMessenger.of(context);
    final TextStyle style = context.vtype.meta.copyWith(fontSize: 12);
    final Color signal = context.vigil.signal;
    nav.pop();
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text('${CaptureParser.typeLabel(_draft.type)} LOGGED${when.isEmpty ? '' : ' · $when'}'.toUpperCase(), style: style),
      action: SnackBarAction(label: 'UNDO', textColor: signal, onPressed: undo),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final bool empty = _ctl.text.trim().isEmpty;
    final bool needsAmount = !empty && _type == CaptureType.spend && (_draft.paise ?? 0) <= 0;
    return AnimatedPadding(
      duration: VigilMotion.sheet,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.paddingOf(context).bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Row(children: <Widget>[
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('CAPTURE', style: t.section.copyWith(fontSize: 22)),
                Text('SAY IT ONCE. K SORTS IT.', style: t.micro.copyWith(color: c.textFaint)),
              ]),
            ),
            VigilIconButton(icon: VigilIcons.close, semanticLabel: 'Close capture', onPressed: () => Navigator.of(context).pop()),
          ]),
          const SizedBox(height: 14),
          VigilSegmented<CaptureType>(
            segments: const <(CaptureType, String)>[
              (CaptureType.obj, 'OBJ'),
              (CaptureType.event, 'EVENT'),
              (CaptureType.note, 'NOTE'),
              (CaptureType.spend, 'SPEND'),
              (CaptureType.habit, 'HABIT'),
            ],
            selected: _type,
            onSelected: (CaptureType v) => setState(() => _override = v),
          ),
          const SizedBox(height: 14),
          Text('PLAIN WORDS', style: t.label.copyWith(color: c.textFaint)),
          const SizedBox(height: 6),
          VigilField(
            controller: _ctl,
            hint: 'e.g. call home 9pm',
            semanticLabel: 'Plain words',
            maxLines: 2,
            autofocus: true,
            fillColor: c.ground,
            onChanged: _onChanged,
          ),
          const SizedBox(height: 14),
          Text('K PARSED', style: t.label.copyWith(color: c.textFaint)),
          const SizedBox(height: 6),
          if (empty)
            Text('Try: lunch 180 · call home 9pm · read 20 pages daily', style: t.meta.copyWith(color: c.textFaint, fontSize: 12))
          else if (needsAmount)
            Text('A spend needs an amount, e.g. lunch 180.', style: t.meta.copyWith(color: c.critical, fontSize: 12))
          else
            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              ParsedChip(keyLabel: 'TYPE', value: CaptureParser.typeLabel(_type), uncertain: _override == null && _draft.uncertainType),
              ParsedChip(keyLabel: 'WHEN', value: _draft.when != null ? '${_draft.whenLabel != null ? '${_draft.whenLabel} ' : ''}${Fmt.hm(_draft.when!)}' : (_draft.whenLabel ?? 'NONE'), uncertain: _draft.when == null && _draft.whenLabel == null),
              if (_draft.paise != null) ParsedChip(keyLabel: '₹', value: Fmt.money(_draft.paise!)),
              ParsedChip(keyLabel: 'TAG', value: _draft.tag ?? 'WORK', uncertain: _draft.tag == null),
            ]),
          const SizedBox(height: 14),
          Text('Priority', style: t.label.copyWith(color: c.textFaint)),
          const SizedBox(height: 6),
          Row(children: <Widget>[
            for (final (Threat th, String label, Color col) in <(Threat, String, Color)>[
              (Threat.crit, 'Urgent', c.critical),
              (Threat.high, 'High', c.warning),
              (Threat.routine, 'Normal', c.neutral),
            ]) ...<Widget>[
              if (th != Threat.crit) const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  button: true,
                  selected: _threat == th,
                  label: 'Priority $label',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: () => setState(() => _threat = th),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: _threat == th ? c.surfaceHigh : null,
                        border: Border.all(color: _threat == th ? col : c.lineStrong),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                        SizedBox(width: 8, height: 8, child: ColoredBox(color: col)),
                        const SizedBox(width: 8),
                        Text(label, style: t.button.copyWith(fontSize: 11, color: _threat == th ? c.text : c.textMuted)),
                      ]),
                    ),
                  ),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 12),
          VigilCard(
            onTap: () => setState(() => _remind = !_remind),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            semanticLabel: 'Reminder',
            child: SizedBox(
              height: 52,
              child: Row(children: <Widget>[
                Expanded(child: Text(_remind ? 'REMIND 30 MIN BEFORE' : 'NO REMINDER', style: t.button.copyWith(color: c.textMuted))),
                VigilIcon(VigilIcons.chevronRight, size: 18, color: c.textMuted),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: <Widget>[
            OctagonButton(
              size: 54,
              color: c.surfaceHigh,
              semanticLabel: 'Dictate',
              onPressed: () => showVigilSnack(context, 'Voice uplink is not connected yet'),
              child: VigilIcon(VigilIcons.voice, color: c.text),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: VigilButton(
                label: 'Commit',
                size: VigilButtonSize.large,
                expand: true,
                onPressed: _canCommit ? _commit : null,
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
