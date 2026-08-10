import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/video_item.dart';

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
