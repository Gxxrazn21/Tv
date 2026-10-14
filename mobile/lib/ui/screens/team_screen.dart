import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/time_format.dart';
import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/favorites_controller.dart';
import '../../state/settings_controller.dart';
import '../widgets/loader.dart';
import '../widgets/match_card.dart';
import '../widgets/nav.dart';
import '../widgets/state_views.dart';

class TeamScreen extends StatelessWidget {
  const TeamScreen({super.key, required this.teamId, required this.name});

  final int teamId;
  final String name;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final repo = context.watch<Repository>();
    final favs = context.watch<FavoritesController>();
    final fmt = TimeFormatter(settings.timezone);
    final fav = favs.isFavorite('team', '$teamId');
    Widget list(bool upcoming) => Loader<List<MatchSummary>>(
          formatter: fmt,
          deps: [repo, teamId, upcoming],
          load: () => repo.teamMatches(teamId, upcoming: upcoming),
          builder: (context, matches, refresh) => RefreshIndicator(
            onRefresh: refresh,
            child: matches.isEmpty
                ? ListView(children: const [MessageView(icon: Icons.event_busy, title: 'Sin partidos disponibles')])
                : ListView(children: [
                    for (final m in matches)
                      MatchCard(match: m, formatter: fmt, showDate: true, onTap: () => openMatch(context, m)),
                  ]),
          ),
        );
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(name),
          actions: [
            IconButton(
              tooltip: fav ? 'Quitar de favoritos' : 'Añadir a favoritos',
              icon: Icon(fav ? Icons.star : Icons.star_outline),
              onPressed: () => favs.toggle(Favorite(kind: 'team', id: '$teamId', label: name)),
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Próximos'), Tab(text: 'Recientes')]),
        ),
        body: TabBarView(children: [list(true), list(false)]),
      ),
    );
  }
}
