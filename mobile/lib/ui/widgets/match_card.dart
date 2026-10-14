import 'package:flutter/material.dart';

import '../../core/time_format.dart';
import '../../data/models.dart';
import 'status_chip.dart';
import 'team_badge.dart';

class MatchCard extends StatelessWidget {
  const MatchCard({super.key, required this.match, required this.formatter, this.onTap, this.showDate = false});

  final MatchSummary match;
  final TimeFormatter formatter;
  final VoidCallback? onTap;
  final bool showDate;

  String get _semanticLabel {
    final m = match;
    final score = m.hasScore ? ', ${m.homeScore} a ${m.awayScore}' : '';
    return '${m.home.name} contra ${m.away.name}, ${phaseLabel(m.phase).toLowerCase()}$score, '
        '${m.competition.name}, ${formatter.full(m.utcDate)}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final m = match;
    return Card(
      child: Semantics(
        button: onTap != null,
        label: _semanticLabel,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.competition.name + (m.matchday != null ? ' · J${m.matchday}' : ''),
                        style: text.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    StatusChip(m.phase),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _TeamRow(team: m.home, score: m.homeScore, showScore: m.hasScore)),
                    SizedBox(
                      width: 72,
                      child: Column(
                        children: [
                          Text(formatter.time(m.utcDate), style: text.titleSmall),
                          if (showDate) Text(formatter.date(m.utcDate), style: text.labelSmall),
                          if (m.wasRescheduled)
                            Text('Horario cambiado', style: text.labelSmall?.copyWith(color: Theme.of(context).colorScheme.error)),
                        ],
                      ),
                    ),
                    Expanded(child: _TeamRow(team: m.away, score: m.awayScore, showScore: m.hasScore, alignEnd: true)),
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

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.team, required this.score, required this.showScore, this.alignEnd = false});

  final Team team;
  final int? score;
  final bool showScore;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final children = <Widget>[
      TeamBadge(team, size: 30),
      const SizedBox(width: 8),
      Flexible(
        child: Text(team.displayName, style: text.bodyMedium, overflow: TextOverflow.ellipsis, textAlign: alignEnd ? TextAlign.end : TextAlign.start),
      ),
      if (showScore) ...[
        const SizedBox(width: 8),
        Text('${score ?? '-'}', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      ],
    ];
    return Row(
      mainAxisAlignment: alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: alignEnd ? children.reversed.toList() : children,
    );
  }
}
