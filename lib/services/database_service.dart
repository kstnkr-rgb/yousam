import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/video_item.dart';
import '../models/channel_item.dart';

/// A video is shown to the child when it belongs to an allowed channel, or was
/// approved one-by-one by the parent. A blocked channel always wins.
const String _visibleWhere = '''
  isApproved = 1
  AND (
    isManual = 1
    OR channelId IN (
      SELECT youtubeChannelId FROM channels WHERE isAllowed = 1 AND isBlocked = 0
    )
  )
  AND channelId NOT IN (
    SELECT youtubeChannelId FROM channels WHERE isBlocked = 1
  )
''';

class DatabaseService {
  static Database? _database;
  static final DatabaseService instance = DatabaseService._init();

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('safe_tube.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE videos (
        id TEXT PRIMARY KEY,
        youtubeVideoId TEXT NOT NULL,
        title TEXT NOT NULL,
        channelName TEXT NOT NULL,
        channelId TEXT NOT NULL,
        thumbnailUrl TEXT NOT NULL,
        channelAvatarUrl TEXT DEFAULT '',
        duration TEXT DEFAULT '',
        viewCount TEXT DEFAULT '0',
        publishedAt TEXT NOT NULL,
        isShort INTEGER DEFAULT 0,
        isApproved INTEGER DEFAULT 1,
        isManual INTEGER DEFAULT 0,
        searchText TEXT DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE channels (
        id TEXT PRIMARY KEY,
        youtubeChannelId TEXT NOT NULL,
        name TEXT NOT NULL,
        avatarUrl TEXT DEFAULT '',
        subscriberCount TEXT DEFAULT '0',
        isAllowed INTEGER DEFAULT 1,
        isBlocked INTEGER DEFAULT 0,
        sourceRef TEXT DEFAULT '',
        lastSyncedAt TEXT DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await _createIndexes(db);
  }

  /// Re-syncing a channel used to duplicate every video: each fetch minted a
  /// fresh uuid primary key, so nothing collided. These indexes are what make
  /// syncing idempotent.
  Future<void> _createIndexes(Database db) async {
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_videos_ytid ON videos(youtubeVideoId)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_channels_ytid ON channels(youtubeChannelId)');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE videos ADD COLUMN isManual INTEGER DEFAULT 0");
      await db.execute("ALTER TABLE videos ADD COLUMN searchText TEXT DEFAULT ''");
      await db.execute("ALTER TABLE channels ADD COLUMN sourceRef TEXT DEFAULT ''");
      await db.execute("ALTER TABLE channels ADD COLUMN lastSyncedAt TEXT DEFAULT ''");

      // Drop duplicates accumulated before the unique indexes existed,
      // keeping the oldest row of each group.
      await db.execute('''
        DELETE FROM videos WHERE rowid NOT IN (
          SELECT MIN(rowid) FROM videos GROUP BY youtubeVideoId
        )
      ''');
      await db.execute('''
        DELETE FROM channels WHERE rowid NOT IN (
          SELECT MIN(rowid) FROM channels GROUP BY youtubeChannelId
        )
      ''');

      await _createIndexes(db);

      // Backfill searchText in Dart — SQLite's lower() leaves Cyrillic alone.
      final rows = await db.query('videos', columns: ['id', 'title', 'channelName']);
      final batch = db.batch();
      for (final row in rows) {
        final haystack =
            '${row['title'] as String? ?? ''} ${row['channelName'] as String? ?? ''}'
                .toLowerCase();
        batch.update('videos', {'searchText': haystack},
            where: 'id = ?', whereArgs: [row['id']]);
      }
      await batch.commit(noResult: true);
    }
  }

  // ---------------------------------------------------------------- videos

