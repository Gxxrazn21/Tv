import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openfoot/app.dart';
import 'package:openfoot/data/api_client.dart';
import 'package:openfoot/data/local_store.dart';
import 'package:openfoot/data/repository.dart';
import 'package:openfoot/services/reminders.dart';
import 'package:openfoot/state/favorites_controller.dart';
import 'package:openfoot/state/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

// Datos sintéticos de prueba con la forma de la API de OpenFoot.
Map<String, dynamic> team(int id, String name, String tla) =>
    {'id': id, 'name': name, 'short_name': name, 'tla': tla, 'crest_url': null};

Map<String, dynamic> matchJson({
  int id = 1,
  String phase = 'live',
  String status = 'IN_PLAY',
  String utc = '2026-10-14T19:00:00Z',
  int? home = 1,
  int? away = 0,
  String code = 'PL',
  List<Map<String, dynamic>> events = const [],
}) =>
    {
      'id': id,
      'competition': {'code': code, 'name': 'Premier League', 'region': 'europe', 'area_name': 'Inglaterra', 'area_code': 'GB'},
      'utc_date': utc,
      'previous_utc_date': null,
      'status': status,
      'phase': phase,
      'matchday': 8,
      'stage': 'REGULAR_SEASON',
      'group': null,
      'venue': null,
      'home': team(10, 'Ejemplo Rovers', 'ROV'),
      'away': team(20, 'Atlético Muestra', 'ATM'),
      'score': {'home': home, 'away': away},
      'source': 'football-data.org',
      'source_updated_at': null,
      'fetched_at': '2026-10-14T19:05:00Z',
      'events': events,
    };

Map<String, dynamic> watchJson({List<Map<String, dynamic>> options = const [], bool directory = true}) => {
      'match_id': 1,
      'country': 'ES',
      'options': options,
      'official_directory': directory
          ? {'organizer': 'Premier League', 'url': 'https://www.premierleague.com/x', 'verified_at': '2026-10-14T10:00:00Z', 'last_check': null}
          : null,
      'message': options.isEmpty ? 'No se encontró una transmisión oficial verificada para esta región' : null,
      'disclaimer': 'OpenFoot no emite ni redistribuye señales.',
    };

Map<String, dynamic> optionJson(String name, String access) => {
      'broadcaster': {'slug': name.toLowerCase(), 'name': name, 'website_url': 'https://www.$name.example/'},
      'access_type': access,
      'price_note': null,
      'territorial_notes': null,
      'coverage_note': null,
      'watch_url': 'https://www.$name.example/futbol',
      'embed_allowed': false,
      'season': '2026/27',
      'source_type': 'organizer_directory',
      'source_url': 'https://www.premierleague.com/x',
      'verified_at': '2026-10-14T10:00:00Z',
      'verified_by': 'test',
      'last_check': null,
    };

final competitionsJson = [
  {
    'code': 'PL', 'name': 'Premier League', 'region': 'europe', 'area_name': 'Inglaterra', 'area_code': 'GB',
    'kind': 'league', 'gender': 'men', 'data_status': 'available', 'data_source': 'football-data.org',
    'data_note': null, 'featured': true, 'emblem_url': null, 'has_official_directory': true,
  },
  {
    'code': 'ARG', 'name': 'Liga Profesional de Argentina', 'region': 'south_america', 'area_name': 'Argentina',
    'area_code': 'AR', 'kind': 'league', 'gender': 'men', 'data_status': 'unavailable', 'data_source': null,
    'data_note': 'Sin fuente gratuita integrada.', 'featured': false, 'emblem_url': null, 'has_official_directory': false,
  },
];

typedef Routes = Map<String, Object Function(http.Request)>;

MockClient mockApi(Routes routes) => MockClient((req) async {
      for (final e in routes.entries) {
        if (req.url.path == e.key) {
          final body = e.value(req);
          if (body is http.Response) return body;
          return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
        }
      }
      return http.Response('{"detail":"no"}', 404);
    });

Future<void> initTestEnv() async {
  tzdata.initializeTimeZones();
  await initializeDateFormatting('es');
  sqfliteFfiInit();
}

Future<LocalStore> memoryStore() => LocalStore.open(factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);

class FakeScheduler implements NotificationScheduler {
  bool permission = true;
  final scheduled = <int, DateTime>{};

  @override
  Future<bool> requestPermission() async => permission;

  @override
  Future<void> schedule(int id, DateTime atUtc, String title, String body) async => scheduled[id] = atUtc;

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);
}

class TestApp {
  TestApp(this.widget, this.settings, this.store, this.scheduler);

  final Widget widget;
  final SettingsController settings;
  final LocalStore store;
  final FakeScheduler scheduler;
}

Future<TestApp> buildApp(Routes routes, {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final store = await memoryStore();
  final settings = SettingsController(sp, deviceTimezone: 'Europe/Madrid', defaultApiUrl: 'https://api.test');
  final favorites = FavoritesController(store);
  await favorites.load();
  final scheduler = FakeScheduler();
  final reminders = RemindersController(store, scheduler);
  final client = mockApi(routes);
  return TestApp(
    OpenFootApp(
      settings: settings,
      favorites: favorites,
      reminders: reminders,
      repositoryBuilder: (url) => Repository(api: OpenFootApi(baseUrl: url, client: client), store: store),
    ),
    settings,
    store,
    scheduler,
  );
}

/// Espera a que terminen las operaciones de SQLite (ffi) y los frames pendientes.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Pantalla alta para que las listas perezosas construyan todo su contenido sin desplazarse.
void tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 6000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}
