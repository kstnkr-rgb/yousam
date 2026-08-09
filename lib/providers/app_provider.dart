import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import '../models/video_item.dart';
import '../models/channel_item.dart';
import '../services/database_service.dart';
import '../services/remote_config_service.dart';
import '../services/youtube_service.dart';
import '../utils/config.dart';

class AppProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  final YouTubeService _yt = YouTubeService();
  final RemoteConfigService _remote = RemoteConfigService();

  List<VideoItem> _allVideos = [];
  List<VideoItem> _regularVideos = [];
  List<VideoItem> _shorts = [];
  List<ChannelItem> _allowedChannels = [];
  List<ChannelItem> _blockedChannels = [];
  bool _isLoading = false;
  bool _isParentMode = false;
  String _parentPin = '1234';

  // Remote channel list state
  String _channelsUrl = kDefaultRemoteChannelsUrl;
  bool _isSyncing = false;
  String _syncStatus = '';
  DateTime? _lastSyncAt;
  String? _lastSyncError;

  /// Channels that resolved fine but ended up with no videos at all. Worth
  /// surfacing: this is exactly how the broken youtube_explode channel API
  /// presented itself — icons in the app, an empty feed, and nothing in the UI
  /// saying anything was wrong.
  List<String> _emptyChannels = [];

  List<VideoItem> get allVideos => _allVideos;
  List<VideoItem> get regularVideos => _regularVideos;
  List<VideoItem> get shorts => _shorts;
  List<ChannelItem> get allowedChannels => _allowedChannels;
  List<ChannelItem> get blockedChannels => _blockedChannels;
  bool get isLoading => _isLoading;
  bool get isParentMode => _isParentMode;
  String get parentPin => _parentPin;

  String get channelsUrl => _channelsUrl;
  bool get isSyncing => _isSyncing;
  String get syncStatus => _syncStatus;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get lastSyncError => _lastSyncError;
  List<String> get emptyChannels => List.unmodifiable(_emptyChannels);
  bool get isRemoteConfigured => !_channelsUrl.contains('OWNER/REPO');

  /// Local-only startup: reads the cached database so the app opens instantly
  /// and works offline. The network round-trip to channels.json happens
  /// afterwards via [syncFromRemote].
  Future<void> init() async {
    final savedPin = await _db.getSetting(SettingsKeys.parentPin);
    if (savedPin != null) _parentPin = savedPin;

    final savedUrl = await _db.getSetting(SettingsKeys.channelsUrl);
    if (savedUrl != null && savedUrl.isNotEmpty) _channelsUrl = savedUrl;

    _lastSyncAt =
        DateTime.tryParse(await _db.getSetting(SettingsKeys.lastSyncAt) ?? '');
    _lastSyncError = await _db.getSetting(SettingsKeys.lastSyncError);
    if (_lastSyncError != null && _lastSyncError!.isEmpty) _lastSyncError = null;

    await loadAllData();
  }

  Future<void> loadAllData() async {
    _isLoading = true;
    notifyListeners();
    await _reloadLists();
    _isLoading = false;
    notifyListeners();
  }

  /// Same read, without flipping [isLoading] — used between channels during a
  /// sync so the feed fills in as it goes instead of staying blank until every
  /// channel is done.
  Future<void> _reloadLists() async {
    _allVideos = await _db.getVisibleVideos();
    _regularVideos = await _db.getVisibleRegularVideos();
    _shorts = await _db.getVisibleShorts();
    _allowedChannels = await _db.getAllowedChannels();
    _blockedChannels = await _db.getBlockedChannels();
    notifyListeners();
  }

  // ------------------------------------------------------------ parent mode

  bool verifyPin(String pin) => pin == _parentPin;

  Future<void> setParentPin(String newPin) async {
    _parentPin = newPin;
    await _db.setSetting(SettingsKeys.parentPin, newPin);
    notifyListeners();
  }

  void enterParentMode() {
    _isParentMode = true;
    notifyListeners();
  }

  void exitParentMode() {
    _isParentMode = false;
    notifyListeners();
  }

  Future<void> setChannelsUrl(String url) async {
    _channelsUrl = url.trim();
    await _db.setSetting(SettingsKeys.channelsUrl, _channelsUrl);
    notifyListeners();
  }

  // -------------------------------------------------- remote channels.json

  /// Reads channels.json and makes the local database match it.
  ///
  /// The file is the single source of truth for channels, but only once it has
  /// actually been read: any fetch or parse failure aborts before touching a
  /// single row. Otherwise a dead Wi-Fi connection would empty the child's app.
  Future<void> syncFromRemote() async {
    if (_isSyncing) return;
    _emptyChannels = [];
    _setSyncing(true, 'Проверяем список каналов…');

    RemoteChannelList? remote;
    try {
      remote = await _remote.fetch(_channelsUrl);
    } catch (e) {
      await _recordSyncError('$e');
      _setSyncing(false, '');
      return;
    }

    if (remote == null) {
      await _recordSyncError('Адрес channels.json не настроен');
      _setSyncing(false, '');
      return;
    }

    try {
      await _reconcile(remote.entries);
      await _db.setSetting(SettingsKeys.cachedChannels, remote.rawBody);
      _lastSyncAt = DateTime.now();
      _lastSyncError = null;
      await _db.setSetting(
          SettingsKeys.lastSyncAt, _lastSyncAt!.toIso8601String());
      await _db.setSetting(SettingsKeys.lastSyncError, '');
    } catch (e) {
      await _recordSyncError('$e');
    }

    _setSyncing(false, '');
    await _reloadLists();
  }

  Future<void> _reconcile(List<String> entries) async {
    final stored = await _db.getAllChannels();
    final byRef = {
      for (final c in stored.where((c) => c.isRemote)) c.sourceRef: c
    };

    // 1. Everything listed in the file. Additions run before removals on
    // purpose: adopting a hand-added channel stamps it with a sourceRef, so
    // the sweep below does not delete and immediately re-download it.
    for (final entry in entries) {
      final known = byRef[entry];
      if (known != null) {
        // A blocked channel stays blocked across syncs, so fetching its
        // uploads would only download videos the visibility rule hides.
        if (!known.isBlocked) {
          await _syncChannel(known, incremental: true);
        }
        continue;
      }

      _setSyncing(true, 'Добавляем канал $entry…');
      final resolved = await _yt.resolveChannel(entry);
      if (resolved == null) {
        // One unreachable channel must not abort the whole reconciliation.
        developer.log('Could not resolve channels.json entry: $entry');
        continue;
      }

      // The parent may have already added this channel by hand; adopt that row
      // instead of inserting a second one for the same YouTube channel.
      final existing = _findByYoutubeId(stored, resolved.id.value);

      final channel = existing != null
          ? existing.copyWith(
              sourceRef: entry, isAllowed: true, isBlocked: false)
          : _yt.toChannelItem(resolved, sourceRef: entry);

      await _db.insertChannel(channel);
      await _syncChannel(channel, incremental: existing != null);
    }

    // 2. Sweep everything the file does not account for. This covers channels
    // dropped from channels.json and channels added by hand on the device —
    // the file is the single source of truth, and the dashboard says as much
    // when it offers a temporary add.
    for (final channel in await _db.getAllChannels()) {
      if (entries.contains(channel.sourceRef)) continue;
      developer.log('Removing channel not listed in channels.json: ${channel.name}');
      await _db.deleteVideosByChannel(channel.youtubeChannelId);
      await _db.deleteChannel(channel.id);
    }
  }

  ChannelItem? _findByYoutubeId(List<ChannelItem> channels, String youtubeId) {
    for (final channel in channels) {
      if (channel.youtubeChannelId == youtubeId) return channel;
    }
    return null;
  }

  Future<void> _recordSyncError(String message) async {
    _lastSyncError = message;
    await _db.setSetting(SettingsKeys.lastSyncError, message);
    developer.log('Remote sync failed: $message');
  }

  void _setSyncing(bool value, String status) {
    _isSyncing = value;
    _syncStatus = status;
    notifyListeners();
  }

  // ------------------------------------------------------ channel syncing

  /// Fetches a channel's uploads into the database.
  ///
  /// [incremental] stops at the first already-stored video, which is what makes
  /// pull-to-refresh cheap; a fresh channel does the full [kChannelSyncLimit]
  /// crawl instead.
  Future<int> _syncChannel(ChannelItem channel, {required bool incremental}) async {
    var known = incremental
        ? await _db.getKnownVideoIds(channel.youtubeChannelId)
        : <String>{};

    // Nothing stored yet means there is nothing to stop at — a channel whose
    // first sync failed, or one that was just unblocked, needs the full crawl
    // rather than the shallow 60-video top-up.
    final topUpOnly = incremental && known.isNotEmpty;
    if (!topUpOnly) known = <String>{};

    _setSyncing(true, 'Загружаем «${channel.name}»…');

    final videos = await _yt.getChannelUploadsById(
      channel.youtubeChannelId,
      limit: topUpOnly ? kIncrementalScanLimit : kChannelSyncLimit,
      stopAtIds: known,
      scanLimit: topUpOnly ? kIncrementalScanLimit : 0,
      onProgress: (count) {
        _setSyncing(true, 'Загружаем «${channel.name}» — $count видео');
      },
    );

    final inserted = await _db.insertVideos(videos);
    await _db.updateChannel(channel.copyWith(lastSyncedAt: DateTime.now()));
    developer.log('${channel.name}: $inserted new videos');

    if (await _db.countVideosByChannel(channel.youtubeChannelId) == 0) {
      _emptyChannels.add(channel.name);
    }

    // Surface this channel's videos right away rather than after the whole
    // batch — with a dozen-plus channels the first run takes minutes.
    if (inserted > 0) await _reloadLists();
    return inserted;
  }

  Future<void> syncChannel(ChannelItem channel) async {
    if (_isSyncing) return;
    _setSyncing(true, '');
    await _syncChannel(channel, incremental: true);
    _setSyncing(false, '');
    await _reloadLists();
  }

  /// Refreshes uploads for every allowed channel without re-reading the file.
  Future<void> syncAllChannels() async {
    if (_isSyncing) return;
    _emptyChannels = [];
    _setSyncing(true, '');
    for (final channel in await _db.getAllowedChannels()) {
      await _syncChannel(channel, incremental: true);
    }
    _setSyncing(false, '');
    await _reloadLists();
  }

  /// What pull-to-refresh does: re-read the file, then top up the channels the
  /// reconciliation does not cover (the ones added by hand on the device).
  Future<void> refreshEverything() async {
    await syncFromRemote();

    final local =
        (await _db.getAllowedChannels()).where((c) => !c.isRemote).toList();
    if (local.isEmpty) return;

    _setSyncing(true, '');
    for (final channel in local) {
      await _syncChannel(channel, incremental: true);
    }
    _setSyncing(false, '');
    await _reloadLists();
  }

  // ------------------------------------------------------------ management

  Future<VideoItem?> addVideoByUrl(String url) async {
    _isLoading = true;
    notifyListeners();

    final video = await _yt.getVideoInfo(url);
    if (video != null) {
      final isBlocked = await _db.isChannelBlocked(video.channelId);
      if (!isBlocked) {
        // Marked manual so it stays visible even though its channel is not in
        // the allowed list.
        await _db.insertVideo(video.copyWith(isManual: true));
        await loadAllData();
        return video;
      }
    }

    _isLoading = false;
    notifyListeners();
    return null;
  }

  Future<void> removeVideo(String id) async {
    await _db.deleteVideo(id);
    await loadAllData();
  }

  /// Adds a channel from the parent dashboard. It gets an empty `sourceRef`,
  /// which means the next remote sync will drop it — the dashboard says so.
  Future<ChannelItem?> addChannelByUrl(String url) async {
    if (_isSyncing) return null;
    _setSyncing(true, 'Ищем канал…');

    final resolved = await _yt.resolveChannel(url.trim());
    if (resolved == null) {
      _setSyncing(false, '');
      return null;
    }

    final channel = _yt.toChannelItem(resolved);
    await _db.insertChannel(channel);
    await _syncChannel(channel, incremental: false);

    _setSyncing(false, '');
    await loadAllData();
    return channel;
  }

  Future<void> blockChannel(ChannelItem channel) async {
    await _db.updateChannel(channel.copyWith(isAllowed: false, isBlocked: true));
    await loadAllData();
  }

  Future<void> unblockChannel(ChannelItem channel) async {
    await _db.updateChannel(channel.copyWith(isAllowed: true, isBlocked: false));
    await loadAllData();
  }

  Future<void> removeChannel(String id) async {
    for (final channel in await _db.getAllChannels()) {
      if (channel.id != id) continue;
      await _db.deleteVideosByChannel(channel.youtubeChannelId);
      break;
    }
    await _db.deleteChannel(id);
    await loadAllData();
  }

  // ---------------------------------------------------------------- search

  /// The child's search. Local only — it can physically not surface a video
  /// from outside the allowed channels.
  Future<List<VideoItem>> searchLocal(String query) {
    return _db.searchVisibleVideos(query.toLowerCase());
  }

  Future<List<VideoItem>> videosOfChannel(String youtubeChannelId) {
    return _db.getVideosByChannel(youtubeChannelId);
  }

  /// Parent-only: searches all of YouTube in order to approve new content.
  Future<List<VideoItem>> searchYouTube(String query) {
    return _yt.searchVideos(query);
  }

  Future<void> approveVideo(VideoItem video) async {
    await _db.insertVideo(video.copyWith(isManual: true));
    await loadAllData();
  }

  @override
  void dispose() {
    _yt.dispose();
    _remote.dispose();
    super.dispose();
  }
}
