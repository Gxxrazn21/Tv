// Modelos que reflejan la API de OpenFoot (backend/openfoot/schemas.py).

DateTime _dt(Object? v) => DateTime.parse(v as String).toUtc();
DateTime? _dtOrNull(Object? v) => v == null ? null : _dt(v);

enum MatchPhase { live, upcoming, finished, postponed, cancelled, unknown }

MatchPhase phaseFrom(String? raw) => switch (raw) {
      'live' => MatchPhase.live,
      'upcoming' => MatchPhase.upcoming,
      'finished' => MatchPhase.finished,
      'postponed' => MatchPhase.postponed,
      'cancelled' => MatchPhase.cancelled,
      _ => MatchPhase.unknown,
    };

class CompetitionRef {
  const CompetitionRef({
    required this.code,
    required this.name,
    required this.region,
    required this.areaName,
    this.areaCode,
    this.emblemUrl,
  });

  final String code;
  final String name;
  final String region;
  final String areaName;
  final String? areaCode;
  final String? emblemUrl;

  factory CompetitionRef.fromJson(Map<String, dynamic> j) => CompetitionRef(
        code: j['code'] as String,
        name: j['name'] as String,
        region: j['region'] as String,
        areaName: j['area_name'] as String,
        areaCode: j['area_code'] as String?,
        emblemUrl: j['emblem_url'] as String?,
      );
}

class Competition extends CompetitionRef {
  const Competition({
    required super.code,
    required super.name,
    required super.region,
    required super.areaName,
    super.areaCode,
    super.emblemUrl,
    required this.kind,
    required this.gender,
    required this.dataStatus,
    this.dataSource,
    this.dataNote,
    required this.featured,
    required this.hasOfficialDirectory,
  });

  final String kind;
  final String gender;
  final String dataStatus;
  final String? dataSource;
  final String? dataNote;
  final bool featured;
  final bool hasOfficialDirectory;

  bool get hasData => dataStatus == 'available';

  factory Competition.fromJson(Map<String, dynamic> j) => Competition(
        code: j['code'] as String,
        name: j['name'] as String,
        region: j['region'] as String,
        areaName: j['area_name'] as String,
        areaCode: j['area_code'] as String?,
        emblemUrl: j['emblem_url'] as String?,
        kind: j['kind'] as String? ?? 'league',
        gender: j['gender'] as String? ?? 'men',
        dataStatus: j['data_status'] as String? ?? 'unavailable',
        dataSource: j['data_source'] as String?,
        dataNote: j['data_note'] as String?,
        featured: j['featured'] as bool? ?? false,
        hasOfficialDirectory: j['has_official_directory'] as bool? ?? false,
      );
}

class Team {
  const Team({required this.id, required this.name, this.shortName, this.tla, this.crestUrl});

  final int id;
  final String name;
  final String? shortName;
  final String? tla;
  final String? crestUrl;

  String get displayName => shortName ?? name;

  factory Team.fromJson(Map<String, dynamic> j) => Team(
        id: j['id'] as int,
        name: j['name'] as String,
        shortName: j['short_name'] as String?,
        tla: j['tla'] as String?,
        crestUrl: j['crest_url'] as String?,
      );
}

class MatchEvent {
  const MatchEvent({this.minute, required this.kind, this.teamSide, this.playerName});

  final int? minute;
  final String kind;
  final String? teamSide;
  final String? playerName;

  factory MatchEvent.fromJson(Map<String, dynamic> j) => MatchEvent(
        minute: j['minute'] as int?,
        kind: j['kind'] as String,
        teamSide: j['team_side'] as String?,
        playerName: j['player_name'] as String?,
      );
}

class MatchSummary {
  const MatchSummary({
    required this.id,
    required this.competition,
    required this.utcDate,
    this.previousUtcDate,
    required this.status,
    required this.phase,
    this.matchday,
    this.stage,
    this.venue,
    required this.home,
    required this.away,
    this.homeScore,
    this.awayScore,
    required this.source,
    required this.fetchedAt,
    this.events = const [],
  });

  final int id;
  final CompetitionRef competition;
  final DateTime utcDate;
  final DateTime? previousUtcDate;
  final String status;
  final MatchPhase phase;
  final int? matchday;
  final String? stage;
  final String? venue;
  final Team home;
  final Team away;
  final int? homeScore;
  final int? awayScore;
  final String source;
  final DateTime fetchedAt;
  final List<MatchEvent> events;

  bool get hasScore => homeScore != null && awayScore != null;
  bool get wasRescheduled => previousUtcDate != null && previousUtcDate != utcDate;

  factory MatchSummary.fromJson(Map<String, dynamic> j) {
    final score = (j['score'] as Map<String, dynamic>?) ?? const {};
    return MatchSummary(
      id: j['id'] as int,
      competition: CompetitionRef.fromJson(j['competition'] as Map<String, dynamic>),
      utcDate: _dt(j['utc_date']),
      previousUtcDate: _dtOrNull(j['previous_utc_date']),
      status: j['status'] as String,
      phase: phaseFrom(j['phase'] as String?),
      matchday: j['matchday'] as int?,
      stage: j['stage'] as String?,
      venue: j['venue'] as String?,
      home: Team.fromJson(j['home'] as Map<String, dynamic>),
      away: Team.fromJson(j['away'] as Map<String, dynamic>),
      homeScore: score['home'] as int?,
      awayScore: score['away'] as int?,
      source: j['source'] as String,
      fetchedAt: _dt(j['fetched_at']),
      events: [
        for (final e in (j['events'] as List<dynamic>? ?? const []))
          MatchEvent.fromJson(e as Map<String, dynamic>),
      ],
    );
  }
}

