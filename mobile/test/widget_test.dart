import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openfoot/ui/screens/match_screen.dart';

import 'helpers.dart';

Routes baseRoutes({List<Map<String, dynamic>>? options}) => {
      '/v1/competitions': (_) => competitionsJson,
      '/v1/matches': (_) => [
            matchJson(),
            matchJson(id: 2, phase: 'upcoming', status: 'TIMED', home: null, away: null, utc: '2026-10-14T21:00:00Z'),
            matchJson(id: 3, phase: 'finished', status: 'FINISHED', home: 2, away: 2, utc: '2026-10-14T13:00:00Z'),
          ],
      '/v1/matches/1': (_) => matchJson(events: [
            {'minute': 12, 'kind': 'goal', 'team_side': 'home', 'player_name': 'Goleador Prueba', 'score_home': 1, 'score_away': 0},
          ]),
      '/v1/matches/1/watch': (_) => watchJson(options: options ?? const []),
      '/v1/sources': (_) => [
            {'name': 'football-data.org', 'configured': true, 'attribution': 'Football data provided by the Football-Data.org API',
             'competitions': ['PL'], 'last_sync_at': null, 'last_sync_ok': null, 'last_sync_detail': null},
          ],
    };

void main() {
  setUpAll(initTestEnv);

  testWidgets('Inicio: filtros por estado, directo y agrupación por competición', (tester) async {
    final app = await buildApp(baseRoutes());
    tallScreen(tester);
    await tester.pumpWidget(app.widget);
    await settle(tester);

    expect(find.text('Todos (3)'), findsOneWidget);
    expect(find.text('En directo (1)'), findsOneWidget);
    expect(find.text('Próximos (1)'), findsOneWidget);
    expect(find.text('Finalizados (1)'), findsOneWidget);
    expect(find.text('En juego ahora (1)'), findsOneWidget);
    expect(find.text('VIVO'), findsWidgets);
    expect(find.text('FINAL'), findsOneWidget);
    // Cabecera de competición con logo (o trofeo de respaldo).
    expect(find.text('Premier League'), findsWidgets);
    expect(find.text('Competiciones destacadas'), findsOneWidget);
    for (final label in ['Inicio', 'Partidos', 'Competiciones', 'Favoritos']) {
      expect(find.text(label), findsWidgets);
    }
    final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(material.themeMode, ThemeMode.dark);

    // Filtro "Finalizados": solo queda el partido terminado.
    await tester.ensureVisible(find.text('Finalizados (1)'));
    await settle(tester);
    await tester.tap(find.text('Finalizados (1)'));
    await settle(tester);
    expect(find.text('FINAL'), findsOneWidget);
    expect(find.text('En juego ahora (1)'), findsNothing);
  });

  testWidgets('Las tarjetas tienen etiqueta accesible', (tester) async {
    final app = await buildApp(baseRoutes());
    tallScreen(tester);
    await tester.pumpWidget(app.widget);
    await settle(tester);
    expect(find.bySemanticsLabel(RegExp('Ejemplo Rovers contra Atlético Muestra, en directo, 1 a 0')), findsWidgets);
  });

  testWidgets('Secciones de inicio personalizables', (tester) async {
    final app = await buildApp(baseRoutes(), prefs: {'home_live': false});
    tallScreen(tester);
    await tester.pumpWidget(app.widget);
    await settle(tester);
    expect(find.text('En juego ahora (1)'), findsNothing);
    expect(find.text('En directo (1)'), findsOneWidget); // el filtro sigue disponible
  });

  testWidgets('Ficha sin país pide elegirlo', (tester) async {
    final app = await buildApp(baseRoutes());
    tallScreen(tester);
    await tester.pumpWidget(app.widget);
    await settle(tester);
    await tester.tap(find.text('Ejemplo Rovers').first);
    await settle(tester);
    expect(find.text('Goleador Prueba'), findsOneWidget);
    expect(find.text('Elige tu país para ver dónde se emite'), findsOneWidget);
  });

  testWidgets('Sin fuente verificada muestra el mensaje y el directorio oficial', (tester) async {
    final app = await buildApp(baseRoutes(), prefs: {'country': 'ES'});
    tallScreen(tester);
    await tester.pumpWidget(app.widget);
    await settle(tester);
    await tester.tap(find.text('Ejemplo Rovers').first);
    await settle(tester);
    expect(find.text('No se encontró una transmisión oficial verificada para esta región'), findsOneWidget);
    expect(find.textContaining('Directorio oficial de emisoras (Premier League)'), findsOneWidget);
    expect(find.byType(WatchOptionCard), findsNothing);
  });

  testWidgets('En directo: se abren solas las opciones gratuitas y las de pago van ocultas', (tester) async {
    final app = await buildApp(
      baseRoutes(options: [optionJson('Abierta', 'free'), optionJson('Premium', 'subscription'), optionJson('Evento', 'ppv')]),
      prefs: {'country': 'ES'},
    );
    tallScreen(tester);
    await tester.pumpWidget(app.widget);
    await settle(tester);
    await tester.tap(find.text('Ejemplo Rovers').first);
    await settle(tester);

    // Partido en directo: la hoja de opciones aparece sola, solo con la opción gratuita.
    expect(find.byType(WatchOptionCard), findsOneWidget);
    expect(find.text('Abrir Abierta'), findsOneWidget);
    expect(find.text('Ver aquí'), findsOneWidget);
    expect(find.widgetWithText(AccessBadge, 'Gratis'), findsOneWidget);

    // Cerrar la hoja y mostrar las de pago.
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(find.text('Ver ahora en Abierta'), findsOneWidget);
    await tester.tap(find.text('Hay 2 opciones de pago ocultas · Mostrar'));
    await settle(tester);
    await tester.tap(find.text('Ver ahora · 3 opciones'));
    await settle(tester);
    expect(find.byType(WatchOptionCard), findsNWidgets(3));
    expect(find.widgetWithText(AccessBadge, 'Suscripción'), findsOneWidget);
    expect(find.widgetWithText(AccessBadge, 'Pago por evento'), findsOneWidget);
  });

  testWidgets('Con «solo gratis» desactivado se ofrecen todas', (tester) async {
    final app = await buildApp(
      baseRoutes(options: [optionJson('Premium', 'subscription')]),
      prefs: {'country': 'ES', 'only_free': false},
    );
    tallScreen(tester);
    await tester.pumpWidget(app.widget);
    await settle(tester);
    await tester.tap(find.text('Ejemplo Rovers').first);
    await settle(tester);
    await tester.tapAt(const Offset(10, 10)); // cierra la hoja abierta automáticamente
    await settle(tester);
    expect(find.text('Ver ahora en Premium'), findsOneWidget);
  });

  testWidgets('Favoritos locales desde la ficha', (tester) async {
    final app = await buildApp(baseRoutes());
    tallScreen(tester);
    await tester.pumpWidget(app.widget);
    await settle(tester);
    await tester.tap(find.text('Ejemplo Rovers').first);
    await settle(tester);
    await tester.tap(find.byTooltip('Añadir Ejemplo Rovers a favoritos'));
    await settle(tester);
    expect(find.byTooltip('Quitar Ejemplo Rovers de favoritos'), findsOneWidget);
    final favs = await tester.runAsync(app.store.favorites);
    expect(favs!.single.label, 'Ejemplo Rovers');
  });

  testWidgets('Competiciones sin datos lo explican', (tester) async {
    final app = await buildApp(baseRoutes());
    tallScreen(tester);
    await tester.pumpWidget(app.widget);
    await settle(tester);
    await tester.tap(find.text('Competiciones').last);
    await settle(tester);
    await tester.tap(find.text('Liga Profesional de Argentina'));
    await settle(tester);
    expect(find.text('Sin fuente gratuita integrada.'), findsOneWidget);
  });

  testWidgets('Error de red sin caché ofrece reintentar', (tester) async {
    final app = await buildApp({});
    tallScreen(tester);
    await tester.pumpWidget(app.widget);
    await settle(tester);
    expect(find.text('Reintentar'), findsWidgets);
  });
}
