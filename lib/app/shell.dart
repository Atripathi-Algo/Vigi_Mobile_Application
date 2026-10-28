import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/capture_sheet.dart';
import '../services/sfx.dart';
import '../vigil/vigil.dart';

/// Hosts the five tabs. The core button (index 2) is the assistant.
/// Android back on a tab root goes to Command; back on Command exits.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: shell.currentIndex == 0,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) shell.goBranch(0);
      },
      child: Scaffold(
        extendBody: true,
        backgroundColor: context.vigil.ground,
        body: StormFlicker(child: shell),
        bottomNavigationBar: VigilNavBar(
          current: VigilTab.values[shell.currentIndex],
          onSelected: (VigilTab t) {
            if (t.index != shell.currentIndex) SfxService.play(Sfx.tick);
            shell.goBranch(t.index, initialLocation: t.index == shell.currentIndex);
          },
        ),
      ),
    );
  }
}

/// Floating action button used by Ops and Vault tabs (octagon, 56).
class CaptureFab extends StatelessWidget {
  const CaptureFab({super.key, required this.type, this.icon = VigilIcons.plus, this.label = 'Capture'});

  final String type;
  final VigilIcons icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 84),
      child: OctagonButton(
        semanticLabel: label,
        onPressed: () => showCaptureSheet(context, type: type),
        child: VigilIcon(icon, color: context.vigil.onSignal),
      ),
    );
  }
}
