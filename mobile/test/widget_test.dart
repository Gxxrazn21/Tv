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

  testWidgets('Inicio muestra secciones y estados claros', (tester) async {
    final app = await buildApp(baseRoutes());
    tallScreen(tester);
    await tester.pumpWidget(app.widget);
    await settle(tester);

    expect(find.text('En directo (1)'), findsOneWidget);
    expect(find.text('Próximos (1)'), findsOneWidget);
    expect(find.text('Finalizados (1)'), findsOneWidget);
    expect(find.text('EN DIRECTO'), findsOneWidget);
    expect(find.text('PRÓXIMO'), findsOneWidget);
    expect(find.text('FINALIZADO'), findsOneWidget);
    expect(find.text('Competiciones destacadas'), findsOneWidget);
    // Navegación inferior
    for (final label in ['Inicio', 'Partidos', 'Competiciones', 'Favoritos']) {
      expect(find.text(label), findsWidgets);
    }
    // Tema oscuro por defecto
    final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(material.themeMode, ThemeMode.dark);
  });

  testWidgets('Las tarjetas tienen etiqueta accesible', (tester) async {
    final app = await buildApp(baseRoutes());
    tallScreen(tester);
    await tester.pumpWidget(app.widget);
    await settle(tester);
    expect(find.bySemanticsLabel(RegExp('Ejemplo Rovers contra Atlético Muestra, en directo, 1 a 0')), findsOneWidget);
  });

  testWidgets('Secciones de inicio personalizables', (tester) async {
    final app = await buildApp(baseRoutes(), prefs: {'home_finished': false});
    tallScreen(tester);
    await tester.pumpWidget(app.widget);
    await settle(tester);
    expect(find.text('Finalizados (1)'), findsNothing);
    expect(find.text('En directo (1)'), findsOneWidget);
  });

  testWidgets('Ficha sin país pide elegirlo', (tester) async {
    final app = await buildApp(baseRoutes());
    tallScreen(tester);
    await tester.pumpWidget(app.widget);
    await settle(tester);
    await tester.tap(find.text('Ejemplo Rovers').first);
    await settle(tester);
    expect(find.text('Goleador Prueba'), findsOneWidget);
    expect(find.textContaining('Elige tu país'), findsOneWidget);
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
  });

  testWidgets('Distingue proveedores gratuitos y de pago', (tester) async {
    final app = await buildApp(
      baseRoutes(options: [optionJson('Abierta', 'free'), optionJson('Premium', 'subscription'), optionJson('Evento', 'ppv')]),
      prefs: {'country': 'ES'},
    );
    tallScreen(tester);
    await tester.pumpWidget(app.widget);
    await settle(tester);
    await tester.tap(find.text('Ejemplo Rovers').first);
    await settle(tester);
    expect(find.widgetWithText(AccessBadge, 'Gratis'), findsOneWidget);
    expect(find.widgetWithText(AccessBadge, 'Suscripción'), findsOneWidget);
    expect(find.widgetWithText(AccessBadge, 'Pago por evento'), findsOneWidget);
    expect(find.text('Abrir Abierta'), findsOneWidget);
    expect(find.text('No se encontró una transmisión oficial verificada para esta región'), findsNothing);
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
