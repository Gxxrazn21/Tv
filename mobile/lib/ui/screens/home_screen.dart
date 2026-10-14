import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/time_format.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/favorites_controller.dart';
import '../../state/settings_controller.dart';
import '../widgets/filter_bar.dart';
import '../widgets/loader.dart';
import '../widgets/match_card.dart';
import '../widgets/nav.dart';
import '../widgets/state_views.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _dayOffset = 0;
  MatchFilters _filters = const MatchFilters();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final favorites = context.watch<FavoritesController>();
    final repo = context.watch<Repository>();
    final fmt = TimeFormatter(settings.timezone);
    final day = fmt.today().add(Duration(days: _dayOffset));

    return Scaffold(
      appBar: AppBar(title: const Text('OpenFoot'), actions: commonActions(context)),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final o in const [-1, 0, 1])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(TimeFormatter.dayLabel(fmt.today().add(Duration(days: o)), fmt.today())),
                      selected: _dayOffset == o,
                      onSelected: (_) => setState(() => _dayOffset = o),
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.event, size: 18),
                  label: Text(_dayOffset.abs() > 1 ? TimeFormatter.dayLabel(day, fmt.today()) : 'Otra fecha'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: day,
                      firstDate: fmt.today().subtract(const Duration(days: 365)),
                      lastDate: fmt.today().add(const Duration(days: 365)),
                    );
                    if (picked != null) setState(() => _dayOffset = picked.difference(fmt.today()).inDays);
                  },
                ),
              ],
            ),
          ),
          FilterBar(filters: _filters, onChanged: (f) => setState(() => _filters = f)),
          Expanded(
            child: Loader<List<MatchSummary>>(
              formatter: fmt,
              deps: [repo, day, _filters.competition, _filters.country, settings.timezone],
              load: () => repo.matches(
                from: day,
                timezone: settings.timezone,
                competition: _filters.competition,
                country: _filters.country,
              ),
              autoRefresh: (data) => data.any((m) => m.phase == MatchPhase.live) ? const Duration(seconds: 60) : null,
              builder: (context, matches, refresh) => RefreshIndicator(
                onRefresh: refresh,
                child: _HomeList(matches: matches, formatter: fmt, settings: settings, favorites: favorites),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeList extends StatelessWidget {
  const _HomeList({required this.matches, required this.formatter, required this.settings, required this.favorites});

  final List<MatchSummary> matches;
  final TimeFormatter formatter;
  final SettingsController settings;
  final FavoritesController favorites;

  @override
  Widget build(BuildContext context) {
    final favTeams = {for (final f in favorites.teams) int.tryParse(f.id)};
    final favComps = {for (final f in favorites.competitions) f.id};
    bool isFav(MatchSummary m) =>
        favTeams.contains(m.home.id) || favTeams.contains(m.away.id) || favComps.contains(m.competition.code);

    final sections = <(String, String, List<MatchSummary>)>[
      ('favorites', 'Tus favoritos', matches.where(isFav).toList()),
      ('live', 'En directo', matches.where((m) => m.phase == MatchPhase.live).toList()),
      ('upcoming', 'Próximos', matches.where((m) => m.phase == MatchPhase.upcoming).toList()),
      ('finished', 'Finalizados', matches.where((m) => m.phase == MatchPhase.finished).toList()),
      (
        'other',
        'Aplazados, cancelados o sin confirmar',
        matches.where((m) => const {MatchPhase.postponed, MatchPhase.cancelled, MatchPhase.unknown}.contains(m.phase)).toList()
      ),
    ];

    final children = <Widget>[];
    if (settings.sectionVisible('featured')) children.add(const _FeaturedCompetitions());
    for (final (key, title, items) in sections) {
      if (items.isEmpty || (key != 'other' && !settings.sectionVisible(key))) continue;
      children.add(SectionHeader('$title (${items.length})'));
      children.addAll(items.map((m) => MatchCard(match: m, formatter: formatter, onTap: () => openMatch(context, m))));
    }
    if (matches.isEmpty) {
      children.add(const MessageView(
        icon: Icons.sports_soccer,
        title: 'No hay partidos para este día',
        detail: 'Solo se muestran competiciones con una fuente de datos integrada. Prueba otra fecha o quita filtros.',
      ));
    }
    children.add(const SizedBox(height: 24));
    return ListView(physics: const AlwaysScrollableScrollPhysics(), children: children);
  }
}

class _FeaturedCompetitions extends StatelessWidget {
  const _FeaturedCompetitions();

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repository>();
    return FutureBuilder<Loaded<List<Competition>>>(
      future: repo.competitions(),
      builder: (context, snap) {
        final featured = snap.data?.data.where((c) => c.featured).toList() ?? const [];
        if (featured.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader('Competiciones destacadas'),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final c in featured)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(label: Text(c.name), onPressed: () => openCompetition(context, c.code, c.name)),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
