import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/time_format.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/favorites_controller.dart';
import '../../state/settings_controller.dart';
import '../widgets/match_card.dart';
import '../widgets/nav.dart';
import '../widgets/state_views.dart';

/// Favoritos guardados solo en este dispositivo (sin cuenta).
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final favs = context.watch<FavoritesController>();
    final settings = context.watch<SettingsController>();
    final repo = context.watch<Repository>();
    final fmt = TimeFormatter(settings.timezone);
    return Scaffold(
      appBar: AppBar(title: const Text('Favoritos'), actions: commonActions(context)),
      body: favs.items.isEmpty
          ? const MessageView(
              icon: Icons.star_outline,
              title: 'Aún no tienes favoritos',
              detail: 'Marca equipos desde la ficha de un partido y competiciones desde su lista. '
                  'Se guardan solo en este dispositivo.',
            )
          : ListView(
              children: [
                if (favs.teams.isNotEmpty) ...[
                  const SectionHeader('Próximos partidos de tus equipos'),
                  _UpcomingForTeams(teamIds: [for (final t in favs.teams) int.parse(t.id)], repo: repo, formatter: fmt),
                  const SectionHeader('Equipos'),
                  for (final t in favs.teams)
                    ListTile(
                      leading: const Icon(Icons.shield_outlined),
                      title: Text(t.label),
                      onTap: () => openTeam(context, int.parse(t.id), t.label),
                      trailing: IconButton(
                        tooltip: 'Quitar de favoritos',
                        icon: const Icon(Icons.star),
                        onPressed: () => favs.toggle(t),
                      ),
                    ),
                ],
                if (favs.competitions.isNotEmpty) ...[
                  const SectionHeader('Competiciones'),
                  for (final c in favs.competitions)
                    ListTile(
                      leading: const Icon(Icons.emoji_events_outlined),
                      title: Text(c.label),
                      subtitle: c.detail != null ? Text(c.detail!) : null,
                      onTap: () => openCompetition(context, c.id, c.label),
                      trailing: IconButton(
                        tooltip: 'Quitar de favoritos',
                        icon: const Icon(Icons.star),
                        onPressed: () => favs.toggle(c),
                      ),
                    ),
                ],
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _UpcomingForTeams extends StatelessWidget {
  const _UpcomingForTeams({required this.teamIds, required this.repo, required this.formatter});

  final List<int> teamIds;
  final Repository repo;
  final TimeFormatter formatter;

  Future<List<MatchSummary>> _load() async {
    final results = await Future.wait(teamIds.map((id) => repo.teamMatches(id).then((r) => r.data).catchError((_) => <MatchSummary>[])));
    final byId = <int, MatchSummary>{for (final list in results) for (final m in list) m.id: m};
    return byId.values.toList()..sort((a, b) => a.utcDate.compareTo(b.utcDate));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MatchSummary>>(
      key: ValueKey(teamIds.join(',')),
      future: _load(),
      builder: (context, snap) {
        if (!snap.hasData) return const LoadingView();
        final items = snap.data!.take(10).toList();
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('No hay próximos partidos disponibles para tus equipos.'),
          );
        }
        return Column(
          children: [
            for (final m in items) MatchCard(match: m, formatter: formatter, showDate: true, onTap: () => openMatch(context, m)),
          ],
        );
      },
    );
  }
}
