import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias del usuario, guardadas solo en el dispositivo.
class SettingsController extends ChangeNotifier {
  SettingsController(this._prefs, {required this.deviceTimezone, required this.defaultApiUrl});

  final SharedPreferences _prefs;
  final String deviceTimezone;
  final String defaultApiUrl;

  static const homeSections = ['featured', 'favorites', 'live'];

  ThemeMode get themeMode => switch (_prefs.getString('theme')) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark, // tema oscuro por defecto
      };

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString('theme', mode.name);
    notifyListeners();
  }

  /// Zona horaria IANA elegida o null para usar la del dispositivo.
  String? get timezoneOverride => _prefs.getString('timezone');
  String get timezone => timezoneOverride ?? deviceTimezone;

  Future<void> setTimezone(String? tz) async {
    tz == null ? await _prefs.remove('timezone') : await _prefs.setString('timezone', tz);
    notifyListeners();
  }

  String? get country => _prefs.getString('country');

  Future<void> setCountry(String code) async {
    await _prefs.setString('country', code.toUpperCase());
    notifyListeners();
  }

  String get apiUrl => _prefs.getString('api_url') ?? defaultApiUrl;

  Future<void> setApiUrl(String url) async {
    await _prefs.setString('api_url', url.trim());
    notifyListeners();
  }

  bool sectionVisible(String section) => _prefs.getBool('home_$section') ?? true;

  Future<void> setSectionVisible(String section, bool visible) async {
    await _prefs.setBool('home_$section', visible);
    notifyListeners();
  }

  /// Por defecto solo se muestran opciones de visionado gratuitas (y legales).
  bool get onlyFree => _prefs.getBool('only_free') ?? true;

  Future<void> setOnlyFree(bool value) async {
    await _prefs.setBool('only_free', value);
    notifyListeners();
  }

  int get reminderMinutes => _prefs.getInt('reminder_minutes') ?? 15;

  Future<void> setReminderMinutes(int minutes) async {
    await _prefs.setInt('reminder_minutes', minutes);
    notifyListeners();
  }

  /// Valida una URL de servidor: https, o http solo para equipos locales (desarrollo).
  static String? validateApiUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return 'URL no válida';
    if (uri.userInfo.isNotEmpty) return 'No incluyas credenciales en la URL';
    const local = {'localhost', '127.0.0.1', '10.0.2.2'};
    if (uri.scheme == 'https') return null;
    if (uri.scheme == 'http' && local.contains(uri.host)) return null;
    return 'Usa https (http solo se admite para localhost o el emulador)';
  }
}
