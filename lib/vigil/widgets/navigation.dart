import 'package:flutter/material.dart';

import '../theme/vigil_tokens.dart';
import 'buttons.dart';
import 'hud.dart';
import 'vigil_icon.dart';

/// Primary tabs. Index 2 is the raised core VIGIL button (assistant).
enum VigilTab { command, ops, vigil, protocols, vault }

/// Bottom navigation: 66 px bar + bottom inset (min 18), five slots,
/// the centre octagon raised 20 px above the bar.
///
/// Use with `Scaffold(extendBody: true, bottomNavigationBar: VigilNavBar(...))`
/// so content scrolls under the raised button's transparent strip.
class VigilNavBar extends StatelessWidget {
  const VigilNavBar({super.key, required this.current, required this.onSelected});

  final VigilTab current;
  final ValueChanged<VigilTab> onSelected;

  static const List<(VigilTab, VigilIcons?, String)> _items = <(VigilTab, VigilIcons?, String)>[
    (VigilTab.command, VigilIcons.command, 'Today'),
    (VigilTab.ops, VigilIcons.ops, 'Plan'),
    (VigilTab.vigil, null, 'K'),
    (VigilTab.protocols, VigilIcons.protocols, 'Habits'),
    (VigilTab.vault, VigilIcons.vault, 'Money'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final double inset = MediaQuery.paddingOf(context).bottom;
    final double bottom = inset < VigilSize.navMinInset ? VigilSize.navMinInset : inset;
    final double barHeight = VigilSize.navBar + bottom;

    return SizedBox(
      height: barHeight + VigilSize.coreLift,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: barHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.navBar,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(top: BorderSide(color: c.line)),
                boxShadow: <BoxShadow>[BoxShadow(color: c.shadow.withValues(alpha: c.isDark ? 0.4 : 0.18), blurRadius: 30, offset: const Offset(0, -10), spreadRadius: -12)],
              ),
              child: Padding(
                padding: EdgeInsets.only(left: 6, right: 6, bottom: bottom),
                child: Row(
                  children: <Widget>[
                    for (final (VigilTab tab, VigilIcons? icon, String label) in _items)
                      Expanded(
                        child: tab == VigilTab.vigil
                            ? _CoreLabel(label: label, active: current == tab, style: t.micro)
                            : _NavItem(
                                icon: icon!,
                                label: label,
                                active: current == tab,
                                onTap: () => onSelected(tab),
                              ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: OctagonButton(
                size: VigilSize.core,
                semanticLabel: 'K assistant',
                onPressed: () => onSelected(VigilTab.vigil),
                child: const CoreEmblem(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.active, required this.onTap});

  final VigilIcons icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final Color color = active ? c.signal2 : c.textFaint;
    final bool big = MediaQuery.textScalerOf(context).scale(10) >= 13; // 1.3x and up: icon only
    return Semantics(
      selected: active,
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AnimatedContainer(
              duration: VigilMotion.fast,
              width: 52,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(gradient: active ? c.softGradient : null, borderRadius: BorderRadius.circular(KRadius.pill)),
              child: VigilIcon(icon, color: color),
            ),
            if (!big) ...<Widget>[
              const SizedBox(height: 3),
              Text(label, style: t.micro.copyWith(color: color, fontWeight: active ? FontWeight.w600 : FontWeight.w500), maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
            ],
          ],
        ),
      ),
    );
  }
}

class _CoreLabel extends StatelessWidget {
  const _CoreLabel({required this.label, required this.active, required this.style});

  final String label;
  final bool active;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    return ExcludeSemantics(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(label, style: style.copyWith(color: active ? c.signal2 : c.textMuted, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

/// Standard VIGIL screen frame: grid texture, safe area, 20 px gutter,
/// title row with optional subtitle and trailing actions.
class VigilScaffold extends StatelessWidget {
  const VigilScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const <Widget>[],
    this.leading,
    this.tab,
    this.onTab,
    this.floatingActionButton,
    this.stealth = false,
    this.mark = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;
  final Widget body;

  /// When set, the bottom nav is shown with this tab active.
  final VigilTab? tab;
  final ValueChanged<VigilTab>? onTab;
  final Widget? floatingActionButton;

  /// Deep Ops / immersive screens use the darker stealth ground, no grid.
  final bool stealth;

  /// Tab roots show the K badge before the title.
  final bool mark;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final Widget header = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: VigilSize.touch),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[leading!, const SizedBox(width: 12)] else if (mark) ...<Widget>[const KBadge(), const SizedBox(width: 12)],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Semantics(header: true, child: Text(title, style: t.section)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: t.meta.copyWith(color: c.textMuted)),
                  ),
              ],
            ),
          ),
          for (int i = 0; i < actions.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 8),
            actions[i],
          ],
        ],
      ),
    );

    final Widget content = SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(VigilSpace.gutter, 12, VigilSpace.gutter, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            header,
            const SizedBox(height: VigilSpace.stack),
            Expanded(child: body),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: stealth ? c.stealth : c.ground,
      extendBody: tab != null,
      body: content,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: tab == null ? null : VigilNavBar(current: tab!, onSelected: onTab ?? (_) {}),
    );
  }
}
