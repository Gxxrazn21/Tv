import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Cliente HTTP de la API de OpenFoot. La app solo habla con este backend: las claves de las
/// APIs deportivas permanecen en el servidor y nunca se incluyen en el cliente.
class OpenFootApi {
  OpenFootApi({required this.baseUrl, http.Client? client}) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  static final _day = DateFormat('yyyy-MM-dd');
  static const _timeout = Duration(seconds: 15);

  Uri _uri(String path, [Map<String, String?> query = const {}]) {
    final params = {
      for (final e in query.entries)
        if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
    };
    final base = Uri.parse(baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl);
    return base.replace(path: '${base.path}$path', queryParameters: params.isEmpty ? null : params);
  }

  /// Devuelve el cuerpo JSON en texto (se guarda tal cual en la caché local).
  Future<String> getRaw(String path, [Map<String, String?> query = const {}]) async {
    final http.Response resp;
    try {
      resp = await _client.get(_uri(path, query), headers: {'Accept': 'application/json'}).timeout(_timeout);
    } catch (_) {
      throw ApiException('No se pudo conectar con el servidor de OpenFoot');
    }
    if (resp.statusCode == 429) {
      throw ApiException('Demasiadas solicitudes; inténtalo en un momento', statusCode: 429);
    }
    if (resp.statusCode == 404) {
      throw ApiException('No encontrado', statusCode: 404);
    }
    if (resp.statusCode >= 400) {
      throw ApiException('Error del servidor (${resp.statusCode})', statusCode: resp.statusCode);
    }
    try {
      return utf8.decode(resp.bodyBytes);
    } on FormatException {
      throw ApiException('Respuesta del servidor no válida');
    }
  }

  static String day(DateTime d) => _day.format(d);

  static Map<String, String?> matchesQuery({
    required DateTime from,
    DateTime? to,
    required String timezone,
    String? competition,
    String? country,
    int? teamId,
    String? phase,
  }) =>
      {
        'date_from': day(from),
        'date_to': day(to ?? from),
        'tz': timezone,
        'competition': competition,
        'country': country,
        'team_id': teamId?.toString(),
        'phase': phase,
      };
}
