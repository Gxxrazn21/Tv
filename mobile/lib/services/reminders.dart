import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/local_store.dart';
import '../data/models.dart';

/// Programa avisos locales en el dispositivo. No usa notificaciones push ni servidores.
abstract class NotificationScheduler {
  Future<bool> requestPermission();
  Future<void> schedule(int id, DateTime atUtc, String title, String body);
  Future<void> cancel(int id);
}

class LocalNotificationScheduler implements NotificationScheduler {
  LocalNotificationScheduler(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static Future<LocalNotificationScheduler> init() async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    return LocalNotificationScheduler(plugin);
  }

  @override
  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) return await ios.requestPermissions(alert: true, sound: true) ?? false;
    return false;
  }

  @override
  Future<void> schedule(int id, DateTime atUtc, String title, String body) => _plugin.zonedSchedule(
        id: id,
        scheduledDate: tz.TZDateTime.from(atUtc, tz.UTC),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'match_reminders',
            'Recordatorios de partidos',
            channelDescription: 'Avisos locales antes del inicio de los partidos que elijas',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        // Modo inexacto: no requiere el permiso de alarmas exactas.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
      );

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);
}

class RemindersController extends ChangeNotifier {
  RemindersController(this._store, this._scheduler);

  final LocalStore _store;
  final NotificationScheduler _scheduler;
  Set<int> _ids = {};

  bool has(int matchId) => _ids.contains(matchId);

  Future<void> load() async {
    final all = await _store.reminders();
    final now = DateTime.now().toUtc();
    for (final r in all.where((r) => r.kickoffUtc.isBefore(now))) {
      await _store.removeReminder(r.matchId);
    }
    _ids = {for (final r in all.where((r) => !r.kickoffUtc.isBefore(now))) r.matchId};
    notifyListeners();
  }

  /// Devuelve un mensaje para el usuario.
  Future<String> toggle(MatchSummary m, {required int minutesBefore}) async {
    if (has(m.id)) {
      await _scheduler.cancel(m.id);
      await _store.removeReminder(m.id);
      await load();
      return 'Recordatorio eliminado';
    }
    final at = m.utcDate.subtract(Duration(minutes: minutesBefore));
    if (!at.isAfter(DateTime.now().toUtc())) return 'El partido empieza demasiado pronto para avisar';
    if (!await _scheduler.requestPermission()) {
      return 'Activa las notificaciones de OpenFoot en los ajustes del sistema';
    }
    final title = '${m.home.displayName} - ${m.away.displayName}';
    await _scheduler.schedule(m.id, at, title, 'Empieza en $minutesBefore minutos · ${m.competition.name}');
    await _store.addReminder(Reminder(matchId: m.id, kickoffUtc: m.utcDate, title: title));
    await load();
    return 'Te avisaremos $minutesBefore minutos antes';
  }
}
