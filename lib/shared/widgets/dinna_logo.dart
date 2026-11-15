import 'package:flutter/material.dart';

/// Marca "dinna." com o ponto em terracota. Use [size] menor no header.
class DinnaLogo extends StatelessWidget {
  const DinnaLogo({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text.rich(
      TextSpan(
        text: 'dinna',
        style: TextStyle(
          fontSize: size,
          height: 1.0,
          fontWeight: FontWeight.w700,
          letterSpacing: size * -0.035,
          color: theme.colorScheme.onSurface,
        ),
        children: [
          TextSpan(
            text: '.',
            style: TextStyle(color: theme.colorScheme.primary),
          ),
        ],
      ),
    );
  }
}
