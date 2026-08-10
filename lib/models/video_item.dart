class VideoItem {
  final String id;
  final String youtubeVideoId;
  final String title;
  final String channelName;
  final String channelId;
  final String thumbnailUrl;
  final String channelAvatarUrl;
  final String duration;
  final String viewCount;
  final DateTime publishedAt;
  final bool isShort;
  final bool isApproved;

  /// Video the parent added one-by-one via URL. Stays visible even when its
  /// channel is not in the allowed list, otherwise "add video by URL" would
  /// silently do nothing.
  final bool isManual;

  VideoItem({
    required this.id,
    required this.youtubeVideoId,
    required this.title,
    required this.channelName,
    required this.channelId,
    required this.thumbnailUrl,
    this.channelAvatarUrl = '',
    this.duration = '',
    this.viewCount = '0',
    DateTime? publishedAt,
    this.isShort = false,
    this.isApproved = true,
    this.isManual = false,
  }) : publishedAt = publishedAt ?? DateTime.now();

  /// Lowercased haystack for local search. Built in Dart on purpose: SQLite's
  /// LIKE and lower() only fold ASCII, so Cyrillic titles would never match a
  /// lowercase query.
  String get searchText => '$title $channelName'.toLowerCase();

  VideoItem copyWith({
    bool? isManual,
    bool? isApproved,
    String? duration,
    String? viewCount,
    bool? isShort,
  }) {
    return VideoItem(
      id: id,
      youtubeVideoId: youtubeVideoId,
      title: title,
      channelName: channelName,
      channelId: channelId,
      thumbnailUrl: thumbnailUrl,
      channelAvatarUrl: channelAvatarUrl,
      duration: duration ?? this.duration,
      viewCount: viewCount ?? this.viewCount,
      publishedAt: publishedAt,
      isShort: isShort ?? this.isShort,
      isApproved: isApproved ?? this.isApproved,
      isManual: isManual ?? this.isManual,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'youtubeVideoId': youtubeVideoId,
      'title': title,
      'channelName': channelName,
      'channelId': channelId,
      'thumbnailUrl': thumbnailUrl,
      'channelAvatarUrl': channelAvatarUrl,
      'duration': duration,
      'viewCount': viewCount,
      'publishedAt': publishedAt.toIso8601String(),
      'isShort': isShort ? 1 : 0,
      'isApproved': isApproved ? 1 : 0,
      'isManual': isManual ? 1 : 0,
      'searchText': searchText,
    };
  }

  factory VideoItem.fromMap(Map<String, dynamic> map) {
    return VideoItem(
      id: map['id'] as String,
      youtubeVideoId: map['youtubeVideoId'] as String,
      title: map['title'] as String,
      channelName: map['channelName'] as String,
      channelId: map['channelId'] as String,
      thumbnailUrl: map['thumbnailUrl'] as String,
      channelAvatarUrl: map['channelAvatarUrl'] as String? ?? '',
      duration: map['duration'] as String? ?? '',
      viewCount: map['viewCount'] as String? ?? '0',
      publishedAt: DateTime.tryParse(map['publishedAt'] as String? ?? '') ?? DateTime.now(),
      isShort: (map['isShort'] as int?) == 1,
      isApproved: (map['isApproved'] as int?) == 1,
      isManual: (map['isManual'] as int?) == 1,
    );
  }
}
