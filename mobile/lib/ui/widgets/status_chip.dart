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

String _short(MatchPhase p) => switch (p) {
      MatchPhase.live => 'VIVO',
      MatchPhase.upcoming => 'PRÓX.',
      MatchPhase.finished => 'FINAL',
      MatchPhase.postponed => 'APLAZ.',
      MatchPhase.cancelled => 'CANC.',
      MatchPhase.unknown => '¿?',
    };

/// Indicador de estado: el texto siempre acompaña al color (accesible sin percepción del color).
class StatusChip extends StatelessWidget {
  const StatusChip(this.phase, {super.key, this.compact = false});

  final MatchPhase phase;
  final bool compact;

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
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 2 : 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (phase == MatchPhase.live && !compact) ...[
            const Icon(Icons.circle, size: 8, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Text(
            compact ? _short(phase) : phaseLabel(phase),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700, letterSpacing: 0.4),
          ),
        ],
      ),
    );
  }
}
