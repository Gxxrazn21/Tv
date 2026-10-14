import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'data/repository.dart';
import 'services/reminders.dart';
import 'state/favorites_controller.dart';
import 'state/settings_controller.dart';
import 'ui/screens/competitions_screen.dart';
import 'ui/screens/favorites_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/matches_screen.dart';

class OpenFootApp extends StatelessWidget {
  const OpenFootApp({
    super.key,
    required this.settings,
    required this.repositoryBuilder,
    required this.favorites,
    required this.reminders,
  });

  final SettingsController settings;
  final Repository Function(String apiUrl) repositoryBuilder;
  final FavoritesController favorites;
  final RemindersController reminders;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: favorites),
        ChangeNotifierProvider.value(value: reminders),
        // Si el usuario cambia el servidor, se reconstruye el repositorio.
        ProxyProvider<SettingsController, Repository>(
          update: (_, s, previous) =>
              previous != null && previous.api.baseUrl == s.apiUrl ? previous : repositoryBuilder(s.apiUrl),
        ),
      ],
      child: Consumer<SettingsController>(
        builder: (context, s, _) => MaterialApp(
          title: 'OpenFoot',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: s.themeMode,
          home: const HomeShell(),
        ),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _pages = [HomeScreen(), MatchesScreen(), CompetitionsScreen(), FavoritesScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Partidos'),
          NavigationDestination(icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events), label: 'Competiciones'),
          NavigationDestination(icon: Icon(Icons.star_outline), selectedIcon: Icon(Icons.star), label: 'Favoritos'),
        ],
      ),
    );
  }
}
