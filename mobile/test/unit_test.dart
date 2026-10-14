import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openfoot/core/countries.dart';
import 'package:openfoot/core/time_format.dart';
import 'package:openfoot/data/api_client.dart';
import 'package:openfoot/data/models.dart';
import 'package:openfoot/data/repository.dart';
import 'package:openfoot/services/reminders.dart';
import 'package:openfoot/state/settings_controller.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'helpers.dart';

void main() {
  setUpAll(initTestEnv);

  group('modelos', () {
    test('partido', () {
      final m = MatchSummary.fromJson(matchJson(events: [
        {'minute': 12, 'kind': 'goal', 'team_side': 'home', 'player_name': 'A', 'score_home': 1, 'score_away': 0},
      ]));
      expect(m.phase, MatchPhase.live);
      expect(m.hasScore, isTrue);
      expect(m.utcDate.isUtc, isTrue);
      expect(m.events.single.playerName, 'A');
      expect(m.wasRescheduled, isFalse);
    });

    test('dónde ver', () {
      final w = WatchInfo.fromJson(watchJson(options: [optionJson('Gratis', 'free'), optionJson('Raro', 'otro')]));
      expect(w.options.first.accessType, AccessType.free);
      expect(w.options.last.accessType, AccessType.unknown);
      expect(w.directory!.organizer, 'Premier League');
    });

    test('fase desconocida', () => expect(phaseFrom('xyz'), MatchPhase.unknown));
  });

  group('zona horaria', () {
    final utc = DateTime.utc(2026, 10, 15, 23, 30);
    test('Madrid y Buenos Aires', () {
      expect(TimeFormatter('Europe/Madrid').time(utc), '01:30');
      expect(TimeFormatter('America/Argentina/Buenos_Aires').time(utc), '20:30');
    });
    test('zona inválida cae a UTC', () => expect(TimeFormatter('Nope/Nada').time(utc), '23:30'));
    test('etiquetas de día', () {
      final today = DateTime(2026, 10, 14);
      expect(TimeFormatter.dayLabel(today, today), 'Hoy');
      expect(TimeFormatter.dayLabel(DateTime(2026, 10, 15), today), 'Mañana');
      expect(TimeFormatter.dayLabel(DateTime(2026, 10, 13), today), 'Ayer');
    });
  });

  test('banderas emoji', () {
    expect(flagEmoji('es'), '🇪🇸');
    expect(flagEmoji('XYZ'), '🏳');
  });

  test('validación de servidor', () {
    expect(SettingsController.validateApiUrl('https://openfoot.example'), isNull);
    expect(SettingsController.validateApiUrl('http://10.0.2.2:8000'), isNull);
    expect(SettingsController.validateApiUrl('http://servidor.example'), isNotNull);
    expect(SettingsController.validateApiUrl('https://user:pw@x.example'), isNotNull);
    expect(SettingsController.validateApiUrl('nada'), isNotNull);
  });

  group('repositorio', () {
    test('envía parámetros y guarda caché; sin red devuelve la caché', () async {
      final store = await memoryStore();
      late Uri seen;
      var online = true;
      final client = MockClient((req) async {
        seen = req.url;
        if (!online) throw http.ClientException('sin red');
        return http.Response.bytes(utf8.encode(jsonEncode([matchJson()])), 200);
      });
      final repo = Repository(api: OpenFootApi(baseUrl: 'https://api.test/', client: client), store: store);
      final day = DateTime(2026, 10, 14);
      final first = await repo.matches(from: day, timezone: 'Europe/Madrid', competition: 'PL');
      expect(first.fromCache, isFalse);
      expect(seen.path, '/v1/matches');
      expect(seen.queryParameters, {'date_from': '2026-10-14', 'date_to': '2026-10-14', 'tz': 'Europe/Madrid', 'competition': 'PL'});
      online = false;
      final second = await repo.matches(from: day, timezone: 'Europe/Madrid', competition: 'PL');
      expect(second.fromCache, isTrue);
      expect(second.data.single.id, 1);
      // Una consulta distinta sin caché propaga el error.
      expect(() => repo.matches(from: day, timezone: 'UTC'), throwsA(isA<ApiException>()));
    });

    test('404 no usa la caché', () async {
      final store = await memoryStore();
      final repo = Repository(
        api: OpenFootApi(baseUrl: 'https://api.test', client: MockClient((_) async => http.Response('{}', 404))),
        store: store,
      );
      expect(() => repo.match(5), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)));
    });
  });

  group('recordatorios', () {
    test('programa, evita duplicados y cancela', () async {
      final store = await memoryStore();
      final scheduler = FakeScheduler();
      final c = RemindersController(store, scheduler);
      final future = DateTime.now().toUtc().add(const Duration(days: 1));
      final m = MatchSummary.fromJson(matchJson(phase: 'upcoming', status: 'TIMED', utc: future.toIso8601String(), home: null, away: null));
      expect(await c.toggle(m, minutesBefore: 15), contains('15 minutos'));
      expect(scheduler.scheduled[m.id], m.utcDate.subtract(const Duration(minutes: 15)));
      expect(c.has(m.id), isTrue);
      expect(await c.toggle(m, minutesBefore: 15), 'Recordatorio eliminado');
      expect(scheduler.scheduled, isEmpty);
    });

    test('sin permiso no programa', () async {
      final scheduler = FakeScheduler()..permission = false;
      final c = RemindersController(await memoryStore(), scheduler);
      final future = DateTime.now().toUtc().add(const Duration(days: 1));
      final m = MatchSummary.fromJson(matchJson(utc: future.toIso8601String()));
      expect(await c.toggle(m, minutesBefore: 15), contains('Activa las notificaciones'));
      expect(c.has(m.id), isFalse);
    });

    test('partido pasado', () async {
      final c = RemindersController(await memoryStore(), FakeScheduler());
      final m = MatchSummary.fromJson(matchJson(utc: '2020-01-01T00:00:00Z'));
      expect(await c.toggle(m, minutesBefore: 15), contains('demasiado pronto'));
    });
  });
}
