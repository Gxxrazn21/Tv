import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/countries.dart';
import '../../core/time_format.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/settings_controller.dart';
import '../widgets/match_card.dart';
import '../widgets/nav.dart';
import '../widgets/state_views.dart';

/// Búsqueda de equipos, jugadores, competiciones, países y partidos por fecha (dd/mm/aaaa).
/// La tolerancia a errores ortográficos la aplica el servidor.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  Future<SearchResult>? _future;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final query = q.trim();
      setState(() {
        _future = query.length < 2
            ? null
            : context.read<Repository>().search(query, context.read<SettingsController>().timezone);
      });
    });
  }

  static const _icons = {
    'team': Icons.shield_outlined,
    'player': Icons.person_outline,
    'competition': Icons.emoji_events_outlined,
    'country': Icons.public,
  };
  static const _kinds = {'team': 'Equipo', 'player': 'Jugador', 'competition': 'Competición', 'country': 'País'};

  @override
  Widget build(BuildContext context) {
    final fmt = TimeFormatter(context.watch<SettingsController>().timezone);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Equipo, jugador, liga, país o 14/10/2026',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
        ),
      ),
      body: _future == null
          ? const MessageView(icon: Icons.search, title: 'Escribe al menos 2 letras', detail: 'Se toleran errores ortográficos.')
          : FutureBuilder<SearchResult>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const LoadingView();
                if (snap.hasError) return ErrorView(error: snap.error!);
                final r = snap.data!;
                if (r.hits.isEmpty && r.matchesOnDate.isEmpty) {
                  return const MessageView(icon: Icons.search_off, title: 'Sin resultados');
                }
                return ListView(
                  children: [
                    if (r.matchesOnDate.isNotEmpty) ...[
                      SectionHeader('Partidos en esa fecha (${r.matchesOnDate.length})'),
                      for (final m in r.matchesOnDate)
                        MatchCard(match: m, formatter: fmt, onTap: () => openMatch(context, m)),
                    ],
                    for (final h in r.hits)
                      ListTile(
                        leading: h.kind == 'country'
                            ? Text(flagEmoji(h.id), style: const TextStyle(fontSize: 22))
                            : Icon(_icons[h.kind] ?? Icons.label_outline),
                        title: Text(h.label),
                        subtitle: Text([_kinds[h.kind] ?? h.kind, if (h.detail != null) h.detail!].join(' · ')),
                        onTap: switch (h.kind) {
                          'team' => () => openTeam(context, int.parse(h.id), h.label),
                          'competition' => () => openCompetition(context, h.id, h.label),
                          'country' => () => _showCountry(context, h),
                          _ => null,
                        },
                      ),
                  ],
                );
              },
            ),
    );
  }

  Future<void> _showCountry(BuildContext context, SearchHit h) async {
    final comps = (await context.read<Repository>().competitions()).data.where((c) => c.areaCode == h.id && c.hasData).toList();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text('${flagEmoji(h.id)} ${h.label}', style: Theme.of(ctx).textTheme.titleMedium)),
            for (final c in comps)
              ListTile(
                title: Text(c.name),
                onTap: () {
                  Navigator.pop(ctx);
                  openCompetition(context, c.code, c.name);
                },
              ),
            if (comps.isEmpty) const ListTile(title: Text('No hay competiciones con datos para este país.')),
          ],
        ),
      ),
    );
  }
}
