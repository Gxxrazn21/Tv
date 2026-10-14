import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/time_format.dart';
import '../../data/models.dart';
import 'status_chip.dart';
import 'team_badge.dart';

/// Tarjeta compacta: columna de hora/estado y dos filas (local y visitante) con escudo,
/// nombre y marcador. Opcionalmente muestra la competición arriba.
class MatchCard extends StatelessWidget {
  const MatchCard({
    super.key,
    required this.match,
    required this.formatter,
    this.onTap,
    this.showDate = false,
    this.showCompetition = true,
  });

  final MatchSummary match;
  final TimeFormatter formatter;
  final VoidCallback? onTap;
  final bool showDate;
  final bool showCompetition;

  String get _semanticLabel {
    final m = match;
    final score = m.hasScore ? ', ${m.homeScore} a ${m.awayScore}' : '';
    return '${m.home.name} contra ${m.away.name}, ${phaseLabel(m.phase).toLowerCase()}$score, '
        '${m.competition.name}, ${formatter.full(m.utcDate)}';
  }

  @override
  Widget build(BuildContext context) {
    final m = match;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final live = m.phase == MatchPhase.live;
    final finished = m.phase == MatchPhase.finished;
    int? winner;
    if (finished && m.hasScore && m.homeScore != m.awayScore) {
      winner = m.homeScore! > m.awayScore! ? 0 : 1;
    }
    return Card(
      child: Semantics(
        button: onTap != null,
        label: _semanticLabel,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showCompetition) ...[
                  Row(
                    children: [
                      CompetitionLogo(url: m.competition.emblemUrl, name: m.competition.name, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          m.competition.name + (m.matchday != null ? ' · Jornada ${m.matchday}' : ''),
                          style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final w in <Widget>[
                          if (live || finished || m.phase != MatchPhase.upcoming)
                            StatusChip(m.phase, compact: true)
                          else
                            Text(formatter.time(m.utcDate), style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          if (showDate || live || finished)
                            Text(
                              showDate ? formatter.date(m.utcDate) : formatter.time(m.utcDate),
                              style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          if (m.wasRescheduled)
                            Text('Cambio de hora', style: text.labelSmall?.copyWith(color: scheme.error)),
                          ])
                            // Se reduce si no cabe (textos grandes de accesibilidad).
                            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: w),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 52, color: scheme.outlineVariant.withValues(alpha: 0.35)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        children: [
                          _TeamLine(team: m.home, score: m.homeScore, live: live, bold: winner == 0, dim: winner == 1),
                          const SizedBox(height: 8),
                          _TeamLine(team: m.away, score: m.awayScore, live: live, bold: winner == 1, dim: winner == 0),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamLine extends StatelessWidget {
  const _TeamLine({required this.team, required this.score, required this.live, this.bold = false, this.dim = false});

  final Team team;
  final int? score;
  final bool live;
  final bool bold;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final color = dim ? scheme.onSurfaceVariant : scheme.onSurface;
    return Row(
      children: [
        TeamBadge(team, size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            team.displayName,
            overflow: TextOverflow.ellipsis,
            style: text.bodyLarge?.copyWith(color: color, fontWeight: bold ? FontWeight.w800 : FontWeight.w500),
          ),
        ),
        if (score != null)
          Text(
            '$score',
            style: text.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: live ? AppTheme.live : color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}

/// Cabecera de un grupo de partidos de la misma competición.
class CompetitionHeader extends StatelessWidget {
  const CompetitionHeader({super.key, required this.competition, this.onTap, this.count});

  final CompetitionRef competition;
  final VoidCallback? onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 6),
        child: Row(
          children: [
            CompetitionLogo(url: competition.emblemUrl, name: competition.name, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                header: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(competition.name, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    Text(competition.areaName, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
            if (count != null) Text('$count', style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
            if (onTap != null) Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
