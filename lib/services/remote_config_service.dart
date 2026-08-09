import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;

/// Result of reading channels.json. [entries] is only ever non-null when the
/// file was fetched *and* parsed successfully.
class RemoteChannelList {
  final List<String> entries;
  final String rawBody;

  const RemoteChannelList(this.entries, this.rawBody);
}

/// Reads the parent-managed channel list from a public raw GitHub URL.
///
/// [fetch] either returns a usable list or fails loudly — it never reports
/// success with nothing in it. That distinction is the safety property of the
/// whole feature: the caller reconciles the local database against this list,
/// so "no channels" would wipe every channel off the child's phone the first
/// time the Wi-Fi is down. An explicitly empty `channels` array is treated as a
/// mistake for the same reason.
class RemoteConfigService {
  final http.Client _client;

  RemoteConfigService({http.Client? client}) : _client = client ?? http.Client();

  Future<RemoteChannelList?> fetch(String url) async {
    if (url.isEmpty || url.contains('OWNER/REPO')) {
      developer.log('Remote channels URL is not configured yet: $url');
      return null;
    }

    // raw.githubusercontent.com sits behind a CDN with a ~5 minute TTL, so an
    // edit made a minute ago would not show up without a cache buster.
    final uri = Uri.parse(url).replace(queryParameters: {
      't': DateTime.now().millisecondsSinceEpoch.toString(),
    });

    try {
      final response = await _client
          .get(uri, headers: {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw RemoteConfigException('HTTP ${response.statusCode}');
      }

      final body = utf8.decode(response.bodyBytes);
      final entries = parseEntries(body);
      if (entries == null) {
        throw RemoteConfigException('файл не является корректным JSON');
      }
      if (entries.isEmpty) {
        throw RemoteConfigException('список каналов пуст');
      }

      developer.log('Remote channel list: ${entries.length} entries');
      return RemoteChannelList(entries, body);
    } catch (e) {
      developer.log('Failed to fetch remote channels: $e');
      rethrow;
    }
  }

  /// Accepts either `{"channels": [...]}` or a bare `[...]` at the root.
  /// Entries may be plain strings or objects with a `url`/`id`/`handle` field.
  static List<String>? parseEntries(String body) {
    try {
      final decoded = jsonDecode(body);

      List<dynamic>? raw;
      if (decoded is List) {
        raw = decoded;
      } else if (decoded is Map<String, dynamic>) {
        final channels = decoded['channels'];
        if (channels is List) raw = channels;
      }
      if (raw == null) return null;

      final entries = <String>[];
      for (final item in raw) {
        String? value;
        if (item is String) {
          value = item;
        } else if (item is Map) {
          value = (item['url'] ?? item['id'] ?? item['handle'])?.toString();
        }
        value = value?.trim();
        if (value == null || value.isEmpty || value.startsWith('#')) continue;
        if (!entries.contains(value)) entries.add(value);
      }
      return entries;
    } catch (e) {
      developer.log('channels.json is not valid JSON: $e');
      return null;
    }
  }

  void dispose() => _client.close();
}

/// Readable failure the parent dashboard can display verbatim, instead of a
/// stringified socket error.
class RemoteConfigException implements Exception {
  final String message;
  RemoteConfigException(this.message);
  @override
  String toString() => message;
}
