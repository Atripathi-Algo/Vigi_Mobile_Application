import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/brand.dart';
import '../app/common.dart';
import '../app/env.dart';
import '../app/fmt.dart';
import '../app/providers.dart';
import '../data/assistant.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/local_brain.dart';
import '../services/sfx.dart';
import '../services/voice.dart';
import '../vigil/vigil.dart';
import 'jarvis_orb.dart';

/// 03 · VIGIL Uplink · Assistant (tab 3)
class UplinkScreen extends ConsumerStatefulWidget {
  const UplinkScreen({super.key});

  @override
  ConsumerState<UplinkScreen> createState() => _UplinkScreenState();
}

class _UplinkScreenState extends ConsumerState<UplinkScreen> with WidgetsBindingObserver {
  final TextEditingController _ctl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final VoiceService _voice = VoiceService.instance;
  bool _busy = false;
  bool _cloud = false;
  bool _local = false;
  String? _model;

  /// After each spoken reply, listen again without a tap.
  bool _handsFree = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voice.addListener(_onVoice);
  }

  void _onVoice() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Never keep the microphone open in the background.
    if (state != AppLifecycleState.resumed) _voice.stopAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voice.removeListener(_onVoice);
    _voice.stopAll();
    _ctl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// [spoken] is true when the words came from the microphone: the reply is read aloud then.
  Future<void> _send(String text, {bool spoken = false}) async {
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
    _voice.setThinking(true);
    _toEnd();
    final ChatMsg reply = await a.reply(q);
    _voice.setThinking(false);
    if (!mounted) return;
    setState(() {
      s.chat.add(reply);
      _cloud = a.lastWasCloud;
      _local = a.lastWasLocal;
      _model = a.lastModel;
      _busy = false;
    });
    _toEnd();
    if (spoken || (s.toggles['spoken'] ?? false)) {
      await _voice.speak(reply.text);
      // Keep the conversation going if hands-free is on, but only while this tab is on screen.
      if (spoken && _handsFree && mounted && TickerMode.valuesOf(context).enabled) await _listen();
    }
  }

  Future<void> _listen() async {
    if (_voice.state == VoiceState.listening) {
      await _voice.stopListening();
      return;
    }
    if (_voice.state == VoiceState.speaking) await _voice.stopSpeaking();
    LocalBrain.instance.preload(); // load the model while the user speaks, so the answer is not delayed
    final bool ok = await _voice.listen((String text) => _send(text, spoken: true));
    if (!ok && mounted) showVigilSnack(context, _voice.error ?? 'Voice is not available on this phone');
  }

  Widget _orbHeader(BuildContext context, VigilStore s) {
    final c = context.vigil;
    final t = context.vtype;
    final bool empty = s.chat.isEmpty;
    final String status = switch (_voice.state) {
      VoiceState.idle => _voice.error ?? 'TAP THE ORB OR MIC AND SPEAK',
      VoiceState.listening => _voice.partial.isEmpty ? 'LISTENING…' : _voice.partial,
      VoiceState.thinking => 'THINKING…',
      VoiceState.speaking => 'SPEAKING · TAP THE ORB TO STOP',
    };
    return Column(children: <Widget>[
      JarvisOrb(
        state: _voice.state,
        level: _voice.level,
        color: c.signal,
        size: empty ? 190 : 104,
        crackle: true,
        onTap: () => _voice.state == VoiceState.idle ? _listen() : _voice.stopAll(),
      ),
      const SizedBox(height: 4),
      Text(status, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: t.micro.copyWith(color: _voice.error != null && _voice.state == VoiceState.idle ? c.critical : c.textFaint, fontSize: 10)),
      const SizedBox(height: 6),
      SizedBox(width: 170, child: VigilFilterChip(label: 'HANDS-FREE', selected: _handsFree, onTap: () => setState(() => _handsFree = !_handsFree))),
      const SizedBox(height: 6),
    ]);
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
      title: kAssistantName,
      subtitle: _local ? '● LOCAL · ${(_model ?? 'MINICPM5-1B').toUpperCase()}' : (_cloud ? '● CLOUD${_model == null ? '' : ' · ${_model!.toUpperCase()}'}' : (cloudOn ? '● ONLINE · CLOUD READY' : (LocalBrain.instance.usable ? '● LOCAL · READY' : '● ON-DEVICE RULES'))),
      leading: const VigilEmblem(size: 30),
      actions: <Widget>[VigilIconButton(icon: VigilIcons.history, semanticLabel: 'History', onPressed: () => showVigilSnack(context, '${s.chat.length} messages this session'))],
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        _orbHeader(context, s),
        Expanded(
          child: s.chat.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    Text('Command $kAssistantName.', style: t.body.copyWith(color: c.textMuted)),
                    const SizedBox(height: 14),
                    Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: <Widget>[for (final String x in chips) VigilFilterChip(label: x, selected: false, onTap: () => _send(x))]),
                  ]),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.only(bottom: 12, top: 8),
                  itemCount: s.chat.length + (_busy ? 1 : 0),
                  itemBuilder: (BuildContext ctx, int i) {
                    if (i == s.chat.length) return Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('$kAssistantName · THINKING…', style: t.label.copyWith(color: c.signal)));
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
            Expanded(child: VigilField(controller: _ctl, hint: 'Command $kAssistantName…', semanticLabel: 'Command $kAssistantName', height: 52, onSubmitted: _send, onChanged: (_) => setState(() {}))),
            const SizedBox(width: 8),
            OctagonButton(size: 52, semanticLabel: _ctl.text.trim().isEmpty ? (_voice.state == VoiceState.listening ? 'Stop listening' : 'Speak') : 'Send', onPressed: () => _ctl.text.trim().isEmpty ? _listen() : _send(_ctl.text), child: VigilIcon(_ctl.text.trim().isEmpty ? VigilIcons.voice : VigilIcons.arrowRight, color: c.onSignal)),
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
            Text('$kAssistantName · ${Fmt.time(m.at)}', style: t.label.copyWith(color: m.alert ? c.critical : c.signal)),
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
                      Align(alignment: Alignment.centerRight, child: VigilButton(label: 'Undo', variant: VigilButtonVariant.secondary, onPressed: () => _undo(m))),
                  ]),
                ),
              ),
            ],
            if (m.note != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(m.note!, style: t.micro.copyWith(color: m.note!.contains('failed') ? c.critical : c.textFaint, fontSize: 10)),
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

  void _undo(ChatMsg m) {
    m.onUndo?.call();
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
