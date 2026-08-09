import 'package:flutter_test/flutter_test.dart';
import 'package:safe_tube/services/remote_config_service.dart';

void main() {
  group('channels.json parsing', () {
    test('reads the documented object form', () {
      final entries = RemoteConfigService.parseEntries('''
        {
          "version": 1,
          "channels": [
            "https://www.youtube.com/@SuperSimpleSongs",
            "@Smeshariki",
            "UCiGm_E4ZwYSHV3bcW1pnSeQ"
          ]
        }
      ''');

      expect(entries, [
        'https://www.youtube.com/@SuperSimpleSongs',
        '@Smeshariki',
        'UCiGm_E4ZwYSHV3bcW1pnSeQ',
      ]);
    });

    test('accepts a bare array at the root', () {
      expect(
        RemoteConfigService.parseEntries('["@one", "@two"]'),
        ['@one', '@two'],
      );
    });

    test('accepts objects with url/id/handle fields', () {
      final entries = RemoteConfigService.parseEntries(
          '{"channels": [{"url": "@one"}, {"id": "UC123"}, {"handle": "@two"}]}');
      expect(entries, ['@one', 'UC123', '@two']);
    });

    test('skips blanks and #comment entries, and de-duplicates', () {
      final entries = RemoteConfigService.parseEntries(
          '{"channels": ["@one", "  ", "# note", "@one", " @two "]}');
      expect(entries, ['@one', '@two']);
    });

    // The null-vs-empty distinction is the safety property of this whole
    // feature: null means "do not touch the database", while an empty list
    // would mean "the parent removed every channel".
    test('returns null for malformed JSON', () {
      expect(RemoteConfigService.parseEntries('{not json'), isNull);
    });

    test('returns null when there is no channels list', () {
      expect(RemoteConfigService.parseEntries('{"version": 1}'), isNull);
      expect(RemoteConfigService.parseEntries('"just a string"'), isNull);
    });

    test('returns an empty list, not null, for an explicitly empty file', () {
      expect(RemoteConfigService.parseEntries('{"channels": []}'), isEmpty);
    });
  });
}
