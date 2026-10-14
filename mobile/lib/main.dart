import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'app.dart';
import 'data/api_client.dart';
import 'data/local_store.dart';
import 'data/repository.dart';
import 'services/reminders.dart';
import 'state/favorites_controller.dart';
import 'state/settings_controller.dart';

/// URL del backend. Se fija al compilar: --dart-define=OPENFOOT_API_URL=https://tu-servidor
/// Por defecto apunta al backend local visto desde el emulador de Android.
const kDefaultApiUrl = String.fromEnvironment('OPENFOOT_API_URL', defaultValue: 'http://10.0.2.2:8000');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  await initializeDateFormatting('es');

  String deviceTz = 'UTC';
  try {
    deviceTz = (await FlutterTimezone.getLocalTimezone()).identifier;
  } catch (_) {
    // Si el sistema no informa de su zona, se usa UTC y el usuario puede elegir otra.
  }

  final prefs = await SharedPreferences.getInstance();
  final store = await LocalStore.open();
  final settings = SettingsController(prefs, deviceTimezone: deviceTz, defaultApiUrl: kDefaultApiUrl);
  final favorites = FavoritesController(store);
  await favorites.load();
  final reminders = RemindersController(store, await LocalNotificationScheduler.init());
  await reminders.load();

  runApp(OpenFootApp(
    settings: settings,
    favorites: favorites,
    reminders: reminders,
    repositoryBuilder: (url) => Repository(api: OpenFootApi(baseUrl: url), store: store),
  ));
}
