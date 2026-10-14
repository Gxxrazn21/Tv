import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/time_format.dart';
import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/favorites_controller.dart';
import '../../state/settings_controller.dart';
import '../widgets/loader.dart';
import '../widgets/nav.dart';
import '../widgets/state_views.dart';
import '../widgets/team_badge.dart';

const regionNames = {'europe': 'Europa', 'south_america': 'Sudamérica', 'international': 'Internacional'};

class CompetitionsScreen extends StatelessWidget {
  const CompetitionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repository>();
    final fmt = TimeFormatter(context.watch<SettingsController>().timezone);
    return Scaffold(
      appBar: AppBar(title: const Text('Competiciones'), actions: commonActions(context)),
      body: Loader<List<Competition>>(
        formatter: fmt,
        deps: [repo],
        load: repo.competitions,
        builder: (context, comps, refresh) => RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            children: [
              for (final region in regionNames.keys) ...[
                SectionHeader(regionNames[region]!),
                for (final c in comps.where((c) => c.region == region)) CompetitionTile(competition: c),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class CompetitionTile extends StatelessWidget {
  const CompetitionTile({super.key, required this.competition});

  final Competition competition;

  @override
  Widget build(BuildContext context) {
    final c = competition;
    final favs = context.watch<FavoritesController>();
    final fav = favs.isFavorite('competition', c.code);
    return ListTile(
      title: Text(c.name),
      subtitle: Text(c.hasData ? c.areaName : '${c.areaName} · Sin datos disponibles'),
      leading: c.hasData
          ? CompetitionLogo(url: c.emblemUrl, name: c.name, size: 32)
          : Icon(Icons.info_outline, color: Theme.of(context).colorScheme.outline),
      trailing: IconButton(
        tooltip: fav ? 'Quitar de favoritos' : 'Añadir a favoritos',
        icon: Icon(fav ? Icons.star : Icons.star_outline),
        onPressed: () => favs.toggle(Favorite(kind: 'competition', id: c.code, label: c.name, detail: c.areaName)),
      ),
      onTap: () {
        if (c.hasData) {
          openCompetition(context, c.code, c.name);
        } else {
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(c.name),
              content: Text(c.dataNote ??
                  'Esta competición no tiene una fuente de datos gratuita integrada. No mostramos datos que no podamos verificar.'),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
            ),
          );
        }
      },
    );
  }
}
