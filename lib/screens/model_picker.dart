import 'package:flutter/material.dart';

import '../api/ai_models.dart';
import '../app/common.dart';
import '../vigil/vigil.dart';

const Color _green = Color(0xFF4ADE80);
const Color _amber = Color(0xFFFFA94D);

/// Green for free or very cheap, amber for paid, red for premium, grey when the price is not known.
Color tierColor(BuildContext context, ModelTier tier) => switch (tier) {
      ModelTier.free || ModelTier.cheap => _green,
      ModelTier.paid => _amber,
      ModelTier.premium => context.vigil.critical,
      ModelTier.unrated => context.vigil.textMuted,
    };

/// Small bordered label. The word is always shown, so colour is never the only signal.
class ModelTierBadge extends StatelessWidget {
  const ModelTierBadge(this.tier, {super.key});

  final ModelTier tier;

  @override
  Widget build(BuildContext context) {
    final Color col = tierColor(context, tier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: col.withValues(alpha: 0.12), border: Border.all(color: col)),
      child: Text(tier.label, style: context.vtype.micro.copyWith(color: col, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

/// Bottom sheet listing the models with how each one is billed. Returns the one tapped, or null.
/// [service] is the service the screen is set to now; it enables "Load live list" and is listed first.
Future<AiModel?> showModelPicker(BuildContext context, {required AiService? service, required String apiKey, required String selectedId}) {
  return showModalBottomSheet<AiModel>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (BuildContext ctx) => _ModelSheet(service: service, apiKey: apiKey, selectedId: selectedId),
  );
}

String _serviceNote(AiService s) => switch (s) {
      AiService.gemini => 'FREE TIER',
      AiService.groq => 'FREE PLAN',
      AiService.openrouter => 'LIVE PRICES',
      AiService.openai => 'PAID',
      AiService.anthropic => 'PAID',
    };

class _ModelSheet extends StatefulWidget {
  const _ModelSheet({required this.service, required this.apiKey, required this.selectedId});

  final AiService? service;
  final String apiKey;
  final String selectedId;

  @override
  State<_ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<_ModelSheet> {
  final TextEditingController _q = TextEditingController();
  String _view = 'all';
  List<AiModel> _live = const <AiModel>[];
  bool _loading = false;
  String? _note;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _loadLive() async {
    final AiService? s = widget.service;
    if (s == null) return;
    setState(() {
      _loading = true;
      _note = null;
    });
    final LiveModels r = await fetchLiveModels(s, apiKey: widget.apiKey);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.error != null) {
        _note = r.error;
      } else {
        _live = r.models;
        _note = '${r.models.length} models from ${s.label}.';
      }
    });
  }

  List<Object> _rows() {
    final String q = _q.text.trim().toLowerCase();
    bool keep(AiModel m) => (_view == 'all' || m.tier.isGreen) && (q.isEmpty || m.id.toLowerCase().contains(q) || m.label.toLowerCase().contains(q));
    final AiService? cur = widget.service;
    final List<Object> rows = <Object>[];
    final List<AiModel> live = _live.where(keep).toList();
    if (cur != null && live.isNotEmpty) {
      rows.add('LIVE · ${cur.label} · ${live.length}');
      rows.addAll(live);
    }
    for (final AiService s in <AiService>[if (cur != null) cur, ...AiService.values.where((AiService x) => x != cur)]) {
      if (_live.isNotEmpty && s == cur) continue; // the live list replaces the curated one for this service
      final List<AiModel> ms = modelsFor(s).where(keep).toList();
      if (ms.isEmpty) continue;
      rows.add('${s.label} · ${_serviceNote(s)}');
      rows.addAll(ms);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final List<Object> rows = _rows();
    final double height = MediaQuery.sizeOf(context).height * 0.9;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: ListView.builder(
          padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.paddingOf(context).bottom + 20),
          itemCount: rows.length + 1,
          itemBuilder: (BuildContext ctx, int i) {
            if (i == 0) return _header(context);
            final Object r = rows[i - 1];
            if (r is String) {
              return Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 6),
                child: Text(r, style: t.label.copyWith(color: c.textFaint)),
              );
            }
            return _row(context, r as AiModel);
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final AiService? svc = widget.service;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text('MODELS', style: t.h2),
      const SizedBox(height: 10),
      const Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
        ModelTierBadge(ModelTier.free),
        ModelTierBadge(ModelTier.cheap),
        ModelTierBadge(ModelTier.paid),
        ModelTierBadge(ModelTier.premium),
      ]),
      const SizedBox(height: 8),
      Text(
        'Green: free, or paid at \$1.50 or less per 1M output tokens. Amber: up to \$10. Red: above \$10. Prices are approximate and change; check the provider. Each service needs its own key, and K keeps one per service.',
        style: t.caption.copyWith(color: c.textMuted),
      ),
      const SizedBox(height: 14),
      VigilSegmented<String>(
        segments: const <(String, String)>[('all', 'ALL'), ('green', 'FREE & CHEAP')],
        selected: _view,
        onSelected: (String v) => setState(() => _view = v),
      ),
      const SizedBox(height: 10),
      VigilField(controller: _q, hint: 'Search models', semanticLabel: 'Search models', onChanged: (_) => setState(() {})),
      if (svc != null) ...<Widget>[
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: VigilButton(
            label: _loading ? 'Loading…' : 'Load live list · ${svc.label}',
            variant: VigilButtonVariant.secondary,
            onPressed: _loading ? null : _loadLive,
          ),
        ),
      ],
      if (_note != null) ...<Widget>[
        const SizedBox(height: 8),
        Semantics(liveRegion: true, child: Text(_note!, style: t.meta.copyWith(color: c.textMuted, fontSize: 12))),
      ],
    ]);
  }

  Widget _row(BuildContext context, AiModel m) {
    final c = context.vigil;
    final t = context.vtype;
    final bool selected = m.id == widget.selectedId && m.service == widget.service;
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: '${m.label}. ${m.tier.label}. ${m.price}',
      child: InkWell(
        onTap: () => Navigator.pop(context, m),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: selected ? c.signalTint(0.10) : c.surface,
            border: Border.all(color: selected ? c.signal : c.line),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(m.label, style: t.rowTitle),
                const SizedBox(height: 2),
                Text(m.id, style: t.micro.copyWith(color: c.textFaint, fontSize: 10)),
                const SizedBox(height: 4),
                Text(m.note.isEmpty ? m.price : '${m.price} · ${m.note}', style: t.caption.copyWith(color: c.textMuted, fontSize: 12)),
              ]),
            ),
            const SizedBox(width: 10),
            ModelTierBadge(m.tier),
          ]),
        ),
      ),
    );
  }
}
