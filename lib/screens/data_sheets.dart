import 'package:flutter/material.dart';

import '../app/common.dart';
import '../app/fmt.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../vigil/vigil.dart';

Future<void> _sheet(BuildContext context, Widget child) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (BuildContext ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.viewInsetsOf(ctx).bottom + MediaQuery.paddingOf(ctx).bottom + 20),
        child: child,
      ),
    );

/// Rupees typed by the user to paise; null for anything that is not a positive amount.
int? parseRupees(String text) {
  final double? v = double.tryParse(text.trim().replaceAll(',', ''));
  if (v == null || v <= 0 || v > 100000000) return null;
  return (v * 100).round();
}

Future<void> showAddProtocolSheet(BuildContext context, VigilStore s) => _sheet(context, _AddProtocol(store: s));

Future<void> showAddBillSheet(BuildContext context, VigilStore s) => _sheet(context, _AddBill(store: s));

Future<void> showBudgetSheet(BuildContext context, VigilStore s) => _sheet(context, _Budget(store: s));

/// Asks before deleting. Returns true when deleted.
Future<bool> confirmDelete(BuildContext context, {required String title, required String message}) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        VigilButton(label: 'Keep', variant: VigilButtonVariant.secondary, onPressed: () => Navigator.pop(ctx, false)),
        VigilButton(label: 'Delete', variant: VigilButtonVariant.critical, onPressed: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  return ok ?? false;
}

class _AddProtocol extends StatefulWidget {
  const _AddProtocol({required this.store});

  final VigilStore store;

  @override
  State<_AddProtocol> createState() => _AddProtocolState();
}

class _AddProtocolState extends State<_AddProtocol> {
  static const List<String> _units = <String>['Pages', 'Min', 'ml', 'Times', 'km'];
  static const List<String> _dayLetters = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  final TextEditingController _name = TextEditingController();
  final TextEditingController _target = TextEditingController();
  String? _unit;
  bool _remind = false;
  int _remindMin = 21 * 60;
  final Set<int> _days = <int>{};

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  int? get _targetValue => int.tryParse(_target.text.trim());

  void _save() {
    if (_name.text.trim().isEmpty) return;
    widget.store.addProtocol(_name.text, unit: _unit, target: _unit == null ? null : _targetValue, remindMin: _remind ? _remindMin : null, days: _days.toList());
    Navigator.pop(context);
  }

  String get _summary {
    final List<String> p = <String>[
      _name.text.trim().isEmpty ? 'Your protocol' : _name.text.trim(),
      if (_unit != null && _targetValue != null) '$_targetValue ${_unit!.toLowerCase()}',
      _days.isEmpty || _days.length == 7 ? 'every day' : (_days.toList()..sort()).map((int d) => const <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1]).join(' '),
      if (_remind) 'reminder ${Fmt.hm(_remindMin)}',
    ];
    return p.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text('NEW PROTOCOL', style: t.h2),
      const SizedBox(height: 6),
      Text('A habit you want to check off. Streaks start from today.', style: t.caption.copyWith(color: c.textMuted)),
      const SizedBox(height: 14),
      VigilField(controller: _name, label: 'Name', hint: 'Read', autofocus: true, onChanged: (_) => setState(() {}), onSubmitted: (_) => _save()),
      const SizedBox(height: 12),
      Text('UNIT (OPTIONAL)', style: t.label.copyWith(color: c.textFaint)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: <Widget>[for (final String u in _units) SizedBox(width: (MediaQuery.sizeOf(context).width - 40 - 16) / 3, child: VigilFilterChip(label: u, selected: _unit == u, onTap: () => setState(() => _unit = _unit == u ? null : u)))]),
      if (_unit != null) ...<Widget>[
        const SizedBox(height: 12),
        VigilField(controller: _target, label: 'Daily target (${_unit!.toLowerCase()})', hint: '20', keyboardType: TextInputType.number, onChanged: (_) => setState(() {})),
      ],
      const SizedBox(height: 14),
      Text('DAYS', style: t.label.copyWith(color: c.textFaint)),
      const SizedBox(height: 6),
      Row(children: <Widget>[
        for (int i = 0; i < 7; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Semantics(
              button: true,
              selected: _days.contains(i + 1),
              label: const <String>['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][i],
              excludeSemantics: true,
              child: InkWell(
                onTap: () => setState(() => _days.contains(i + 1) ? _days.remove(i + 1) : _days.add(i + 1)),
                child: Container(
                  height: VigilSize.button,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _days.contains(i + 1) ? c.signal : Colors.transparent, border: Border.all(color: _days.contains(i + 1) ? c.signal : c.lineStrong)),
                  child: Text(_dayLetters[i], style: t.button.copyWith(color: _days.contains(i + 1) ? c.onSignal : c.textMuted)),
                ),
              ),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 4),
      Text(_days.isEmpty ? 'None picked means every day.' : '', style: t.micro.copyWith(color: c.textFaint, fontSize: 9.5)),
      const SizedBox(height: 8),
      Row(children: <Widget>[
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text('Reminder', style: t.rowTitle), Text(_remind ? 'At ${Fmt.hm(_remindMin)}, on the days above' : 'A nudge at a set time', style: t.caption.copyWith(color: c.textFaint))])),
        if (_remind)
          VigilButton(
            label: Fmt.hm(_remindMin),
            variant: VigilButtonVariant.secondary,
            onPressed: () async {
              final TimeOfDay? v = await pickVigilTime(context, _remindMin);
              if (v != null) setState(() => _remindMin = v.hour * 60 + v.minute);
            },
          ),
        const SizedBox(width: 8),
        VigilSwitch(value: _remind, onChanged: (bool v) => setState(() => _remind = v), semanticLabel: 'Reminder'),
      ]),
      const SizedBox(height: 12),
      Text(_summary, style: t.caption.copyWith(color: c.textMuted)),
      const SizedBox(height: 12),
      Align(alignment: Alignment.centerLeft, child: VigilButton(label: 'Add protocol', onPressed: _name.text.trim().isEmpty ? null : _save)),
    ]);
  }
}

