class ChannelItem {
  final String id;
  final String youtubeChannelId;
  final String name;
  final String avatarUrl;
  final String subscriberCount;
  final bool isAllowed;
  final bool isBlocked;

  /// The verbatim entry from channels.json this channel came from (a URL,
  /// an @handle or a raw UC id). Empty for channels added by hand on the
  /// device. Reconciliation matches on this so a handle never has to be
  /// re-resolved over the network just to be recognised.
  final String sourceRef;

  final DateTime? lastSyncedAt;

  ChannelItem({
    required this.id,
    required this.youtubeChannelId,
    required this.name,
    this.avatarUrl = '',
    this.subscriberCount = '0',
    this.isAllowed = true,
    this.isBlocked = false,
    this.sourceRef = '',
    this.lastSyncedAt,
  });

  bool get isRemote => sourceRef.isNotEmpty;

  ChannelItem copyWith({
    String? name,
    String? avatarUrl,
    bool? isAllowed,
    bool? isBlocked,
    String? sourceRef,
    DateTime? lastSyncedAt,
  }) {
    return ChannelItem(
      id: id,
      youtubeChannelId: youtubeChannelId,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      subscriberCount: subscriberCount,
      isAllowed: isAllowed ?? this.isAllowed,
      isBlocked: isBlocked ?? this.isBlocked,
      sourceRef: sourceRef ?? this.sourceRef,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'youtubeChannelId': youtubeChannelId,
      'name': name,
      'avatarUrl': avatarUrl,
      'subscriberCount': subscriberCount,
      'isAllowed': isAllowed ? 1 : 0,
      'isBlocked': isBlocked ? 1 : 0,
      'sourceRef': sourceRef,
      'lastSyncedAt': lastSyncedAt?.toIso8601String() ?? '',
    };
  }

  factory ChannelItem.fromMap(Map<String, dynamic> map) {
    return ChannelItem(
      id: map['id'] as String,
      youtubeChannelId: map['youtubeChannelId'] as String,
      name: map['name'] as String,
      avatarUrl: map['avatarUrl'] as String? ?? '',
      subscriberCount: map['subscriberCount'] as String? ?? '0',
      isAllowed: (map['isAllowed'] as int?) == 1,
      isBlocked: (map['isBlocked'] as int?) == 1,
      sourceRef: map['sourceRef'] as String? ?? '',
      lastSyncedAt: DateTime.tryParse(map['lastSyncedAt'] as String? ?? ''),
    );
  }
}
