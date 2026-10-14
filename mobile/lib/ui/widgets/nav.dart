import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../screens/competition_screen.dart';
import '../screens/match_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/team_screen.dart';

void openMatch(BuildContext context, MatchSummary m) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MatchScreen(matchId: m.id, initial: m)));

void openTeam(BuildContext context, int id, String name) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeamScreen(teamId: id, name: name)));

void openCompetition(BuildContext context, String code, String name) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CompetitionScreen(code: code, name: name)));

void openSearch(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen()));

void openSettings(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

/// Acciones comunes de la barra superior: búsqueda y ajustes.
List<Widget> commonActions(BuildContext context) => [
      IconButton(tooltip: 'Buscar', icon: const Icon(Icons.search), onPressed: () => openSearch(context)),
      IconButton(tooltip: 'Ajustes', icon: const Icon(Icons.settings_outlined), onPressed: () => openSettings(context)),
    ];
