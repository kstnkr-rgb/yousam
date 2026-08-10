import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/video_item.dart';
import '../models/channel_item.dart';
import '../utils/config.dart';
import 'newpipe_service.dart';
import 'package:uuid/uuid.dart';

class YouTubeService {
  YoutubeExplode? _yt;
  final Uuid _uuid = const Uuid();
  final NewPipeService _newPipe = NewPipeService();

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

    // 4. Read the id off the channel page itself.
    return _resolveViaPage(cleaned);
  }

  /// Last resort: fetch the channel page and pull its canonical UC id out of
  /// the HTML.
  ///
  /// Needed because getByHandle does not cope with non-ASCII handles — a
  /// Cyrillic @handle never resolves through the library, however it is
  /// encoded.
  Future<Channel?> _resolveViaPage(String input) async {
    final url = input.startsWith('@')
        ? 'https://www.youtube.com/$input'
        : (input.contains('youtube.com') ? input : null);
    if (url == null) return null;

    try {
      final response = await http.get(Uri.parse(url), headers: {
        // Without a browser UA YouTube tends to answer with a consent
        // interstitial that carries no channel id.
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36',
        'Accept-Language': 'ru,en;q=0.9',
      }).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        developer.log('Channel page $url: HTTP ${response.statusCode}');
        return null;
      }

      final body = utf8.decode(response.bodyBytes);
      final id = (RegExp(r'"(?:externalId|channelId)":"(UC[\w-]{22})"')
                  .firstMatch(body) ??
              RegExp(r'youtube\.com/channel/(UC[\w-]{22})').firstMatch(body))
          ?.group(1);

      if (id == null) {
        developer.log('No channel id found on $url');
        return null;
      }

      developer.log('Resolved $url to $id via page');
      return await yt.channels.get(ChannelId(id));
    } catch (e) {
      developer.log('Page resolution failed for $url: $e');
      return null;
    }
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
  /// [stopAtIds] turns this into an incremental refresh: listings come
  /// newest-first, so hitting a video we already stored means everything below
  /// it is known too and collection can stop there.
  Future<List<VideoItem>> getChannelUploadsById(
    String youtubeChannelId, {
    int limit = kChannelSyncLimit,
    Set<String> stopAtIds = const {},
    void Function(int fetched)? onProgress,
  }) async {
    // NewPipeExtractor first: it returns the full archive with durations
    // already attached, and separates Shorts by channel tab. The Dart
    // scraper's channel listing has been broken upstream since YouTube moved
    // to the lockupViewModel layout, so it is no longer even attempted — it
    // only ever cost two dead requests per channel.
    final viaNewPipe = await _newPipe.channelVideos(
      youtubeChannelId,
      limit: limit,
      stopAtIds: stopAtIds,
    );
    if (viaNewPipe != null && viaNewPipe.isNotEmpty) {
      onProgress?.call(viaNewPipe.length);
      developer.log('Fetched ${viaNewPipe.length} uploads via NewPipe '
          'for $youtubeChannelId');
      return viaNewPipe;
    }

    // Atom feed: shallower and without durations, but a plain public endpoint
    // that keeps working when extraction breaks.
    developer.log('NewPipe gave nothing, falling back to RSS');
    final videos = await getUploadsViaRss(youtubeChannelId, stopAtIds: stopAtIds);
    onProgress?.call(videos.length);

    developer.log('Fetched ${videos.length} uploads for $youtubeChannelId');
    return videos;
  }

  /// The channel's Atom feed: the 15 most recent uploads.
  ///
  /// Shallower than scraping and carries no duration, so videos from here are
  /// all treated as regular ones — Shorts cannot be told apart without it.
  /// The trade is deliberate: a feed of the newest 15 per channel beats an
  /// empty app.
  Future<List<VideoItem>> getUploadsViaRss(
    String youtubeChannelId, {
    Set<String> stopAtIds = const {},
    int limit = kFeedVideoLimit,
  }) async {
    final uri = Uri.parse(
        'https://www.youtube.com/feeds/videos.xml?channel_id=$youtubeChannelId');
    final videos = <VideoItem>[];

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        developer.log('RSS $youtubeChannelId: HTTP ${response.statusCode}');
        return videos;
      }

      final feed = XmlDocument.parse(utf8.decode(response.bodyBytes));
      final author = _firstText(feed.rootElement, 'name');

      for (final entry in feed.findAllElements('entry')) {
        if (videos.length >= limit) break;
        final videoId = _firstText(entry, 'videoId');
        if (videoId.isEmpty || stopAtIds.contains(videoId)) continue;

        final entryAuthor = _firstText(entry, 'name');
        final entryChannel = _firstText(entry, 'channelId');
        final thumbnail = _firstAttribute(entry, 'thumbnail', 'url');

        videos.add(VideoItem(
          id: _uuid.v4(),
          youtubeVideoId: videoId,
          title: _firstText(entry, 'title'),
          channelName: entryAuthor.isEmpty ? author : entryAuthor,
          channelId: entryChannel.isEmpty ? youtubeChannelId : entryChannel,
          thumbnailUrl: thumbnail.isEmpty
              ? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg'
              : thumbnail,
          viewCount: _formatViewCount(
              int.tryParse(_firstAttribute(entry, 'statistics', 'views')) ?? 0),
          publishedAt: DateTime.tryParse(_firstText(entry, 'published')),
        ));
      }
      developer.log('RSS $youtubeChannelId: ${videos.length} videos');
      return _withDurations(videos);
    } catch (e, stackTrace) {
      developer.log('RSS failed for $youtubeChannelId: $e',
          error: e, stackTrace: stackTrace);
    }
    return videos;
  }

  /// Fills in duration for videos that came from the feed.
  ///
  /// The feed carries no duration, and without it a Short is
  /// indistinguishable from a normal video — the Shorts tab stayed empty and
  /// no card showed a length badge. Single-video lookups still work even
  /// though the channel-listing API does not, so each entry is topped up
  /// individually. A few at a time: this runs for every new video, and
  /// hammering YouTube earns a rate limit.
  Future<List<VideoItem>> _withDurations(List<VideoItem> videos) async {
    const concurrency = 6;
    final filled = List<VideoItem>.from(videos);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= filled.length) return;
        try {
          final video =
              await yt.videos.get(VideoId(filled[index].youtubeVideoId));
          final duration = video.duration;
          filled[index] = filled[index].copyWith(
            duration: _formatDuration(duration),
            isShort: duration != null && duration.inSeconds <= 60,
            viewCount: _formatViewCount(video.engagement.viewCount),
          );
        } catch (e) {
          // Keep the feed version: a missing badge beats a missing video.
          developer.log('Duration lookup failed for '
              '${filled[index].youtubeVideoId}: $e');
        }
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    return filled;
  }

  /// Namespace-agnostic lookup: the feed mixes the Atom, `yt:` and `media:`
  /// namespaces, and matching on qualified names would break if YouTube ever
  /// changed a prefix.
  String _firstText(XmlElement parent, String localName) {
    for (final element in parent.descendantElements) {
      if (element.localName == localName) return element.innerText.trim();
    }
    return '';
  }

  String _firstAttribute(XmlElement parent, String localName, String attribute) {
    for (final element in parent.descendantElements) {
      if (element.localName == localName) {
        return element.getAttribute(attribute) ?? '';
      }
    }
    return '';
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