class _AddBill extends StatefulWidget {
  const _AddBill({required this.store});

  final VigilStore store;

  @override
  State<_AddBill> createState() => _AddBillState();
}

class _AddBillState extends State<_AddBill> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  DateTime _due = DateTime.now().add(const Duration(days: 7));

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty && parseRupees(_amount.text) != null;

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? d = await showDatePicker(context: context, initialDate: _due, firstDate: DateTime(now.year, now.month, now.day), lastDate: DateTime(now.year + 2));
    if (d != null) setState(() => _due = d);
  }

  void _save() {
    final int? paise = parseRupees(_amount.text);
    if (!_valid || paise == null) return;
    widget.store.addBill(_name.text, paise, _due);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final Bill preview = Bill(id: '', name: '', dueAt: _due, paise: 0);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text('NEW BILL', style: t.h2),
      const SizedBox(height: 6),
      Text('K only tracks it. It never moves money.', style: t.caption.copyWith(color: c.textMuted)),
      const SizedBox(height: 14),
      VigilField(controller: _name, label: 'Name', hint: 'Electricity', autofocus: true, onChanged: (_) => setState(() {})),
      const SizedBox(height: 10),
      VigilField(
        controller: _amount,
        label: 'Amount',
        hint: 'Amount in rupees',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 10),
      Align(alignment: Alignment.centerLeft, child: VigilButton(label: 'Due ${preview.due}', variant: VigilButtonVariant.secondary, onPressed: _pickDate)),
      const SizedBox(height: 14),
      Align(alignment: Alignment.centerLeft, child: VigilButton(label: 'Add bill', onPressed: _valid ? _save : null)),
    ]);
  }
}

class _Budget extends StatefulWidget {
  const _Budget({required this.store});

  final VigilStore store;

  @override
  State<_Budget> createState() => _BudgetState();
}

class _BudgetState extends State<_Budget> {
  late final TextEditingController _amount = TextEditingController(text: widget.store.monthBudgetPaise > 0 ? (widget.store.monthBudgetPaise / 100).round().toString() : '');
  late bool _alert = widget.store.budgetAlert;
  late bool _rollover = widget.store.budgetRollover;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final VigilStore s = widget.store;
    final int? paise = parseRupees(_amount.text);
    final int spent = s.monthSpentPaise;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text('MONTHLY BUDGET', style: t.h2),
      const SizedBox(height: 6),
      Text('Your own limit for this month\'s spending. The Ledger measures pace against it. Bills count toward it when you log them as expenses.', style: t.caption.copyWith(color: c.textMuted)),
      const SizedBox(height: 14),
      VigilField(
        controller: _amount,
        label: 'Monthly limit (₹)',
        hint: 'Amount in rupees',
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
        for (final int v in const <int>[20000, 25000, 30000]) SizedBox(width: (MediaQuery.sizeOf(context).width - 40 - 16) / 3, child: VigilFilterChip(label: Fmt.money(v * 100), selected: paise == v * 100, onTap: () => setState(() => _amount.text = '$v'))),
      ]),
      const SizedBox(height: 14),
      Row(children: <Widget>[
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text('Alert me at 80 %', style: t.rowTitle), Text(paise == null ? 'One nudge when spending gets close' : 'One nudge when spend crosses ${Fmt.money((paise * 0.8).round())}', style: t.caption.copyWith(color: c.textFaint))])),
        VigilSwitch(value: _alert, onChanged: (bool v) => setState(() => _alert = v), semanticLabel: 'Alert me at 80 percent'),
      ]),
      const SizedBox(height: 10),
      Row(children: <Widget>[
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text('Roll unspent into next month', style: t.rowTitle), Text('Adds what is left at the end of a month to the next', style: t.caption.copyWith(color: c.textFaint))])),
        VigilSwitch(value: _rollover, onChanged: (bool v) => setState(() => _rollover = v), semanticLabel: 'Roll unspent into next month'),
      ]),
      const SizedBox(height: 10),
      Text('You\'ve spent ${Fmt.money(spent)} so far${paise == null ? '' : ' · ${(spent * 100 / paise).round()} %'}', style: t.caption.copyWith(color: c.textMuted)),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
        VigilButton(
          label: 'Save budget',
          onPressed: paise == null
              ? null
              : () {
                  s
                    ..budgetAlert = _alert
                    ..budgetRollover = _rollover;
                  s.setBudget(paise);
                  Navigator.pop(context);
                },
        ),
        if (s.monthBudgetPaise > 0)
          VigilButton(
            label: 'Remove budget',
            variant: VigilButtonVariant.secondary,
            onPressed: () {
              s.setBudget(0);
              Navigator.pop(context);
            },
          ),
      ]),
    ]);
  }
}
