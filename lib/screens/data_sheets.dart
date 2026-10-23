import 'package:flutter/material.dart';

import '../app/common.dart';
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
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty) return;
    widget.store.addProtocol(_name.text);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text('NEW PROTOCOL', style: t.h2),
      const SizedBox(height: 6),
      Text('A habit you want to check off every day. Streaks start from today.', style: t.caption.copyWith(color: c.textMuted)),
      const SizedBox(height: 14),
      VigilField(controller: _name, label: 'Name', hint: 'Read 20 pages', autofocus: true, onChanged: (_) => setState(() {}), onSubmitted: (_) => _save()),
      const SizedBox(height: 14),
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
      Text('VIGIL only tracks it. It never moves money.', style: t.caption.copyWith(color: c.textMuted)),
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

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final int? paise = parseRupees(_amount.text);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text('MONTHLY BUDGET', style: t.h2),
      const SizedBox(height: 6),
      Text('Your own limit for this month\'s spending. The Ledger measures pace against it.', style: t.caption.copyWith(color: c.textMuted)),
      const SizedBox(height: 14),
      VigilField(
        controller: _amount,
        label: 'Budget',
        hint: 'Amount in rupees',
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
        VigilButton(
          label: 'Save',
          onPressed: paise == null
              ? null
              : () {
                  widget.store.setBudget(paise);
                  Navigator.pop(context);
                },
        ),
        if (widget.store.monthBudgetPaise > 0)
          VigilButton(
            label: 'Remove budget',
            variant: VigilButtonVariant.secondary,
            onPressed: () {
              widget.store.setBudget(0);
              Navigator.pop(context);
            },
          ),
      ]),
    ]);
  }
}
