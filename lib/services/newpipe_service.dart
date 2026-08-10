import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/video_item.dart';

/// One playable video rendition.
class VideoStreamOption {
  final String url;
  final String resolution;
  final int height;

  /// True when the stream carries no audio and must be paired with a separate
  /// audio track. YouTube only muxes the two at low resolutions.
  final bool videoOnly;

  const VideoStreamOption({
    required this.url,
    required this.resolution,
    required this.height,
    required this.videoOnly,
  });

  String get label => resolution.isNotEmpty
      ? resolution
      : (height > 0 ? '${height}p' : 'авто');
}

/// One audio rendition. [trackType] is NewPipe's AudioTrackType — ORIGINAL,
/// DUBBED, DESCRIPTIVE or SECONDARY — and empty when the video has a single
/// track and YouTube says nothing about it.
class AudioStreamOption {
  final String url;
  final int bitrate;
  final String trackType;
  final String language;
  final String trackName;

  const AudioStreamOption({
    required this.url,
    required this.bitrate,
    required this.trackType,
    required this.language,
    required this.trackName,
  });

  String describe() => '${trackType.isEmpty ? 'UNTYPED' : trackType}'
      '/${language.isEmpty ? '??' : language} ${bitrate}bps';
}

/// Everything needed to play one video directly, sorted best-first.
class VideoStreams {
  final List<VideoStreamOption> video;
  final String? audioUrl;

  /// What extraction actually found, for when the quality list comes back
  /// shorter than expected. Shown in the quality sheet because the alternative
  /// is reading a device log.
  final String diagnostics;

  const VideoStreams({
    required this.video,
    this.audioUrl,
    this.diagnostics = '',
  });

  /// Video-only renditions are unusable without a separate audio track.
  List<VideoStreamOption> get playable => audioUrl == null
      ? video.where((v) => !v.videoOnly).toList()
      : video;
}

/// Channel listings via NewPipeExtractor, running on the Android side.
///
/// This is the primary source. It reports the whole archive with durations and
/// tells Shorts apart by which channel tab they came from, so nothing needs a
/// follow-up request per video the way the Atom feed did.
class NewPipeService {
  static const MethodChannel _channel = MethodChannel('kidtube/newpipe');
  final Uuid _uuid = const Uuid();

  /// False on any platform without the native side wired up, so callers can
  /// skip straight to the fallback.
  bool get isAvailable => Platform.isAndroid;

  /// Returns null — as opposed to an empty list — when the extractor could not
  /// be reached at all. An empty list means the channel genuinely has no
  /// videos, and the caller must not confuse the two: one warrants a fallback,
  /// the other does not.
  Future<List<VideoItem>?> channelVideos(
    String youtubeChannelId, {
    required int limit,
    Set<String> stopAtIds = const {},
  }) async {
    if (!isAvailable) return null;

    try {
      final raw = await _channel.invokeListMethod<dynamic>('channelVideos', {
        'channelId': youtubeChannelId,
        'limit': limit,
        'stopAtIds': stopAtIds.toList(),
      });
      if (raw == null) return null;

      final videos = <VideoItem>[];
      for (final entry in raw) {
        final map = Map<String, dynamic>.from(entry as Map);
        final id = map['id'] as String?;
        if (id == null || id.isEmpty) continue;

        final seconds = (map['durationSeconds'] as num?)?.toInt() ?? 0;
        final uploadedAt = map['uploadedAtMillis'] as int?;

        videos.add(VideoItem(
          id: _uuid.v4(),
          youtubeVideoId: id,
          title: (map['title'] as String?) ?? '',
          channelName: (map['channelName'] as String?) ?? '',
          channelId: (map['channelId'] as String?) ?? youtubeChannelId,
          thumbnailUrl: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
          duration: _formatDuration(seconds),
          viewCount: _formatViewCount((map['viewCount'] as num?)?.toInt() ?? 0),
          publishedAt: uploadedAt == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(uploadedAt),
          isShort: (map['isShort'] as bool?) ?? false,
        ));
      }

      developer.log('NewPipe $youtubeChannelId: ${videos.length} videos');
      return videos;
    } on MissingPluginException {
      developer.log('NewPipe bridge is not registered on this platform');
      return null;
    } on PlatformException catch (e) {
      developer.log('NewPipe failed for $youtubeChannelId: ${e.message}');
      return null;
    } catch (e) {
      developer.log('NewPipe call failed for $youtubeChannelId: $e');
      return null;
    }
  }

