import 'package:flutter/material.dart';

import '../../shared/widgets/dinna_logo.dart';

/// Marca no topo do painel, no lugar da AppBar. O toque volta para a home.
class PanelBrandBar extends StatelessWidget {
  const PanelBrandBar({super.key, required this.onLeave});

  final void Function(BuildContext context) onLeave;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: () => onLeave(context),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back, size: 18, color: scheme.onSurface),
                    const SizedBox(width: 8),
                    const DinnaLogo(size: 22),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
