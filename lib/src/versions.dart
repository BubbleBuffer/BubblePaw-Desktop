// The versions About shows. A test keeps them equal to pubspec.yaml.

/// The app's own version (pubspec `version`, without the build number).
const appVersion = '0.1.0';

/// The agent kit tag the app pins (the pubspec's `# v...` comment on the
/// agent_kit ref).
const kitVersion = 'v0.16.2';

/// The version this build reports to the update check. A nightly build sets
/// it with `--dart-define=BP_APP_VERSION=0.1.0-nightly.20261029+abc1234`.
const buildVersion = String.fromEnvironment(
  'BP_APP_VERSION',
  defaultValue: appVersion,
);
