import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/brand.dart';
import '../app/common.dart';
import '../app/providers.dart';
import '../data/brain_eval.dart';
import '../data/brain_prompt.dart';
import '../services/local_brain.dart';
import '../services/local_llm.dart';
import '../services/model_store.dart';
import '../vigil/vigil.dart';

/// K's on-device brain: download, settings that trade speed and battery, and a speed and accuracy check.
class BrainScreen extends ConsumerStatefulWidget {
  const BrainScreen({super.key});

  @override
  ConsumerState<BrainScreen> createState() => _BrainScreenState();
}

class _BrainScreenState extends ConsumerState<BrainScreen> {
  String? _message;
  bool _testing = false;
  String? _speed;
  String? _evalSummary;
  List<EvalResult> _failed = const <EvalResult>[];
  int _evalDone = 0;
  int _partial = 0;

  @override
  void initState() {
    super.initState();
    LocalBrain.instance.partialBytes().then((int b) => mounted ? setState(() => _partial = b) : null);
  }

  Future<void> _download(LocalBrain b) async {
    setState(() => _message = null);
    final String? err = await b.download();
    final int partial = await b.partialBytes();
    if (!mounted) return;
    setState(() {
      _partial = partial;
      _message = err ?? (b.status == BrainStatus.ready ? 'Downloaded. K now answers on this phone.' : 'Download paused. Tap again to resume.');
    });
  }

