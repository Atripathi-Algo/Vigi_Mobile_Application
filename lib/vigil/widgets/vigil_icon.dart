import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/vigil_tokens.dart';

/// Icon set shipped in `assets/svg/icons/` (24 grid, 1.6 stroke, butt caps).
enum VigilIcons {
  command,
  ops,
  protocols,
  vault,
  deepOps,
  water,
  alert,
  voice,
  standDown,
  loadout,
  plus,
  minus,
  close,
  chevronRight,
  chevronLeft,
  chevronDown,
  arrowRight,
  check,
  search,
  calendar,
  sync,
  history,
  tag,
  edit,
  sun,
  pause,
  play,
  timer,
  shield,
  sleep,
  screen,
}

extension VigilIconsAsset on VigilIcons {
  /// camelCase enum name → snake_case file name.
  String get asset {
    final String snake = name.replaceAllMapped(RegExp('[A-Z]'), (Match m) => '_${m[0]!.toLowerCase()}');
    return 'assets/svg/icons/$snake.svg';
  }
}

/// Tinted SVG icon. Decorative unless [semanticLabel] is given.
class VigilIcon extends StatelessWidget {
  const VigilIcon(this.icon, {super.key, this.size = VigilSize.icon, this.color, this.semanticLabel});

  final VigilIcons icon;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Color tint = color ?? IconTheme.of(context).color ?? context.vigil.text;
    return SvgPicture.asset(
      icon.asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}
