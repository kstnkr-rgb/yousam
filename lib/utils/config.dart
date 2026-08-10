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

/// Build identifier, injected by CI as `1.0.<run_number>`. Shown in the parent
/// dashboard so "which build is actually on the phone" is answerable without
/// digging through Android settings. Local builds report "dev".
const String kAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: 'dev',
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

/// How many videos to take from a channel's Atom feed.
///
/// The feed itself holds 15, but each one then costs a separate request to
/// learn its duration — a full watch-page fetch — and that is what makes a
/// first sync drag: 20 channels turned into ~300 of them.
///
/// Temporarily lowered to 2 for testing. Raise it back towards 15 once the
/// timing is understood.
const int kFeedVideoLimit = 2;