  Future<void> _speedTest(LocalBrain b) async {
    setState(() {
      _testing = true;
      _speed = null;
    });
    await b.unload(); // a cold start, as after a long idle
    String s(num? ms) => ms == null ? 'n/a' : '${(ms / 1000).toStringAsFixed(1)} s';
    final StringBuffer out = StringBuffer();
    // 1. Raw speed: a tiny free-text answer, no grammar, so only the model's own speed is measured.
    final raw = await b.run(const <BrainTurn>[BrainTurn('user', 'Say hello in five words.')], sampling: const BrainSampling(maxTokens: 24), timeout: const Duration(seconds: 240), constrained: false);
    out.writeln('Load ${s(b.lastLoadMs)}. First word ${s(b.lastFirstTokenMs)}. ${b.lastTokensPerSecond == null ? 'Writing speed n/a.' : 'Writes ${b.lastTokensPerSecond!.toStringAsFixed(1)} tokens/s.'}');
    out.writeln(raw.text == null ? 'Raw test: ${raw.error}' : 'Raw reply: ${raw.text!.replaceAll('\n', ' ')}');
    // 2. A real request: the full prompt, forced to the JSON schema.
    if (raw.text != null) {
      final Stopwatch sw = Stopwatch()..start();
      final reply = await b.ask(kEvalFacts, 'how much water have I had today?', const <(bool, String)>[], timeout: const Duration(seconds: 240));
      out.write('Real request: ${s(sw.elapsedMilliseconds)}. ${reply.text ?? reply.error}');
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _speed = out.toString();
    });
  }

  Future<void> _accuracy(LocalBrain b) async {
    setState(() {
      _testing = true;
      _evalSummary = null;
      _failed = const <EvalResult>[];
      _evalDone = 0;
    });
    final EvalReport r = await runBrainEval(b, onProgress: (int done, int total) {
      if (mounted) setState(() => _evalDone = done);
    });
    if (!mounted) return;
    setState(() {
      _testing = false;
      _evalSummary = '${r.passed} of ${r.results.length} correct (${(r.accuracy * 100).round()}%). Decided by: ${r.bySource}. Average ${(r.averageMs / 1000).toStringAsFixed(1)} s per answer.';
      _failed = r.results.where((EvalResult e) => !e.ok).take(8).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final LocalBrain b = ref.watch(brainProvider);
    final BrainStatus st = b.status;
    final bool installed = st == BrainStatus.ready || st == BrainStatus.loading || st == BrainStatus.busy;
    return VigilScaffold(
      title: '$kAssistantName brain',
      subtitle: 'On this phone · No key · No cost',
      leading: VigilIconButton(icon: VigilIcons.chevronLeft, semanticLabel: 'Back', onPressed: () => context.pop()),
      body: ListView(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 28),
        children: <Widget>[
          VigilCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              Row(children: <Widget>[
                Expanded(child: Text('MiniCPM5-1B', style: t.label.copyWith(color: c.text))),
                StatusChip(switch (st) {
                  BrainStatus.notInstalled => 'NOT DOWNLOADED',
                  BrainStatus.downloading => 'DOWNLOADING',
                  BrainStatus.ready => b.loaded ? 'LOADED' : 'READY',
                  BrainStatus.loading => 'LOADING',
                  BrainStatus.busy => 'THINKING',
                }, on: installed),
              ]),
              const SizedBox(height: 6),
              Text(
                'OpenBMB\'s 1-billion-parameter model (Apache-2.0), run by llama.cpp on this phone\'s CPU. $kAssistantName understands plain language and can add, log and clear things, '
                'with no internet, key or account. Nothing you say leaves the phone.',
                style: t.caption.copyWith(color: c.textMuted),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          VigilCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              Text('Model file', style: t.label.copyWith(color: c.textFaint)),
              const SizedBox(height: 8),
              VigilSegmented<BrainVariant>(
                segments: <(BrainVariant, String)>[for (final BrainVariant v in BrainVariant.values) (v, '${v.label} · ${v.sizeText}')],
                selected: b.variant,
                onSelected: (BrainVariant v) async {
                  if (st == BrainStatus.downloading) return;
                  await b.setVariant(v);
                  final int p = await b.partialBytes();
                  if (mounted) setState(() => _partial = p);
                },
              ),
              const SizedBox(height: 6),
              Text(b.variant.note, style: t.caption.copyWith(color: c.textMuted)),
              const SizedBox(height: 12),
              if (st == BrainStatus.downloading) ...<Widget>[
                ValueListenableBuilder<double>(
                  valueListenable: b.progress,
                  builder: (BuildContext ctx, double p, Widget? _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                    SegmentBar(fraction: p.clamp(0, 1).toDouble(), thickness: 8, color: c.signal),
                    const SizedBox(height: 6),
                    Text('${(p * 100).toStringAsFixed(0)}% of ${b.variant.sizeText}', style: t.meta.copyWith(color: c.textMuted)),
                  ]),
                ),
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: VigilButton(label: 'Pause', variant: VigilButtonVariant.secondary, onPressed: b.cancelDownload)),
              ] else if (!installed)
                Align(
                  alignment: Alignment.centerLeft,
                  child: VigilButton(
                    label: _partial > 0 ? 'Resume download · ${(_partial / 1e6).round()} MB done' : 'Download ${b.variant.sizeText}',
                    onPressed: () => _download(b),
                  ),
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: VigilButton(
                    label: 'Delete model',
                    variant: VigilButtonVariant.secondary,
                    onPressed: () async {
                      if (await confirmDeleteModel(context)) await b.remove();
                    },
                  ),
                ),
              if (_message != null || b.error != null) ...<Widget>[
                const SizedBox(height: 10),
                Semantics(liveRegion: true, child: Text(_message ?? b.error!, style: t.meta.copyWith(color: b.error != null && _message == b.error ? c.critical : c.textMuted, fontSize: 12))),
              ],
              const SizedBox(height: 8),
              Text('Download over Wi-Fi: it is a one-time file. It resumes if interrupted.', style: t.micro.copyWith(color: c.textFaint, fontSize: 10)),
            ]),
          ),
          const SizedBox(height: 14),
          VigilCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              Row(children: <Widget>[
                Expanded(child: Text('Answer on this phone', style: t.rowTitle)),
                VigilSwitch(value: b.enabled, onChanged: (bool v) => b.setEnabled(v), semanticLabel: 'Answer on this phone'),
              ]),
              const SizedBox(height: 14),
              Text('Free the memory after', style: t.label.copyWith(color: c.textFaint)),
              const SizedBox(height: 6),
              VigilSegmented<int>(
                segments: const <(int, String)>[(1, '1 MIN'), (2, '2 MIN'), (5, '5 MIN')],
                selected: b.idleMinutes,
                onSelected: (int v) => b.setIdleMinutes(v),
              ),
              const SizedBox(height: 14),
              Text('CPU threads', style: t.label.copyWith(color: c.textFaint)),
              const SizedBox(height: 6),
              VigilSegmented<int>(
                segments: const <(int, String)>[(0, 'Auto'), (2, '2'), (3, '3'), (4, '4')],
                selected: b.threads,
                onSelected: (int v) => b.setThreads(v),
              ),
              const SizedBox(height: 8),
              Text(
                'Battery: nothing runs while $kAssistantName is idle. The model loads when you ask (or open the microphone), answers in a few seconds, and is released after the time above. '
                'More threads is faster but uses more power; AUTO uses the four fast cores.',
                style: t.caption.copyWith(color: c.textMuted),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          VigilCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              Text('Check this phone', style: t.label.copyWith(color: c.textFaint)),
              const SizedBox(height: 6),
              Text('Measures how fast the model starts and writes, and how often it picks the right action on ${kEvalCases.length} sample requests. Nothing is saved or changed.', style: t.caption.copyWith(color: c.textMuted)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                VigilButton(label: _testing ? 'Working…' : 'Speed test', variant: VigilButtonVariant.secondary, onPressed: !installed || _testing ? null : () => _speedTest(b)),
                VigilButton(label: _testing && _evalDone > 0 ? 'Checking $_evalDone / ${kEvalCases.length}' : 'Accuracy check', variant: VigilButtonVariant.secondary, onPressed: !installed || _testing ? null : () => _accuracy(b)),
              ]),
              if (_speed != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(_speed!, style: t.meta.copyWith(color: c.textMuted, fontSize: 12)),
              ],
              if (_evalSummary != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(_evalSummary!, style: t.rowTitle),
                for (final EvalResult e in _failed) Padding(padding: const EdgeInsets.only(top: 4), child: Text('"${e.c.utterance}": ${e.detail}', style: t.micro.copyWith(color: c.textFaint, fontSize: 10))),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}

Future<bool> confirmDeleteModel(BuildContext context) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: const Text('Delete model?'),
      content: Text('$kAssistantName stops answering on this phone until you download the model again.'),
      actions: <Widget>[
        VigilButton(label: 'Keep', variant: VigilButtonVariant.secondary, onPressed: () => Navigator.pop(ctx, false)),
        VigilButton(label: 'Delete', variant: VigilButtonVariant.critical, onPressed: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  return ok ?? false;
}
