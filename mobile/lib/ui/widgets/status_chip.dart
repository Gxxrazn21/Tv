import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';

String phaseLabel(MatchPhase p) => switch (p) {
      MatchPhase.live => 'EN DIRECTO',
      MatchPhase.upcoming => 'PRÓXIMO',
      MatchPhase.finished => 'FINALIZADO',
      MatchPhase.postponed => 'APLAZADO',
      MatchPhase.cancelled => 'CANCELADO',
      MatchPhase.unknown => 'SIN CONFIRMAR',
    };

/// Indicador de estado: el texto siempre acompaña al color (accesible sin percepción del color).
class StatusChip extends StatelessWidget {
  const StatusChip(this.phase, {super.key});

  final MatchPhase phase;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (phase) {
      MatchPhase.live => (AppTheme.live, Colors.white),
      MatchPhase.upcoming => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      MatchPhase.finished => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      _ => (scheme.errorContainer, scheme.onErrorContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (phase == MatchPhase.live) ...[
            const Icon(Icons.circle, size: 8, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Text(
            phaseLabel(phase),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700, letterSpacing: 0.4),
          ),
        ],
      ),
    );
  }
}