  Future<void> insertVideo(VideoItem video) async {
    final db = await database;
    await db.insert('videos', video.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Bulk insert for channel syncs. Existing videos are left untouched so a
  /// re-sync never rewrites hundreds of rows.
  Future<int> insertVideos(List<VideoItem> videos) async {
    if (videos.isEmpty) return 0;
    final db = await database;
    final batch = db.batch();
    for (final video in videos) {
      batch.insert('videos', video.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    final results = await batch.commit(noResult: false);
    return results.where((r) => r is int && r > 0).length;
  }

  Future<void> deleteVideo(String id) async {
    final db = await database;
    await db.delete('videos', where: 'id = ?', whereArgs: [id]);
  }

  /// Videos the parent approved individually survive — only the channel's own
  /// uploads go away with it.
  Future<int> deleteVideosByChannel(String youtubeChannelId) async {
    final db = await database;
    return db.delete('videos',
        where: 'channelId = ? AND isManual = 0', whereArgs: [youtubeChannelId]);
  }

  Future<List<VideoItem>> getVisibleVideos() => _queryVisible();

  Future<List<VideoItem>> getVisibleRegularVideos() =>
      _queryVisible(extra: 'AND isShort = 0');

  Future<List<VideoItem>> getVisibleShorts() =>
      _queryVisible(extra: 'AND isShort = 1');

  Future<List<VideoItem>> _queryVisible({String extra = ''}) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT * FROM videos
      WHERE $_visibleWhere $extra
      ORDER BY publishedAt DESC
    ''');
    return maps.map((map) => VideoItem.fromMap(map)).toList();
  }

  /// Local full-text-ish search, restricted to what the child is allowed to
  /// see. [query] must already be lowercased by the caller.
  Future<List<VideoItem>> searchVisibleVideos(String query,
      {int limit = 100}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT * FROM videos
      WHERE $_visibleWhere AND searchText LIKE ? ESCAPE '\\'
      ORDER BY publishedAt DESC
      LIMIT ?
    ''', ['%${_escapeLike(trimmed)}%', limit]);
    return maps.map((map) => VideoItem.fromMap(map)).toList();
  }

  String _escapeLike(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');

  Future<List<VideoItem>> getAllVideos() async {
    final db = await database;
    final maps = await db.query('videos', orderBy: 'publishedAt DESC');
    return maps.map((map) => VideoItem.fromMap(map)).toList();
  }

  Future<List<VideoItem>> getVideosByChannel(String channelId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT * FROM videos
      WHERE $_visibleWhere AND channelId = ?
      ORDER BY publishedAt DESC
    ''', [channelId]);
    return maps.map((map) => VideoItem.fromMap(map)).toList();
  }

  /// Used to stop an incremental sync as soon as it reaches already-known
  /// uploads.
  Future<Set<String>> getKnownVideoIds(String youtubeChannelId) async {
    final db = await database;
    final maps = await db.query('videos',
        columns: ['youtubeVideoId'],
        where: 'channelId = ?',
        whereArgs: [youtubeChannelId]);
    return maps.map((m) => m['youtubeVideoId'] as String).toSet();
  }

  Future<int> countVideosByChannel(String youtubeChannelId) async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM videos WHERE channelId = ?',
        [youtubeChannelId]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // -------------------------------------------------------------- channels

  Future<void> insertChannel(ChannelItem channel) async {
    final db = await database;
    await db.insert('channels', channel.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteChannel(String id) async {
    final db = await database;
    await db.delete('channels', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ChannelItem>> getAllowedChannels() async {
    final db = await database;
    final maps = await db.query('channels',
        where: 'isAllowed = ? AND isBlocked = ?',
        whereArgs: [1, 0],
        orderBy: 'name COLLATE NOCASE');
    return maps.map((map) => ChannelItem.fromMap(map)).toList();
  }

  Future<List<ChannelItem>> getBlockedChannels() async {
    final db = await database;
    final maps = await db.query('channels', where: 'isBlocked = ?', whereArgs: [1]);
    return maps.map((map) => ChannelItem.fromMap(map)).toList();
  }

  Future<List<ChannelItem>> getAllChannels() async {
    final db = await database;
    final maps = await db.query('channels');
    return maps.map((map) => ChannelItem.fromMap(map)).toList();
  }

  Future<void> updateChannel(ChannelItem channel) async {
    final db = await database;
    await db.update('channels', channel.toMap(),
        where: 'id = ?', whereArgs: [channel.id]);
  }

  Future<bool> isChannelBlocked(String youtubeChannelId) async {
    final db = await database;
    final maps = await db.query('channels',
        where: 'youtubeChannelId = ? AND isBlocked = ?',
        whereArgs: [youtubeChannelId, 1]);
    return maps.isNotEmpty;
  }

  // -------------------------------------------------------------- settings

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final maps = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (maps.isNotEmpty) {
      return maps.first['value'] as String;
    }
    return null;
  }
}
