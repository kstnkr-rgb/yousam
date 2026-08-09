import 'dart:developer' as developer;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/video_item.dart';
import '../models/channel_item.dart';
import '../utils/config.dart';
import 'package:uuid/uuid.dart';

class YouTubeService {
  YoutubeExplode? _yt;
  final Uuid _uuid = const Uuid();

  YoutubeExplode get yt {
    _yt ??= YoutubeExplode();
    return _yt!;
  }

  /// Extract @handle from a URL like https://www.youtube.com/@CyberBugz
  String? _extractHandle(String input) {
    final cleaned = input.trim();

    // Direct handle: @CyberBugz
    if (cleaned.startsWith('@')) {
      return cleaned;
    }

    // URL format: https://www.youtube.com/@CyberBugz
    final uri = Uri.tryParse(cleaned);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      for (final segment in uri.pathSegments) {
        if (segment.startsWith('@')) {
          return segment;
        }
      }
    }

    // Check if URL contains /@. Deliberately not \w: handles can be Cyrillic,
    // and \w is ASCII-only in Dart.
    final handleMatch = RegExp(r'/@([^/?#]+)').firstMatch(cleaned);
    if (handleMatch != null) {
      return '@${Uri.decodeComponent(handleMatch.group(1)!)}';
    }

    return null;
  }

  /// Pull the name out of a legacy custom URL: /c/TeslaKids, /user/Foo, or a
  /// bare name.
  String? _extractLegacyName(String input) {
    final match =
        RegExp(r'youtube\.com/(?:c/|user/)?([^/?#@]+)').firstMatch(input.trim());
    final name = match?.group(1)?.trim();
    if (name != null && name.isNotEmpty) return Uri.decodeComponent(name);

    // Not a URL at all — treat the whole string as a name.
    if (!input.contains('/') && !input.startsWith('@')) return input.trim();
    return null;
  }

  /// Resolve a channel URL/handle/ID to a Channel object
  Future<Channel?> resolveChannel(String input) => _resolveChannel(input);

  Future<Channel?> _resolveChannel(String input) async {
    final cleaned = input.trim();
    developer.log('Resolving channel from: $cleaned');

    // 1. Try @handle format
    final handle = _extractHandle(cleaned);
    if (handle != null) {
      developer.log('Detected handle: $handle');
      try {
        final channel = await yt.channels.getByHandle(handle);
        developer.log('Resolved handle to channel: ${channel.title} (${channel.id})');
        return channel;
      } catch (e) {
        developer.log('getByHandle failed for $handle: $e');
      }
    }

    // 2. Try standard channel ID (UC...)
    try {
      final channelId = ChannelId.parseChannelId(cleaned);
      if (channelId != null) {
        developer.log('Parsed channel ID: $channelId');
        final channel = await yt.channels.get(channelId);
        return channel;
      }
    } catch (e) {
      developer.log('parseChannelId failed: $e');
    }

    // 3. Legacy custom URL (/c/TeslaKids) or a bare name.
    final legacy = _extractLegacyName(cleaned);
    if (legacy != null) {
      // Most /c/ vanity names were carried over verbatim as the @handle when
      // YouTube introduced handles, so this succeeds far more often than the
      // /user/ endpoint below.
      try {
        developer.log('Trying legacy name as handle: @$legacy');
        return await yt.channels.getByHandle('@$legacy');
      } catch (e) {
        developer.log('getByHandle failed for @$legacy: $e');
      }

      try {
        developer.log('Trying as username: $legacy');
        return await yt.channels.getByUsername(legacy);
      } catch (e) {
        developer.log('getByUsername failed for $legacy: $e');
      }
    }

    return null;
  }

  Future<VideoItem?> getVideoInfo(String videoUrl) async {
    try {
      developer.log('Fetching video info for: $videoUrl');

      String? vidId;
      try {
        vidId = VideoId.parseVideoId(videoUrl);
      } catch (_) {}

      if (vidId == null) {
        final cleaned = videoUrl.trim();
        if (cleaned.length == 11 && !cleaned.contains('/')) {
          vidId = cleaned;
        }
        final uri = Uri.tryParse(cleaned);
        if (uri != null) {
          vidId ??= uri.queryParameters['v'];
          if (uri.host.contains('youtu.be')) {
            vidId ??= uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
          }
        }
      }

      if (vidId == null) {
        developer.log('Failed to parse video ID from URL: $videoUrl');
        return null;
      }
      developer.log('Parsed video ID: $vidId');

      final video = await yt.videos.get(VideoId(vidId));
      developer.log('Got video: ${video.title}');
      final duration = video.duration;
      final isShort = duration != null && duration.inSeconds <= 60;

      return VideoItem(
        id: _uuid.v4(),
        youtubeVideoId: video.id.value,
        title: video.title,
        channelName: video.author,
        channelId: video.channelId.value,
        thumbnailUrl: video.thumbnails.highResUrl,
        channelAvatarUrl: '',
        duration: _formatDuration(duration),
        viewCount: _formatViewCount(video.engagement.viewCount),
        publishedAt: video.uploadDate ?? DateTime.now(),
        isShort: isShort,
      );
    } catch (e, stackTrace) {
      developer.log('Error fetching video: $e', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Pull a channel's uploads.
  ///
  /// [stopAtIds] turns this into an incremental refresh: `getUploads` yields
  /// newest-first, so hitting a video we already stored means everything below
  /// it is known too and the scan can stop. [scanLimit] is the safety valve for
  /// the case where nothing matches (e.g. the channel deleted its recent
  /// uploads) so a "check for new videos" never degrades into a full crawl.
  Future<List<VideoItem>> getChannelUploadsById(
    String youtubeChannelId, {
    int limit = kChannelSyncLimit,
    Set<String> stopAtIds = const {},
    int scanLimit = 0,
    void Function(int fetched)? onProgress,
  }) async {
    final videos = <VideoItem>[];
    try {
      var scanned = 0;
      await for (final video
          in yt.channels.getUploads(ChannelId(youtubeChannelId))) {
        scanned++;
        if (stopAtIds.contains(video.id.value)) {
          developer.log('Reached known video ${video.id.value}, stopping scan');
          break;
        }

        final duration = video.duration;
        videos.add(VideoItem(
          id: _uuid.v4(),
          youtubeVideoId: video.id.value,
          title: video.title,
          channelName: video.author,
          channelId: video.channelId.value,
          thumbnailUrl: video.thumbnails.highResUrl,
          duration: _formatDuration(duration),
          viewCount: _formatViewCount(video.engagement.viewCount),
          publishedAt: video.uploadDate ?? DateTime.now(),
          isShort: duration != null && duration.inSeconds <= 60,
        ));

        if (onProgress != null && videos.length % 10 == 0) {
          onProgress(videos.length);
        }
        if (videos.length >= limit) break;
        if (scanLimit > 0 && scanned >= scanLimit) break;
      }
      onProgress?.call(videos.length);
      developer.log('Fetched ${videos.length} uploads for $youtubeChannelId');
    } catch (e, stackTrace) {
      developer.log('Error fetching channel uploads: $e',
          error: e, stackTrace: stackTrace);
      // Keep whatever arrived before the failure — a partial sync beats none.
    }
    return videos;
  }

  Future<List<VideoItem>> getChannelVideos(String channelUrl,
      {int limit = kChannelSyncLimit}) async {
    final channel = await _resolveChannel(channelUrl);
    if (channel == null) {
      developer.log('Could not resolve channel: $channelUrl');
      return [];
    }
    return getChannelUploadsById(channel.id.value, limit: limit);
  }

  ChannelItem toChannelItem(Channel channel, {String sourceRef = ''}) {
    return ChannelItem(
      id: _uuid.v4(),
      youtubeChannelId: channel.id.value,
      name: channel.title,
      avatarUrl: channel.logoUrl,
      subscriberCount: '',
      sourceRef: sourceRef,
    );
  }

  Future<ChannelItem?> getChannelInfo(String channelUrl) async {
    try {
      final channel = await _resolveChannel(channelUrl);
      if (channel == null) {
        developer.log('Could not resolve channel: $channelUrl');
        return null;
      }
      return toChannelItem(channel);
    } catch (e, stackTrace) {
      developer.log('Error fetching channel: $e', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  Future<List<VideoItem>> searchVideos(String query, {int limit = 20}) async {
    try {
      developer.log('Searching YouTube for: "$query"');

      final searchList = await yt.search.search(query);
      developer.log('Search returned ${searchList.length} results');

      final videos = <VideoItem>[];

      for (final result in searchList) {
        if (videos.length >= limit) break;

        if (result is SearchVideo) {
          final duration = result.duration;
          final isShort = duration != null && duration.inSeconds <= 60;

          videos.add(VideoItem(
            id: _uuid.v4(),
            youtubeVideoId: result.id.value,
            title: result.title,
            channelName: result.author,
            channelId: result.channelId.value,
            thumbnailUrl: result.thumbnails.highResUrl,
            duration: _formatDuration(duration),
            viewCount: _formatViewCount(result.engagement.viewCount),
            isShort: isShort,
          ));
        }
      }

      developer.log('Parsed ${videos.length} video results');

      // If no video results, try to find a channel and get its uploads
      if (videos.isEmpty) {
        developer.log('No video results, trying to find channel...');
        try {
          final channel = await _resolveChannel(query);
          if (channel != null) {
            developer.log('Found channel: ${channel.title}');
            final uploads = yt.channels.getUploads(channel.id);
            await for (final video in uploads) {
              if (videos.length >= limit) break;
              final dur = video.duration;
              final isShort = dur != null && dur.inSeconds <= 60;
              videos.add(VideoItem(
                id: _uuid.v4(),
                youtubeVideoId: video.id.value,
                title: video.title,
                channelName: video.author,
                channelId: video.channelId.value,
                thumbnailUrl: video.thumbnails.highResUrl,
                duration: _formatDuration(dur),
                viewCount: _formatViewCount(video.engagement.viewCount),
                publishedAt: video.uploadDate ?? DateTime.now(),
                isShort: isShort,
              ));
            }
            developer.log('Got ${videos.length} videos from channel');
          }
        } catch (e2) {
          developer.log('Channel lookup also failed: $e2');
        }
      }

      return videos;
    } catch (e, stackTrace) {
      developer.log('Error searching: $e', error: e, stackTrace: stackTrace);

      // Fallback: try to get video directly if query looks like a URL
      if (query.contains('youtube.com') || query.contains('youtu.be')) {
        final video = await getVideoInfo(query);
        if (video != null) return [video];
      }

      return [];
    }
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatViewCount(int count) {
    if (count >= 1000000000) {
      return '${(count / 1000000000).toStringAsFixed(1)}B';
    } else if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  void dispose() {
    _yt?.close();
    _yt = null;
  }
}
