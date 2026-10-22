import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/common.dart';
import '../app/env.dart';
import '../app/fmt.dart';
import '../app/providers.dart';
import '../data/assistant.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/sfx.dart';
import '../vigil/vigil.dart';

/// 03 · VIGIL Uplink · Assistant (tab 3)
class UplinkScreen extends ConsumerStatefulWidget {
  const UplinkScreen({super.key});

  @override
  ConsumerState<UplinkScreen> createState() => _UplinkScreenState();
}

class _UplinkScreenState extends ConsumerState<UplinkScreen> {
  final TextEditingController _ctl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _busy = false;
  bool _cloud = false;

  @override
  void dispose() {
    _ctl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final String q = text.trim();
    if (q.isEmpty || _busy) return;
    final VigilStore s = ref.read(storeProvider);
    final Assistant a = ref.read(assistantProvider);
    SfxService.play(Sfx.tick);
    setState(() {
      s.chat.add(ChatMsg(fromUser: true, text: q, at: DateTime.now()));
      _ctl.clear();
      _busy = true;
    });
    _toEnd();
    final ChatMsg reply = await a.reply(q);
    if (!mounted) return;
    setState(() {
      s.chat.add(reply);
      _cloud = a.lastWasCloud;
      _busy = false;
    });
    _toEnd();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: VigilMotion.sheet, curve: VigilMotion.curve);
      });

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final VigilStore s = ref.watch(storeProvider);
    final bool cloudOn = s.toggles['cloudAi'] == true && Env.hasCloudAi;
    final List<String> chips = <String>[
      'Plan my day',
      if (s.overdueCount > 0) 'What\'s overdue?' else 'Sleep tonight',
      'Week report',
    ];

    return VigilScaffold(
      title: 'Vigil uplink',
      subtitle: _cloud ? '● CLOUD ASSIST' : (cloudOn ? '● ONLINE · CLOUD READY' : '● ONLINE · ON-DEVICE'),
      leading: const VigilEmblem(size: 30),
      actions: <Widget>[VigilIconButton(icon: VigilIcons.history, semanticLabel: 'History', onPressed: () => showVigilSnack(context, '${s.chat.length} messages this session'))],
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Expanded(
          child: s.chat.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    const VigilEmblem(size: 48, semanticLabel: ''),
                    const SizedBox(height: 14),
                    Text('Command VIGIL.', style: t.body.copyWith(color: c.textMuted)),
                    const SizedBox(height: 14),
                    Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: <Widget>[for (final String x in chips) VigilFilterChip(label: x, selected: false, onTap: () => _send(x))]),
                  ]),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.only(bottom: 12, top: 8),
                  itemCount: s.chat.length + (_busy ? 1 : 0),
                  itemBuilder: (BuildContext ctx, int i) {
                    if (i == s.chat.length) return Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('VIGIL · THINKING…', style: t.label.copyWith(color: c.signal)));
                    return _bubble(context, s, s.chat[i]);
                  },
                ),
        ),
        if (s.chat.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, children: <Widget>[for (final String x in chips) Padding(padding: const EdgeInsets.only(right: 8), child: VigilFilterChip(label: x, selected: false, onTap: () => _send(x)))]),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: EdgeInsets.only(bottom: tabBottomPad(context) - 12),
          child: Row(children: <Widget>[
            SizedBox(
              width: 44,
              height: 52,
              child: Semantics(button: true, label: 'Attach', child: InkWell(onTap: () => showVigilSnack(context, 'Attachments are not supported yet'), child: Container(decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.lineStrong)), child: Center(child: VigilIcon(VigilIcons.plus, size: 18, color: c.textMuted))))),
            ),
            const SizedBox(width: 8),
            Expanded(child: VigilField(controller: _ctl, hint: 'Command VIGIL…', semanticLabel: 'Command VIGIL', height: 52, onSubmitted: _send, onChanged: (_) => setState(() {}))),
            const SizedBox(width: 8),
            OctagonButton(size: 52, semanticLabel: _ctl.text.trim().isEmpty ? 'Voice' : 'Send', onPressed: () => _ctl.text.trim().isEmpty ? showVigilSnack(context, 'Voice uplink is not connected yet') : _send(_ctl.text), child: VigilIcon(_ctl.text.trim().isEmpty ? VigilIcons.voice : VigilIcons.arrowRight, color: c.onSignal)),
          ]),
        ),
      ]),
    );
  }

  Widget _bubble(BuildContext context, VigilStore s, ChatMsg m) {
    final c = context.vigil;
    final t = context.vtype;
    final double w = MediaQuery.sizeOf(context).width - 40;
    if (m.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          constraints: BoxConstraints(maxWidth: w * 0.82),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.surfaceHigh, border: Border.all(color: c.lineStrong)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[Text(m.text, style: t.body), const SizedBox(height: 4), Text(Fmt.time(m.at), style: t.micro.copyWith(color: c.textFaint))]),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _longPress(context, m),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          constraints: BoxConstraints(maxWidth: w * 0.92),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text('VIGIL · ${Fmt.time(m.at)}', style: t.label.copyWith(color: m.alert ? c.critical : c.signal)),
            const SizedBox(height: 4),
            Text(m.text, style: t.body),
            if (m.diff != null) ...<Widget>[
              const SizedBox(height: 8),
              CornerBrackets(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.line)),
                  child: Column(children: <Widget>[
                    for (final (String, String) r in m.diff!)
                      Row(children: <Widget>[SizedBox(width: 62, child: Text(r.$1, style: t.micro.copyWith(color: c.signal))), Expanded(child: Text(m.undone ? 'UNDONE' : r.$2, style: t.meta.copyWith(color: c.text)))]),
                    if (m.undoable && !m.undone)
                      Align(alignment: Alignment.centerRight, child: VigilButton(label: 'Undo', variant: VigilButtonVariant.secondary, onPressed: () => _undo(s, m))),
                  ]),
                ),
              ),
            ],
            if (m.chart != null) ...<Widget>[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.line)),
                child: Column(children: <Widget>[
                  MiniBars(values: m.chart!, colors: <Color>[for (int i = 0; i < m.chart!.length; i++) i == m.chart!.length - 1 ? c.signal : c.steel], height: 48, gap: 6, semanticLabel: 'Seven day chart'),
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: <Widget>[for (final String d in 'MTWTFSS'.split('')) Text(d, style: t.micro.copyWith(color: c.textFaint))]),
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  void _undo(VigilStore s, ChatMsg m) {
    // Reverse the most recent assistant write: water or the newest objective.
    final String d = m.diff!.first.$2;
    if (d.contains('water')) {
      final RegExpMatch? ml = RegExp(r'\+(\d+) ml').firstMatch(d);
      if (ml != null) s.logWater(-int.parse(ml.group(1)!));
    } else {
      final Objective? o = s.objectives.where((Objective e) => e.title == d).firstOrNull;
      if (o != null) s.removeObjective(o.id);
    }
    setState(() => m.undone = true);
  }

  void _longPress(BuildContext context, ChatMsg m) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          ListTile(
            title: const Text('COPY'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: m.text));
              Navigator.pop(ctx);
            },
          ),
          ListTile(
            title: const Text('WHY?'),
            subtitle: Text('Answered from the on-device router${m.diff != null ? ' with one write' : ''}. Numbers come from the store.', style: ctx.vtype.caption),
            onTap: () => Navigator.pop(ctx),
          ),
          ListTile(title: const Text('REPORT'), onTap: () => Navigator.pop(ctx)),
        ]),
      ),
    );
  }
}
