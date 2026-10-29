import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app/brand.dart';
import '../app/common.dart';
import '../app/env.dart';
import '../app/fmt.dart';
import '../app/providers.dart';
import '../data/assistant.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/haptics.dart';
import '../services/local_brain.dart';
import '../services/sfx.dart';
import '../services/voice.dart';
import '../vigil/vigil.dart';
import 'jarvis_orb.dart';

/// 03 · K · Assistant (tab 3)
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

  /// The words of an on-device answer as they are written, or null when none is being written.
  String? _stream;

  /// Shown when the microphone is switched off for K.
  bool _micNeeded = false;

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
      s.chatChanged();
      _ctl.clear();
      _busy = true;
    });
    _voice.setThinking(true);
    _toEnd();
    final ChatMsg reply = await a.reply(q, onPartial: (String words) {
      if (!mounted) return;
      setState(() => _stream = words);
      _toEnd();
    });
    _voice.setThinking(false);
    if (!mounted) return;
    setState(() {
      _stream = null;
      s.chat.add(reply);
      s.chatChanged();
      _cloud = a.lastWasCloud;
      _local = a.lastWasLocal;
      _model = a.lastModel;
      _busy = false;
    });
    _toEnd();
    // A change was made and it worked: the strike.
    if (reply.diff != null && !reply.alert) {
      Haptics.strike();
      ThunderFx.strike(context);
    }
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
    if (ok && _micNeeded && mounted) setState(() => _micNeeded = false);
    if (!ok && mounted) {
      final bool granted = (await Permission.microphone.status).isGranted;
      if (!mounted) return;
      if (!granted) {
        setState(() => _micNeeded = true);
        return;
      }
      showVigilSnack(context, _voice.error ?? 'Voice is not available on this phone');
    }
  }

  Future<void> _allowMic() async {
    final PermissionStatus st = await Permission.microphone.request();
    if (!mounted) return;
    if (st.isGranted) {
      setState(() => _micNeeded = false);
      await _listen();
    } else if (st.isPermanentlyDenied) {
      await openAppSettings();
    }
  }

  Widget _orbHeader(BuildContext context, VigilStore s) {
    final c = context.vigil;
    final t = context.vtype;
    final bool empty = s.chat.isEmpty;
    final String status = switch (_voice.state) {
      VoiceState.idle => _voice.error ?? 'Tap the orb or mic and speak',
      VoiceState.listening => _voice.partial.isEmpty ? 'Listening…' : _voice.partial,
      VoiceState.thinking => 'Thinking…',
      VoiceState.speaking => 'Speaking · tap the orb to stop',
    };
    final Color statusColor = _voice.error != null && _voice.state == VoiceState.idle ? c.critical : c.textMuted;
    JarvisOrb orb(double size) => JarvisOrb(
          state: _voice.state,
          level: _voice.level,
          color: c.violet,
          size: size,
          crackle: !empty,
          onTap: () => _voice.state == VoiceState.idle ? _listen() : _voice.stopAll(),
        );
    // Once there is a conversation the orb shrinks to a header row, so messages get the room.
    if (!empty) {
      return Column(children: <Widget>[
        Row(children: <Widget>[
          orb(56),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(status, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.caption.copyWith(color: statusColor)),
              const SizedBox(height: 2),
              _brainLine(context, center: false),
            ]),
          ),
          VigilFilterChip(label: 'Hands-free', selected: _handsFree, onTap: () => setState(() => _handsFree = !_handsFree)),
        ]),
        if (_micNeeded) _micCard(context),
      ]);
    }
    return Column(children: <Widget>[
      orb(150),
      const SizedBox(height: 4),
      Text(status, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: t.caption.copyWith(color: statusColor)),
      const SizedBox(height: 6),
      VigilFilterChip(label: 'Hands-free', selected: _handsFree, onTap: () => setState(() => _handsFree = !_handsFree)),
      const SizedBox(height: 6),
      _brainLine(context),
      if (_micNeeded) _micCard(context),
    ]);
  }

  /// One line about K's brain: warm, asleep, off, or not installed (with a way to get it).
  Widget _brainLine(BuildContext context, {bool center = true}) {
    final c = context.vigil;
    final t = context.vtype;
    final LocalBrain b = ref.watch(brainProvider);
    if (b.status == BrainStatus.notInstalled && !center) {
      return Row(children: <Widget>[
        Flexible(child: Text('AI model not installed', style: t.micro.copyWith(color: c.textFaint))),
        const SizedBox(width: 4),
        VigilButton(label: 'Download', variant: VigilButtonVariant.ghost, size: VigilButtonSize.small, onPressed: () => context.push('/loadout/brain')),
      ]);
    }
    if (b.status == BrainStatus.notInstalled) {
      return Container(
        margin: const EdgeInsets.only(top: 4, bottom: 4),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(border: Border.all(color: c.lineStrong), color: c.surface, borderRadius: BorderRadius.circular(KRadius.field)),
        child: Row(children: <Widget>[
          Expanded(child: Text('The AI model is not installed. Commands and your data still work.', style: t.caption.copyWith(color: c.textMuted))),
          const SizedBox(width: 8),
          VigilButton(label: 'Download', variant: VigilButtonVariant.secondary, onPressed: () => context.push('/loadout/brain')),
        ]),
      );
    }
    if (!b.enabled) return Text('AI model off · instant answers and your data only', style: t.micro.copyWith(color: c.textFaint));
    final bool warm = b.loaded;
    return Row(mainAxisAlignment: center ? MainAxisAlignment.center : MainAxisAlignment.start, children: <Widget>[
      Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: warm ? c.success : Colors.transparent, border: Border.all(color: warm ? c.success : c.textFaint))),
      const SizedBox(width: 6),
      Flexible(child: Text(warm ? 'AI model ready · frees memory in ${b.idleMinutes} min' : 'AI model off · loads when needed', style: t.micro.copyWith(color: c.textFaint))),
    ]);
  }

  Widget _micCard(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: c.violet), color: c.surface, borderRadius: BorderRadius.circular(KRadius.card)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('Microphone needed to talk to $kAssistantName', style: t.rowTitle),
        const SizedBox(height: 4),
        Text('$kAssistantName listens only while the mic is lit. Speech is turned into text on this phone, needs the offline speech pack, and is never stored.', style: t.caption.copyWith(color: c.textMuted)),
        const SizedBox(height: 8),
        Row(children: <Widget>[
          VigilButton(label: 'Allow', onPressed: _allowMic),
          const SizedBox(width: 8),
          VigilButton(label: 'Type instead', variant: VigilButtonVariant.ghost, onPressed: () => setState(() => _micNeeded = false)),
        ]),
      ]),
    );
  }

  /// The answer being written: streamed words with Cancel, the cold-start card, or plain thinking.
  Widget _working(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final LocalBrain b = ref.watch(brainProvider);
    final Widget cancel = Align(alignment: Alignment.centerRight, child: VigilButton(label: 'Cancel', variant: VigilButtonVariant.secondary, onPressed: b.cancelAnswer));
    if (_stream != null && _stream!.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('$kAssistantName · answering', style: t.label.copyWith(color: c.violet)),
          const SizedBox(height: 4),
          Semantics(liveRegion: true, child: Text('$_stream▍', style: t.body.copyWith(color: c.textMuted))),
          const SizedBox(height: 6),
          Row(children: <Widget>[const _SourceTag(ReplySource.model), const Spacer(), cancel]),
        ]),
      );
    }
    if (b.status == BrainStatus.loading) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: VigilCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Row(children: <Widget>[
              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Expanded(child: Text('Waking $kAssistantName\'s brain…', style: t.title)),
            ]),
            const SizedBox(height: 6),
            Text('The first answer after idle can take about a minute. Instant commands work now.', style: t.caption.copyWith(color: c.textMuted)),
            const SizedBox(height: 8),
            cancel,
          ]),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: <Widget>[
        Expanded(child: Text('$kAssistantName · thinking…', style: t.label.copyWith(color: c.violet))),
        if (b.status == BrainStatus.busy) cancel,
      ]),
    );
  }

  /// "Remind me to…" puts the start of a sentence in the box and leaves the cursor at the end.
  void _startReminder() => setState(() {
        _ctl.text = 'Remind me to ';
        _ctl.selection = TextSelection.collapsed(offset: _ctl.text.length);
      });

  /// First run: who K is, what it can do without the model, and things to try.
  Widget _firstRun(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    Widget row(String tag, String text) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            SizedBox(width: 110, child: Text(tag, style: t.label.copyWith(color: c.violet))),
            Expanded(child: Text(text, style: t.caption.copyWith(color: c.textMuted))),
          ]),
        );
    return SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        const SizedBox(height: 10),
        Text('Standing by', style: t.label.copyWith(color: c.violet)),
        const SizedBox(height: 4),
        Text('I\'m $kAssistantName.', style: t.h2),
        const SizedBox(height: 6),
        Text('I run on this phone: private, offline, free. Tell me what to log, or ask about your day.', style: t.body.copyWith(color: c.textMuted), textAlign: TextAlign.center),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: <Widget>[
          for (final MapEntry<String, VoidCallback> chip in <String, VoidCallback>{
            'Log a glass of water': () => _send('Log a glass of water'),
            'Remind me to…': _startReminder,
            'How much water today?': () => _send('How much water today?'),
            "What's on my calendar?": () => _send("What's on my calendar today?"),
          }.entries)
            SizedBox(width: (MediaQuery.sizeOf(context).width - 48 - 8) / 2, child: VigilFilterChip(label: chip.key, selected: false, onTap: chip.value)),
        ]),
        const SizedBox(height: 14),
        row('Done instantly', 'Clear commands, under 50 ms'),
        row('From your data', 'Water, sleep, spend, calendar'),
        row('AI answer', 'Open chat, 10–20 s'),
      ]),
    );
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: VigilMotion.sheet, curve: VigilMotion.curve);
      });

  void _fill(String text) => setState(() {
        _ctl.text = text;
        _ctl.selection = TextSelection.collapsed(offset: text.length);
      });

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final VigilStore s = ref.watch(storeProvider);
    final bool cloudOn = s.toggles['cloudAi'] == true && Env.hasCloudAi;
    // Text handed over by the quick-add bar on Today.
    final String? pending = ref.watch(pendingPromptProvider);
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(pendingPromptProvider.notifier).state = null;
        _send(pending);
      });
    }
    // Suggestions that fit what is on this phone now: questions are sent, commands are put in the box to finish.
    final Block? firstEvent = s.todayBlocks.where((Block b) => b.kind == BlockKind.event && b.src == null).firstOrNull;
    final List<(String, bool)> chips = <(String, bool)>[
      (s.overdueCount > 0 ? 'What\'s overdue?' : 'What\'s on today?', true),
      if (s.effectiveBudgetPaise > 0) ('How much budget is left?', true) else ('Spent 200 on ', false),
      if (firstEvent != null) ('Move ${firstEvent.title.toLowerCase()} to ', false) else ('Remind me to ', false),
      if (s.healthOn) ('Log a glass of water', true),
    ];

    return VigilScaffold(
      title: kAssistantName,
      subtitle: _local ? 'On this phone · ${_model ?? 'MiniCPM5-1B'}' : (_cloud ? 'Cloud${_model == null ? '' : ' · $_model'}' : (cloudOn ? 'Cloud ready' : (LocalBrain.instance.usable ? 'On this phone · ready' : 'Instant commands and your data'))),
      mark: true,
      actions: <Widget>[VigilIconButton(icon: VigilIcons.history, semanticLabel: 'History', onPressed: () => showVigilSnack(context, '${s.chat.length} messages this session'))],
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        _orbHeader(context, s),
        Expanded(
          child: s.chat.isEmpty
              ? Center(child: _firstRun(context))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.only(bottom: 12, top: 8),
                  itemCount: s.chat.length + (_busy ? 1 : 0),
                  itemBuilder: (BuildContext ctx, int i) {
                    if (i == s.chat.length) return _working(context);
                    return _bubble(context, s, s.chat[i]);
                  },
                ),
        ),
        if (s.chat.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, children: <Widget>[for (final (String, bool) x in chips) Padding(padding: const EdgeInsets.only(right: 8), child: VigilFilterChip(label: x.$1.trim(), selected: false, onTap: () => x.$2 ? _send(x.$1) : _fill(x.$1)))]),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: EdgeInsets.only(bottom: tabBottomPad(context) - 12),
          child: Row(children: <Widget>[
            Expanded(child: VigilField(controller: _ctl, hint: 'Ask $kAssistantName or give a command…', semanticLabel: 'Command $kAssistantName', height: 52, onSubmitted: _send, onChanged: (_) => setState(() {}))),
            const SizedBox(width: 8),
            CircleButton(size: 52, semanticLabel: _ctl.text.trim().isEmpty ? (_voice.state == VoiceState.listening ? 'Stop listening' : 'Speak') : 'Send', onPressed: () => _ctl.text.trim().isEmpty ? _listen() : _send(_ctl.text), child: VigilIcon(_ctl.text.trim().isEmpty ? VigilIcons.voice : VigilIcons.arrowRight, color: c.onSignal)),
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
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(6)),
          ),
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
            Text('$kAssistantName · ${Fmt.time(m.at)}', style: t.label.copyWith(color: m.alert ? c.critical : c.violet)),
            if (m.source != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: <Widget>[
                  _SourceTag(m.source!),
                  if (m.ms != null && (m.source == ReplySource.instant || m.source == ReplySource.data)) Padding(padding: const EdgeInsets.only(left: 8), child: Text('${m.ms} ms', style: t.meta.copyWith(color: c.textFaint))),
                ]),
              ),
            const SizedBox(height: 4),
            Text(m.text, style: t.body),
            if (m.diff != null) ...<Widget>[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.raised, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(16), boxShadow: c.cardShadow),
                child: Column(children: <Widget>[
                  for (final (String, String) r in m.diff!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[SizedBox(width: 90, child: Text(r.$1, style: t.label.copyWith(color: c.violet))), Expanded(child: Text(m.undone ? 'Undone' : r.$2, style: t.meta.copyWith(color: c.text)))]),
                    ),
                  if (m.undoable && !m.undone)
                    Align(alignment: Alignment.centerRight, child: VigilButton(label: 'Undo', size: VigilButtonSize.small, variant: VigilButtonVariant.secondary, onPressed: () => _undo(m))),
                ]),
              ),
            ],
            if (m.confirm && !_busy && s.chat.isNotEmpty && identical(s.chat.last, m)) ...<Widget>[
              const SizedBox(height: 10),
              Row(children: <Widget>[
                VigilButton(label: 'Confirm', variant: VigilButtonVariant.critical, size: VigilButtonSize.small, onPressed: () => _send('yes')),
                const SizedBox(width: 8),
                VigilButton(label: 'Cancel', variant: VigilButtonVariant.secondary, size: VigilButtonSize.small, onPressed: () => _send('no')),
              ]),
            ],
            if (m.route != null) ...<Widget>[
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: VigilButton(label: 'Open', variant: VigilButtonVariant.secondary, onPressed: () => context.go(m.route!))),
            ],
            if (m.note != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(m.note!, style: t.caption.copyWith(color: m.note!.contains('failed') ? c.critical : c.textFaint)),
            ],
            if (m.chart != null) ...<Widget>[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(16)),
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

  String _why(ChatMsg m) => switch (m.source) {
        ReplySource.instant => 'Decided by exact rules on this phone: no model was used, so it is the same every time.',
        ReplySource.data => 'Answered from the real data in this app, on this phone. The numbers come from the store.',
        ReplySource.model => 'Written by the on-device model, MiniCPM5-1B. Anything it wanted to change was checked against your words first.',
        ReplySource.cloud => 'Answered by your own cloud AI key. Only your question and earlier open-chat turns were sent, never your app data.',
        null => 'A note from $kAssistantName about how this request was handled.',
      };

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
            title: const Text('Copy'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: m.text));
              Navigator.pop(ctx);
            },
          ),
          ListTile(
            title: const Text('Why this answer?'),
            subtitle: Text(_why(m), style: ctx.vtype.caption),
            onTap: () => Navigator.pop(ctx),
          ),
          ListTile(title: const Text('Report'), onTap: () => Navigator.pop(ctx)),
        ]),
      ),
    );
  }
}

/// Tells where a reply came from: an icon, the words, and a colour (never colour alone).
class _SourceTag extends StatelessWidget {
  const _SourceTag(this.source);

  final ReplySource source;

  @override
  Widget build(BuildContext context) {
    final t = context.vtype;
    final c = context.vigil;
    final (IconData icon, String label, Color color) = switch (source) {
      ReplySource.instant => (Icons.bolt, 'Done instantly', c.signal2),
      ReplySource.data => (Icons.dataset_outlined, 'From your data', c.success),
      ReplySource.model => (Icons.memory, 'AI answer', c.violet),
      ReplySource.cloud => (Icons.cloud_outlined, 'Cloud', c.warning),
    };
    return Semantics(
      label: 'Answered by: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(border: Border.all(color: color.withValues(alpha: 0.5)), color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(KRadius.pill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: t.micro.copyWith(color: color, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
