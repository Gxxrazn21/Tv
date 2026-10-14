import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Favorito guardado SOLO en el dispositivo.
class Favorite {
  const Favorite({required this.kind, required this.id, required this.label, this.detail});

  /// team | competition
  final String kind;
  final String id;
  final String label;
  final String? detail;
}

class CachedBody {
  const CachedBody(this.body, this.fetchedAt);

  final String body;
  final DateTime fetchedAt;
}

class Reminder {
  const Reminder({required this.matchId, required this.kickoffUtc, required this.title});

  final int matchId;
  final DateTime kickoffUtc;
  final String title;
}

/// Base de datos local (SQLite). No hay cuentas ni sincronización con servidores.
class LocalStore {
  LocalStore(this._db);

  final Database _db;
  static const _version = 1;
  static const cacheMaxAge = Duration(days: 14);

  static Future<LocalStore> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'openfoot.db');
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: _version, onCreate: _create),
    );
    final store = LocalStore(db);
    await store.pruneCache();
    return store;
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE favorites (
        kind TEXT NOT NULL,
        id TEXT NOT NULL,
        label TEXT NOT NULL,
        detail TEXT,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (kind, id)
      )''');
    await db.execute('''
      CREATE TABLE cache (
        key TEXT PRIMARY KEY,
        body TEXT NOT NULL,
        fetched_at INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE reminders (
        match_id INTEGER PRIMARY KEY,
        kickoff_utc INTEGER NOT NULL,
        title TEXT NOT NULL
      )''');
  }

  // --- Favoritos --------------------------------------------------------------------------
  Future<List<Favorite>> favorites() async {
    final rows = await _db.query('favorites', orderBy: 'kind, label COLLATE NOCASE');
    return [
      for (final r in rows)
        Favorite(
          kind: r['kind']! as String,
          id: r['id']! as String,
          label: r['label']! as String,
          detail: r['detail'] as String?,
        ),
    ];
  }

  Future<void> addFavorite(Favorite f) => _db.insert(
        'favorites',
        {
          'kind': f.kind,
          'id': f.id,
          'label': f.label,
          'detail': f.detail,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> removeFavorite(String kind, String id) =>
      _db.delete('favorites', where: 'kind = ? AND id = ?', whereArgs: [kind, id]);

  // --- Caché de respuestas ----------------------------------------------------------------
  Future<void> putCache(String key, String body) => _db.insert(
        'cache',
        {'key': key, 'body': body, 'fetched_at': DateTime.now().millisecondsSinceEpoch},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<CachedBody?> getCache(String key) async {
    final rows = await _db.query('cache', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return CachedBody(
      rows.first['body']! as String,
      DateTime.fromMillisecondsSinceEpoch(rows.first['fetched_at']! as int, isUtc: true),
    );
  }

  Future<void> pruneCache() async {
    final limit = DateTime.now().subtract(cacheMaxAge).millisecondsSinceEpoch;
    await _db.delete('cache', where: 'fetched_at < ?', whereArgs: [limit]);
  }

  Future<void> clearCache() => _db.delete('cache');

  // --- Recordatorios ----------------------------------------------------------------------
  Future<List<Reminder>> reminders() async {
    final rows = await _db.query('reminders', orderBy: 'kickoff_utc');
    return [
      for (final r in rows)
        Reminder(
          matchId: r['match_id']! as int,
          kickoffUtc: DateTime.fromMillisecondsSinceEpoch(r['kickoff_utc']! as int, isUtc: true),
          title: r['title']! as String,
        ),
    ];
  }

  Future<void> addReminder(Reminder r) => _db.insert(
        'reminders',
        {'match_id': r.matchId, 'kickoff_utc': r.kickoffUtc.millisecondsSinceEpoch, 'title': r.title},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> removeReminder(int matchId) =>
      _db.delete('reminders', where: 'match_id = ?', whereArgs: [matchId]);

  Future<void> close() => _db.close();
}
