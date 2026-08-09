// Diagnostic: resolve every entry in channels.json and try to fetch uploads.
//
// This exists because the failure that emptied the feed was invisible from the
// outside — channels resolved, icons appeared, and no error was raised
// anywhere. Running this answers "does YouTube still talk to us?" in two
// minutes instead of a 54 MB reinstall.
//
//   dart run tool/check_channels.dart
//
// Pure Dart on purpose: no Flutter imports, so it runs headless in CI.

import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main(List<String> args) async {
  final path = args.isNotEmpty ? args.first : 'channels.json';
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Не найден $path');
    exit(2);
  }

  final decoded = jsonDecode(file.readAsStringSync());
  final raw = decoded is List ? decoded : (decoded as Map)['channels'] as List;
  final entries = raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty);

  final yt = YoutubeExplode();
  var unresolved = 0;
  var empty = 0;
  var ok = 0;

  for (final entry in entries) {
    final channel = await _resolve(yt, entry);
    if (channel == null) {
      unresolved++;
      print('НЕ НАЙДЕН   $entry');
      continue;
    }

    final scraped = await _countUploads(yt, channel.id.value);
    final rss = scraped > 0 ? 0 : await _countRss(channel.id.value);

    if (scraped > 0) {
      ok++;
      print('ok $scraped+ (скрейпинг)   ${channel.title}  (${channel.id})');
    } else if (rss > 0) {
      ok++;
      print('ok $rss (RSS)              ${channel.title}  (${channel.id})');
    } else {
      empty++;
      print('БЕЗ ВИДЕО                  ${channel.title}  (${channel.id})  <- $entry');
    }
  }

  yt.close();
  print('\nВсего: ok=$ok, без видео=$empty, не найдено=$unresolved');

  // Non-zero exit only when nothing at all worked: YouTube throttling a
  // datacenter IP should not be reported as "your channel list is broken".
  if (ok == 0) {
    stderr.writeln('Ни один канал не отдал видео — похоже, сломан API.');
    exit(1);
  }
}

/// Mirrors the resolution order in lib/services/youtube_service.dart.
Future<Channel?> _resolve(YoutubeExplode yt, String entry) async {
  final uri = Uri.tryParse(entry);
  String? handle;
  if (entry.startsWith('@')) {
    handle = entry;
  } else if (uri != null) {
    for (final segment in uri.pathSegments) {
      if (segment.startsWith('@')) handle = segment;
    }
  }

  if (handle != null) {
    try {
      return await yt.channels.getByHandle(handle);
    } catch (_) {}
  }

  try {
    final id = ChannelId.parseChannelId(entry);
    if (id != null) return await yt.channels.get(ChannelId(id));
  } catch (_) {}

  final legacy =
      RegExp(r'youtube\.com/(?:c/|user/)?([^/?#@]+)').firstMatch(entry)?.group(1);
  if (legacy != null) {
    try {
      return await yt.channels.getByHandle('@$legacy');
    } catch (_) {}
    try {
      return await yt.channels.getByUsername(legacy);
    } catch (_) {}
  }

  // Last resort, mirroring the app: read the canonical id off the page.
  final url = entry.startsWith('@')
      ? 'https://www.youtube.com/$entry'
      : (entry.contains('youtube.com') ? entry : null);
  if (url != null) {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent',
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final id = RegExp(r'"(?:externalId|channelId)":"(UC[\w-]{22})"')
          .firstMatch(body)
          ?.group(1);
      if (id != null) return await yt.channels.get(ChannelId(id));
    } catch (e) {
      stderr.writeln('  резолв по странице не удался: $e');
    }
  }
  return null;
}

/// Counts up to 5 uploads, trying the same fallback the app uses.
Future<int> _countUploads(YoutubeExplode yt, String channelId) async {
  var count = await _take(yt.channels.getUploads(ChannelId(channelId)));
  if (count == 0) {
    count = await _take(
        yt.playlists.getVideos(PlaylistId('UU${channelId.substring(2)}')));
  }
  return count;
}

/// Counts entries in the channel's Atom feed — the app's last-resort source.
Future<int> _countRss(String channelId) async {
  final uri = Uri.parse(
      'https://www.youtube.com/feeds/videos.xml?channel_id=$channelId');
  try {
    final client = HttpClient();
    final request = await client.getUrl(uri);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    client.close();
    if (response.statusCode != 200) {
      stderr.writeln('  RSS вернул HTTP ${response.statusCode}');
      return 0;
    }
    return '<entry>'.allMatches(body).length;
  } catch (e) {
    stderr.writeln('  RSS недоступен: $e');
    return 0;
  }
}

Future<int> _take(Stream<Video> source) async {
  var count = 0;
  try {
    await for (final _ in source) {
      if (++count >= 5) break;
    }
  } catch (e) {
    stderr.writeln('  ошибка при получении видео: $e');
  }
  return count;
}
