/// Where the allowed-channel list lives.
///
/// The parent edits `channels.json` in the GitHub repository and the app
/// re-reads it on every launch, so channels can be added or removed without
/// rebuilding or reinstalling anything.
///
/// Override at build time without touching the source:
///   `flutter build apk --dart-define=CHANNELS_URL=https://raw.githubusercontent.com/USER/REPO/main/channels.json`
///
/// It can also be changed at runtime in the parent dashboard; that value is
/// stored in the settings table and wins over this default.
const String kDefaultRemoteChannelsUrl = String.fromEnvironment(
  'CHANNELS_URL',
  defaultValue:
      'https://raw.githubusercontent.com/OWNER/REPO/main/channels.json',
);

/// Settings keys shared between the provider and the parent dashboard.
class SettingsKeys {
  static const parentPin = 'parent_pin';
  static const channelsUrl = 'channels_url';
  static const lastSyncAt = 'remote_channels_fetched_at';
  static const lastSyncError = 'remote_channels_last_error';
  static const cachedChannels = 'remote_channels_cache';
}

/// How many uploads to pull when a channel is first added. Deep enough to feel
/// like "the whole channel" for kids' channels, shallow enough that the first
/// sync finishes in well under a minute.
const int kChannelSyncLimit = 200;

/// Safety valve for incremental re-syncs: stop scanning after this many
/// uploads even if no known video turned up.
const int kIncrementalScanLimit = 60;
