import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

/// Calendario: días anteriores y futuros, con filtros por competición, país y equipo favorito.
class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  static const _range = 14;
  int _offset = 0;
  MatchFilters _filters = const MatchFilters();
  int? _teamId;
  final _strip = ScrollController(initialScrollOffset: (_range - 2) * 64.0);

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final repo = context.watch<Repository>();
    final favorites = context.watch<FavoritesController>();
    final fmt = TimeFormatter(settings.timezone);
    final today = fmt.today();
    final day = today.add(Duration(days: _offset));

    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat("EEEE d 'de' MMMM", 'es').format(day)),
        actions: [
          IconButton(
            tooltip: 'Elegir fecha',
            icon: const Icon(Icons.event),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: day,
                firstDate: today.subtract(const Duration(days: 365)),
                lastDate: today.add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _offset = picked.difference(today).inDays);
            },
          ),
          ...commonActions(context),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 64,
            child: ListView.builder(
              controller: _strip,
              scrollDirection: Axis.horizontal,
              itemCount: _range * 2 + 1,
              itemBuilder: (context, i) {
                final o = i - _range;
                final d = today.add(Duration(days: o));
                final selected = o == _offset;
                final scheme = Theme.of(context).colorScheme;
                return Semantics(
                  selected: selected,
                  button: true,
                  label: DateFormat("EEEE d 'de' MMMM", 'es').format(d),
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: () => setState(() => _offset = o),
                    child: Container(
                      width: 64,
                      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected ? scheme.primaryContainer : null,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(o == 0 ? 'HOY' : DateFormat('EEE', 'es').format(d).toUpperCase(),
                              style: Theme.of(context).textTheme.labelSmall),
                          Text('${d.day}', style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Row(
            children: [
              Expanded(child: FilterBar(filters: _filters, onChanged: (f) => setState(() => _filters = f))),
              if (favorites.teams.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: PopupMenuButton<int?>(
                    tooltip: 'Filtrar por equipo favorito',
                    icon: Icon(_teamId == null ? Icons.shield_outlined : Icons.shield),
                    onSelected: (v) => setState(() => _teamId = v == -1 ? null : v),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: -1, child: Text('Todos los equipos')),
                      for (final t in favorites.teams) PopupMenuItem(value: int.tryParse(t.id), child: Text(t.label)),
                    ],
                  ),
                ),
            ],
          ),
          Expanded(
            child: Loader<List<MatchSummary>>(
              formatter: fmt,
              deps: [repo, day, _filters.competition, _filters.country, _teamId, settings.timezone],
              load: () => repo.matches(
                from: day,
                timezone: settings.timezone,
                competition: _filters.competition,
                country: _filters.country,
                teamId: _teamId,
              ),
              autoRefresh: (data) => data.any((m) => m.phase == MatchPhase.live) ? const Duration(seconds: 60) : null,
              builder: (context, matches, refresh) {
                if (matches.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: refresh,
                    child: ListView(children: const [
                      MessageView(icon: Icons.event_busy, title: 'Sin partidos en esta fecha', detail: 'Cambia de día o ajusta los filtros.'),
                    ]),
                  );
                }
                final byComp = <String, List<MatchSummary>>{};
                for (final m in matches) {
                  byComp.putIfAbsent(m.competition.name, () => []).add(m);
                }
                return RefreshIndicator(
                  onRefresh: refresh,
                  child: ListView(
                    children: [
                      for (final e in byComp.entries) ...[
                        SectionHeader(e.key),
                        for (final m in e.value) MatchCard(match: m, formatter: fmt, onTap: () => openMatch(context, m)),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