enum AccessType { free, subscription, ppv, unknown }

AccessType accessFrom(String? raw) => switch (raw) {
      'free' => AccessType.free,
      'subscription' => AccessType.subscription,
      'ppv' => AccessType.ppv,
      _ => AccessType.unknown,
    };

class LinkCheckInfo {
  const LinkCheckInfo({required this.checkedAt, required this.outcome, this.statusCode});

  final DateTime checkedAt;
  final String outcome;
  final int? statusCode;

  static LinkCheckInfo? fromJson(Map<String, dynamic>? j) => j == null
      ? null
      : LinkCheckInfo(
          checkedAt: _dt(j['checked_at']),
          outcome: j['outcome'] as String,
          statusCode: j['status_code'] as int?,
        );
}

class WatchOption {
  const WatchOption({
    required this.broadcasterName,
    required this.accessType,
    this.priceNote,
    this.territorialNotes,
    this.coverageNote,
    required this.watchUrl,
    required this.sourceUrl,
    required this.verifiedAt,
    required this.verifiedBy,
    this.lastCheck,
  });

  final String broadcasterName;
  final AccessType accessType;
  final String? priceNote;
  final String? territorialNotes;
  final String? coverageNote;
  final String watchUrl;
  final String sourceUrl;
  final DateTime verifiedAt;
  final String verifiedBy;
  final LinkCheckInfo? lastCheck;

  factory WatchOption.fromJson(Map<String, dynamic> j) => WatchOption(
        broadcasterName: (j['broadcaster'] as Map<String, dynamic>)['name'] as String,
        accessType: accessFrom(j['access_type'] as String?),
        priceNote: j['price_note'] as String?,
        territorialNotes: j['territorial_notes'] as String?,
        coverageNote: j['coverage_note'] as String?,
        watchUrl: j['watch_url'] as String,
        sourceUrl: j['source_url'] as String,
        verifiedAt: _dt(j['verified_at']),
        verifiedBy: j['verified_by'] as String? ?? '',
        lastCheck: LinkCheckInfo.fromJson(j['last_check'] as Map<String, dynamic>?),
      );
}

class OfficialDirectory {
  const OfficialDirectory({required this.organizer, required this.url, required this.verifiedAt});

  final String organizer;
  final String url;
  final DateTime verifiedAt;

  static OfficialDirectory? fromJson(Map<String, dynamic>? j) => j == null
      ? null
      : OfficialDirectory(
          organizer: j['organizer'] as String,
          url: j['url'] as String,
          verifiedAt: _dt(j['verified_at']),
        );
}

class WatchInfo {
  const WatchInfo({
    required this.country,
    required this.options,
    this.directory,
    this.message,
    required this.disclaimer,
  });

  final String country;
  final List<WatchOption> options;
  final OfficialDirectory? directory;
  final String? message;
  final String disclaimer;

  factory WatchInfo.fromJson(Map<String, dynamic> j) => WatchInfo(
        country: j['country'] as String,
        options: [
          for (final o in j['options'] as List<dynamic>) WatchOption.fromJson(o as Map<String, dynamic>),
        ],
        directory: OfficialDirectory.fromJson(j['official_directory'] as Map<String, dynamic>?),
        message: j['message'] as String?,
        disclaimer: j['disclaimer'] as String,
      );
}

class SearchHit {
  const SearchHit({required this.kind, required this.id, required this.label, this.detail});

  final String kind;
  final String id;
  final String label;
  final String? detail;

  factory SearchHit.fromJson(Map<String, dynamic> j) => SearchHit(
        kind: j['kind'] as String,
        id: j['id'] as String,
        label: j['label'] as String,
        detail: j['detail'] as String?,
      );
}

class SearchResult {
  const SearchResult({required this.hits, required this.matchesOnDate});

  final List<SearchHit> hits;
  final List<MatchSummary> matchesOnDate;

  factory SearchResult.fromJson(Map<String, dynamic> j) => SearchResult(
        hits: [for (final h in j['hits'] as List<dynamic>) SearchHit.fromJson(h as Map<String, dynamic>)],
        matchesOnDate: [
          for (final m in j['matches_on_date'] as List<dynamic>)
            MatchSummary.fromJson(m as Map<String, dynamic>),
        ],
      );
}

class SourceStatus {
  const SourceStatus({required this.name, required this.configured, required this.attribution});

  final String name;
  final bool configured;
  final String attribution;

  factory SourceStatus.fromJson(Map<String, dynamic> j) => SourceStatus(
        name: j['name'] as String,
        configured: j['configured'] as bool,
        attribution: j['attribution'] as String,
      );
}

/// Resultado de una consulta que puede proceder de la caché local.
class Loaded<T> {
  const Loaded(this.data, {this.cachedAt});

  final T data;

  /// Si no es null, los datos proceden de la caché porque la red falló.
  final DateTime? cachedAt;

  bool get fromCache => cachedAt != null;
}
