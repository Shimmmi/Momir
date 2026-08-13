import 'package:flutter/material.dart';

import '../core/mana/mana_cost_parser.dart';

class ManaSymbol extends StatelessWidget {
  const ManaSymbol({super.key, required this.code, this.size = 22});

  final String code;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      manaAssetPath(code),
      width: size,
      height: size,
      filterQuality: FilterQuality.none,
      errorBuilder: (_, _, _) => Text(
        '{$code}',
        style: TextStyle(fontSize: size * 0.55, fontWeight: FontWeight.bold),
      ),
    );
  }
}
