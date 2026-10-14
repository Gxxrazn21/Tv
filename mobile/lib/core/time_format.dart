import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

/// Convierte instantes UTC a la zona horaria elegida por el usuario.
class TimeFormatter {
  TimeFormatter(String timezone) : location = _resolve(timezone);

  final tz.Location location;

  static tz.Location _resolve(String name) {
    try {
      return tz.getLocation(name);
    } catch (_) {
      return tz.UTC;
    }
  }

  tz.TZDateTime local(DateTime utc) => tz.TZDateTime.from(utc, location);

  /// Fecha "de calendario" (medianoche) en la zona elegida.
  DateTime today() {
    final now = tz.TZDateTime.now(location);
    return DateTime(now.year, now.month, now.day);
  }

  String time(DateTime utc) => DateFormat('HH:mm', 'es').format(local(utc));

  String date(DateTime utc) => DateFormat("EEE d 'de' MMM", 'es').format(local(utc));

  String full(DateTime utc) => DateFormat("EEEE d 'de' MMMM 'de' y, HH:mm", 'es').format(local(utc));

  static String dayLabel(DateTime day, DateTime today) {
    final diff = DateTime(day.year, day.month, day.day).difference(today).inDays;
    return switch (diff) {
      0 => 'Hoy',
      -1 => 'Ayer',
      1 => 'Mañana',
      _ => DateFormat('EEE d MMM', 'es').format(day),
    };
  }
}
