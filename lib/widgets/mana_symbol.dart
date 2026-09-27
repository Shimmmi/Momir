import 'package:flutter/material.dart';

import '../core/mana/mana_cost_parser.dart';

const _invertColors = ColorFilter.matrix(<double>[
  -1, 0, 0, 0, 255,
  0, -1, 0, 0, 255,
  0, 0, -1, 0, 255,
  0, 0, 0, 1, 0,
]);

class ManaSymbol extends StatelessWidget {
  const ManaSymbol({super.key, required this.code, this.size = 22});

  final String code;
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      manaAssetPath(code),
      width: size,
      height: size,
      filterQuality: FilterQuality.none,
      errorBuilder: (_, _, _) => Text(
        '{$code}',
        style: TextStyle(fontSize: size * 0.55, fontWeight: FontWeight.bold),
      ),
    );
    if (!isGenericMana(code)) return image;
    final ring = (size * 0.1).clamp(1.0, 2.5);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: ring),
        color: Colors.white,
      ),
      child: ClipOval(
        child: ColorFiltered(colorFilter: _invertColors, child: image),
      ),
    );
  }
}
