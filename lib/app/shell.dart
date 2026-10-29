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
        body: StormFlicker(child: _TabSwitch(index: shell.currentIndex, child: shell)),
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

/// A short shared-axis feel when the tab changes: the incoming tab fades in while sliding 4 % from the side it
/// is on. The tabs stay mounted (they are an indexed stack), so only the wrapper animates. Skipped with
/// reduce-motion.
class _TabSwitch extends StatefulWidget {
  const _TabSwitch({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_TabSwitch> createState() => _TabSwitchState();
}

class _TabSwitchState extends State<_TabSwitch> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 240), value: 1);
  int _dir = 1;

  @override
  void didUpdateWidget(_TabSwitch old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && !MediaQuery.disableAnimationsOf(context)) {
      _dir = widget.index > old.index ? 1 : -1;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        final double t = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: 0.35 + 0.65 * t,
          child: Transform.translate(offset: Offset(_dir * (1 - t) * 0.04 * MediaQuery.sizeOf(context).width, 0), child: child),
        );
      },
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
