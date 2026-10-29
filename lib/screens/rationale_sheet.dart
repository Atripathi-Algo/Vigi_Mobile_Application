import 'package:flutter/material.dart';

import '../vigil/vigil.dart';

/// "Before Android asks": a short sheet that says why K needs a permission, shown the first time a feature needs it.
/// Returns true when the user taps the allow button (the caller then asks Android), false for "Not now".
Future<bool> showRationaleSheet(
  BuildContext context, {
  required String title,
  required String why,
  required VigilIcons icon,
  String allowLabel = 'Continue',
  String? note,
}) async {
  final bool? ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (BuildContext ctx) {
      final c = ctx.vigil;
      final t = ctx.vtype;
      return Padding(
        padding: EdgeInsets.fromLTRB(24, 4, 24, MediaQuery.paddingOf(ctx).bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(gradient: KTile.violet.gradient, borderRadius: BorderRadius.circular(KRadius.tile)),
              child: Center(child: VigilIcon(icon, size: 26, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 16),
          Text('Before Android asks', style: t.label.copyWith(color: c.violet), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(title, style: t.h2, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(why, style: t.body.copyWith(color: c.textMuted), textAlign: TextAlign.center),
          if (note != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(note, style: t.caption.copyWith(color: c.textFaint), textAlign: TextAlign.center),
          ],
          const SizedBox(height: 22),
          VigilButton(label: allowLabel, size: VigilButtonSize.large, expand: true, onPressed: () => Navigator.pop(ctx, true)),
          const SizedBox(height: 6),
          Center(child: VigilButton(label: 'Not now', variant: VigilButtonVariant.ghost, onPressed: () => Navigator.pop(ctx, false))),
        ]),
      );
    },
  );
  return ok ?? false;
}
