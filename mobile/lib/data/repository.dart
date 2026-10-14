import 'dart:convert';

import 'api_client.dart';
import 'local_store.dart';
import 'models.dart';

/// Une la API y la caché local: si la red falla, devuelve lo último guardado indicando
/// la fecha, en lugar de inventar datos.
class Repository {
  Repository({required this.api, required this.store});

  final OpenFootApi api;
  final LocalStore store;

  Future<Loaded<T>> _cached<T>(
    String path,
    Map<String, String?> query,
    T Function(Object? json) parse, {
    bool cache = true,
  }) async {
    final key = '$path?${query.entries.where((e) => e.value != null).map((e) => '${e.key}=${e.value}').join('&')}';
    try {
      final body = await api.getRaw(path, query);
      final data = parse(jsonDecode(body));
      if (cache) await store.putCache(key, body);
      return Loaded(data);
    } on ApiException catch (e) {
      if (e.statusCode != null && e.statusCode! < 500 && e.statusCode != 429) rethrow;
      final hit = cache ? await store.getCache(key) : null;
      if (hit == null) rethrow;
      return Loaded(parse(jsonDecode(hit.body)), cachedAt: hit.fetchedAt);
    }
  }

  static List<MatchSummary> _matches(Object? j) =>
      [for (final m in j! as List<dynamic>) MatchSummary.fromJson(m as Map<String, dynamic>)];

  Future<Loaded<List<Competition>>> competitions() => _cached(
        '/v1/competitions',
        const {},
        (j) => [for (final c in j! as List<dynamic>) Competition.fromJson(c as Map<String, dynamic>)],
      );

  Future<Loaded<List<MatchSummary>>> matches({
    required DateTime from,
    DateTime? to,
    required String timezone,
    String? competition,
    String? country,
    int? teamId,
    String? phase,
  }) =>
      _cached(
        '/v1/matches',
        OpenFootApi.matchesQuery(
          from: from,
          to: to,
          timezone: timezone,
          competition: competition,
          country: country,
          teamId: teamId,
          phase: phase,
        ),
        _matches,
      );

  Future<Loaded<List<MatchSummary>>> teamMatches(int teamId, {bool upcoming = true}) =>
      _cached('/v1/teams/$teamId/matches', {'upcoming': '$upcoming'}, _matches);

  Future<Loaded<MatchSummary>> match(int id) =>
      _cached('/v1/matches/$id', const {}, (j) => MatchSummary.fromJson(j! as Map<String, dynamic>));

  Future<Loaded<WatchInfo>> watch(int matchId, String country) => _cached(
        '/v1/matches/$matchId/watch',
        {'country': country},
        (j) => WatchInfo.fromJson(j! as Map<String, dynamic>),
      );

  Future<SearchResult> search(String q, String timezone) async {
    final res = await _cached(
      '/v1/search',
      {'q': q, 'tz': timezone},
      (j) => SearchResult.fromJson(j! as Map<String, dynamic>),
      cache: false,
    );
    return res.data;
  }

  Future<List<SourceStatus>> sources() async {
    final res = await _cached(
      '/v1/sources',
      const {},
      (j) => [for (final s in j! as List<dynamic>) SourceStatus.fromJson(s as Map<String, dynamic>)],
    );
    return res.data;
  }
}
