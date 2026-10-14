import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
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
import '../widgets/team_badge.dart';

enum PhaseFilter { all, live, upcoming, finished }

const _phaseFilterLabels = {
  PhaseFilter.all: 'Todos',
  PhaseFilter.live: 'En directo',
  PhaseFilter.upcoming: 'Próximos',
  PhaseFilter.finished: 'Finalizados',
};

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _dayOffset = 0;
  MatchFilters _filters = const MatchFilters();
  PhaseFilter _phase = PhaseFilter.all;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final favorites = context.watch<FavoritesController>();
    final repo = context.watch<Repository>();
    final fmt = TimeFormatter(settings.timezone);
    final today = fmt.today();
    final day = today.add(Duration(days: _dayOffset));

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.sports_soccer, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('OpenFoot'),
          ],
        ),
        actions: commonActions(context),
      ),
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
                      label: Text(TimeFormatter.dayLabel(today.add(Duration(days: o)), today)),
                      selected: _dayOffset == o,
                      onSelected: (_) => setState(() => _dayOffset = o),
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.event, size: 18),
                  label: Text(_dayOffset.abs() > 1 ? TimeFormatter.dayLabel(day, today) : 'Otra fecha'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: day,
                      firstDate: today.subtract(const Duration(days: 365)),
                      lastDate: today.add(const Duration(days: 365)),
                    );
                    if (picked != null) setState(() => _dayOffset = picked.difference(today).inDays);
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
                child: _HomeList(
                  matches: matches,
                  formatter: fmt,
                  settings: settings,
                  favorites: favorites,
                  phase: _phase,
                  onPhase: (p) => setState(() => _phase = p),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _matchesPhase(MatchSummary m, PhaseFilter f) => switch (f) {
      PhaseFilter.all => true,
      PhaseFilter.live => m.phase == MatchPhase.live,
      PhaseFilter.upcoming => m.phase == MatchPhase.upcoming,
      PhaseFilter.finished => m.phase == MatchPhase.finished,
    };

class _HomeList extends StatelessWidget {
  const _HomeList({
    required this.matches,
    required this.formatter,
    required this.settings,
    required this.favorites,
    required this.phase,
    required this.onPhase,
  });

  final List<MatchSummary> matches;
  final TimeFormatter formatter;
  final SettingsController settings;
  final FavoritesController favorites;
  final PhaseFilter phase;
  final ValueChanged<PhaseFilter> onPhase;

  @override
  Widget build(BuildContext context) {
    final favTeams = {for (final f in favorites.teams) int.tryParse(f.id)};
    final favComps = {for (final f in favorites.competitions) f.id};
    bool isFav(MatchSummary m) =>
        favTeams.contains(m.home.id) || favTeams.contains(m.away.id) || favComps.contains(m.competition.code);

    final live = matches.where((m) => m.phase == MatchPhase.live).toList();
    final filtered = matches.where((m) => _matchesPhase(m, phase)).toList();
    final counts = {for (final f in PhaseFilter.values) f: matches.where((m) => _matchesPhase(m, f)).length};

    // Agrupa por competición manteniendo el orden por hora.
    final groups = <String, List<MatchSummary>>{};
    for (final m in filtered) {
      groups.putIfAbsent(m.competition.code, () => []).add(m);
    }

    final children = <Widget>[];
    if (settings.sectionVisible('featured')) children.add(const _FeaturedCompetitions());

    children.add(SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          for (final f in PhaseFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text('${_phaseFilterLabels[f]} (${counts[f]})'),
                selected: phase == f,
                avatar: f == PhaseFilter.live && counts[f]! > 0
                    ? const Icon(Icons.circle, size: 10, color: AppTheme.live)
                    : null,
                showCheckmark: false,
                onSelected: (_) => onPhase(f),
              ),
            ),
        ],
      ),
    ));

    final favs = filtered.where(isFav).toList();
    if (settings.sectionVisible('favorites') && favs.isNotEmpty) {
      children.add(SectionHeader('Tus favoritos (${favs.length})'));
      children.addAll(favs.map((m) => MatchCard(match: m, formatter: formatter, onTap: () => openMatch(context, m))));
    }
    if (settings.sectionVisible('live') && phase == PhaseFilter.all && live.isNotEmpty) {
      children.add(SectionHeader('En juego ahora (${live.length})'));
      children.addAll(live.map((m) => MatchCard(match: m, formatter: formatter, onTap: () => openMatch(context, m))));
    }
    for (final entry in groups.entries) {
      final comp = entry.value.first.competition;
      children.add(CompetitionHeader(
        competition: comp,
        count: entry.value.length,
        onTap: () => openCompetition(context, comp.code, comp.name),
      ));
      children.addAll(entry.value.map((m) => MatchCard(
            match: m,
            formatter: formatter,
            showCompetition: false,
            onTap: () => openMatch(context, m),
          )));
    }
    if (filtered.isEmpty) {
      children.add(MessageView(
        icon: Icons.sports_soccer,
        title: matches.isEmpty ? 'No hay partidos para este día' : 'No hay partidos con este filtro',
        detail: matches.isEmpty
            ? 'Solo se muestran competiciones con una fuente de datos integrada. Prueba otra fecha o quita filtros.'
            : null,
      ));
    }
    children.add(const SizedBox(height: 24));
    return ListView(physics: const AlwaysScrollableScrollPhysics(), children: children);
  }
}

class _FeaturedCompetitions extends StatefulWidget {
  const _FeaturedCompetitions();

  @override
  State<_FeaturedCompetitions> createState() => _FeaturedCompetitionsState();
}

class _FeaturedCompetitionsState extends State<_FeaturedCompetitions> {
  Repository? _repo;
  Future<Loaded<List<Competition>>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Se pide una sola vez por servidor, no en cada reconstrucción de la lista.
    final repo = context.watch<Repository>();
    if (!identical(repo, _repo)) {
      _repo = repo;
      _future = repo.competitions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return FutureBuilder<Loaded<List<Competition>>>(
      future: _future,
      builder: (context, snap) {
        final featured = snap.data?.data.where((c) => c.featured).toList() ?? const [];
        if (featured.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader('Competiciones destacadas'),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: featured.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final c = featured[i];
                  return Semantics(
                    button: true,
                    label: c.name,
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => openCompetition(context, c.code, c.name),
                      child: Ink(
                        width: 92,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CompetitionLogo(url: c.emblemUrl, name: c.name, size: 40),
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Text(
                                c.name,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
