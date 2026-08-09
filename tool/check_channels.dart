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

    final count = await _countUploads(yt, channel.id.value);
    if (count == 0) {
      empty++;
      print('БЕЗ ВИДЕО   ${channel.title}  (${channel.id})  <- $entry');
    } else {
      ok++;
      print('ok $count+   ${channel.title}  (${channel.id})');
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