  /// Chooses the audio track the video was actually made with.
  ///
  /// YouTube attaches machine-translated dubs to a growing number of videos,
  /// and they arrive in the same list as the real thing. Sorting by bitrate
  /// alone picked whichever was encoded fattest, which is how a Russian
  /// channel ended up narrated in Arabic.
  AudioStreamOption? _pickAudio(List<AudioStreamOption> tracks) {
    if (tracks.isEmpty) return null;

    // Best bitrate *within* the preferred group, not across all of them.
    AudioStreamOption? bestOf(bool Function(AudioStreamOption) matches) {
      AudioStreamOption? best;
      for (final track in tracks) {
        if (!matches(track)) continue;
        if (best == null || track.bitrate > best.bitrate) best = track;
      }
      return best;
    }

    // A track explicitly marked original wins outright.
    final original = bestOf((t) => t.trackType == 'ORIGINAL');
    if (original != null) return original;

    // Nothing marked: on videos without dubs the type is simply absent, so an
    // untyped track is the original by elimination.
    final untyped = bestOf((t) => t.trackType.isEmpty);
    if (untyped != null) return untyped;

    // Everything is a dub. Prefer Russian, then English, then give up and take
    // the loudest — better some audio than none.
    return bestOf((t) => t.language == 'ru') ??
        bestOf((t) => t.language == 'en') ??
        bestOf((_) => true);
  }

  /// Playable stream URLs for one video, or null when extraction failed and
  /// the caller should fall back to the embedded YouTube player.
  Future<VideoStreams?> videoStreams(String youtubeVideoId) async {
    if (!isAvailable) return null;

    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
          'videoStreams', {'videoId': youtubeVideoId});
      if (raw == null) return null;

      final video = <VideoStreamOption>[];
      for (final entry in (raw['video'] as List? ?? const [])) {
        final map = Map<String, dynamic>.from(entry as Map);
        final url = map['url'] as String?;
        if (url == null || url.isEmpty) continue;
        final resolution = (map['resolution'] as String?) ?? '';
        video.add(VideoStreamOption(
          url: url,
          resolution: resolution,
          // Some streams report no height; the label carries it instead.
          height: (map['height'] as num?)?.toInt() ??
              int.tryParse(RegExp(r'(\d+)').firstMatch(resolution)?.group(1) ?? '') ??
              0,
          videoOnly: (map['videoOnly'] as bool?) ?? false,
        ));
      }

      final audio = <AudioStreamOption>[];
      for (final entry in (raw['audio'] as List? ?? const [])) {
        final map = Map<String, dynamic>.from(entry as Map);
        final url = map['url'] as String?;
        if (url == null || url.isEmpty) continue;
        audio.add(AudioStreamOption(
          url: url,
          bitrate: (map['bitrate'] as num?)?.toInt() ?? 0,
          trackType: (map['trackType'] as String?) ?? '',
          language: (map['language'] as String?) ?? '',
          trackName: (map['trackName'] as String?) ?? '',
        ));
      }

      final bestAudio = _pickAudio(audio);

      if (video.isEmpty) return null;
      video.sort((a, b) => b.height.compareTo(a.height));

      final d = Map<String, dynamic>.from(
          (raw['diagnostics'] as Map?) ?? const <String, dynamic>{});
      final diagnostics = 'совмещённых ${d['usableMuxed'] ?? '?'}'
          '/${d['rawMuxed'] ?? '?'}, '
          'раздельных ${d['usableVideoOnly'] ?? '?'}'
          '/${d['rawVideoOnly'] ?? '?'}, '
          'звук ${d['usableAudio'] ?? '?'}/${d['rawAudio'] ?? '?'}';

      developer.log('NewPipe streams for $youtubeVideoId: $diagnostics, '
          'audio=${bestAudio?.describe()}');
      return VideoStreams(
        video: video,
        audioUrl: bestAudio?.url,
        diagnostics: diagnostics,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      developer.log('Stream extraction failed for $youtubeVideoId: ${e.message}');
      return null;
    } catch (e) {
      developer.log('Stream extraction failed for $youtubeVideoId: $e');
      return null;
    }
  }

  String _formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '';
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    if (hours > 0) return '$hours:${two(minutes)}:${two(seconds)}';
    return '$minutes:${two(seconds)}';
  }

  String _formatViewCount(int count) {
    if (count >= 1000000000) return '${(count / 1000000000).toStringAsFixed(1)}B';
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}
