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

/// Partidos de una competición: los últimos 3 días y los próximos 10.
class CompetitionScreen extends StatelessWidget {
  const CompetitionScreen({super.key, required this.code, required this.name});

  final String code;
  final String name;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final repo = context.watch<Repository>();
    final favs = context.watch<FavoritesController>();
    final fmt = TimeFormatter(settings.timezone);
    final today = fmt.today();
    final fav = favs.isFavorite('competition', code);
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(
            tooltip: fav ? 'Quitar de favoritos' : 'Añadir a favoritos',
            icon: Icon(fav ? Icons.star : Icons.star_outline),
            onPressed: () => favs.toggle(Favorite(kind: 'competition', id: code, label: name)),
          ),
        ],
      ),
      body: Loader<List<MatchSummary>>(
        formatter: fmt,
        deps: [repo, code, settings.timezone],
        load: () => repo.matches(
          from: today.subtract(const Duration(days: 3)),
          to: today.add(const Duration(days: 10)),
          timezone: settings.timezone,
          competition: code,
        ),
        builder: (context, matches, refresh) => RefreshIndicator(
          onRefresh: refresh,
          child: matches.isEmpty
              ? ListView(children: const [MessageView(icon: Icons.event_busy, title: 'Sin partidos en estas fechas')])
              : ListView(
                  children: [
                    for (final m in matches)
                      MatchCard(match: m, formatter: fmt, showDate: true, onTap: () => openMatch(context, m)),
                    const SizedBox(height: 24),
                  ],
                ),
        ),
      ),
    );
  }
}
