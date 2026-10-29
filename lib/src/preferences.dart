// The app's own preferences: theme, what happens at login and when the window
// closes, and whether the host starts with the app. Stored beside config.json
// as preferences.json. They apply at once; nothing here restarts the host.

/// How the app picks light or dark.
enum ThemeSetting {
  /// Follow the operating system.
  system,
  light,
  dark,
}

/// Which releases of the app the update check looks at.
enum UpdateChannel { stable, nightly }

class AppPrefs {
  const AppPrefs({
    this.theme = ThemeSetting.system,
    this.openAtLogin = false,
    this.startInTray = false,
    this.keepInTray = false,
    this.startHost = true,
    this.trayNoticeShown = false,
    this.updateChannel = UpdateChannel.stable,
    this.checkUpdates = true,
    this.lastUpdateCheck,
    this.skippedUpdate = '',
  });

  final ThemeSetting theme;

  /// BubblePaw starts when the person signs in to the computer.
  final bool openAtLogin;

  /// A login start hides the window. Only means something with
  /// [openAtLogin]; [effectiveStartInTray] is the combination.
  final bool startInTray;

  /// Closing the window hides it to the tray instead of quitting.
  final bool keepInTray;

  /// The host starts when the app does.
  final bool startHost;

  /// The one-time "still running in the tray" notice was dismissed.
  final bool trayNoticeShown;

  /// The releases the update check follows.
  final UpdateChannel updateChannel;

  /// Look for a new version when the app starts, at most once a day.
  final bool checkUpdates;

  /// When the last check ran (UTC); null before the first.
  final DateTime? lastUpdateCheck;

  /// A version the person chose to skip, such as `0.2.0`.
  final String skippedUpdate;

  /// Whether a login start hides the window.
  bool get effectiveStartInTray => openAtLogin && startInTray;

  AppPrefs copyWith({
    ThemeSetting? theme,
    bool? openAtLogin,
    bool? startInTray,
    bool? keepInTray,
    bool? startHost,
    bool? trayNoticeShown,
    UpdateChannel? updateChannel,
    bool? checkUpdates,
    DateTime? lastUpdateCheck,
    String? skippedUpdate,
  }) => AppPrefs(
    updateChannel: updateChannel ?? this.updateChannel,
    checkUpdates: checkUpdates ?? this.checkUpdates,
    lastUpdateCheck: lastUpdateCheck ?? this.lastUpdateCheck,
    skippedUpdate: skippedUpdate ?? this.skippedUpdate,
    theme: theme ?? this.theme,
    openAtLogin: openAtLogin ?? this.openAtLogin,
    startInTray: startInTray ?? this.startInTray,
    keepInTray: keepInTray ?? this.keepInTray,
    startHost: startHost ?? this.startHost,
    trayNoticeShown: trayNoticeShown ?? this.trayNoticeShown,
  );

  Map<String, Object?> toJson() => {
    'theme': theme.name,
    'openAtLogin': openAtLogin,
    'startInTray': startInTray,
    'keepInTray': keepInTray,
    'startHost': startHost,
    'trayNoticeShown': trayNoticeShown,
    'updateChannel': updateChannel.name,
    'checkUpdates': checkUpdates,
    if (lastUpdateCheck != null)
      'lastUpdateCheck': lastUpdateCheck!.toUtc().toIso8601String(),
    if (skippedUpdate.isNotEmpty) 'skippedUpdate': skippedUpdate,
  };

  /// Reads what it can; anything missing or of the wrong type is a default.
  static AppPrefs fromJson(Object? json) {
    if (json is! Map<String, Object?>) return const AppPrefs();
    bool flag(String key, bool fallback) {
      final value = json[key];
      return value is bool ? value : fallback;
    }

    const defaults = AppPrefs();
    return AppPrefs(
      theme: ThemeSetting.values.firstWhere(
        (t) => t.name == json['theme'],
        orElse: () => defaults.theme,
      ),
      openAtLogin: flag('openAtLogin', defaults.openAtLogin),
      startInTray: flag('startInTray', defaults.startInTray),
      keepInTray: flag('keepInTray', defaults.keepInTray),
      startHost: flag('startHost', defaults.startHost),
      trayNoticeShown: flag('trayNoticeShown', defaults.trayNoticeShown),
      updateChannel: UpdateChannel.values.firstWhere(
        (c) => c.name == json['updateChannel'],
        orElse: () => defaults.updateChannel,
      ),
      checkUpdates: flag('checkUpdates', defaults.checkUpdates),
      lastUpdateCheck: switch (json['lastUpdateCheck']) {
        final String text => DateTime.tryParse(text),
        _ => null,
      },
      skippedUpdate: switch (json['skippedUpdate']) {
        final String text => text,
        _ => '',
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppPrefs &&
      other.theme == theme &&
      other.openAtLogin == openAtLogin &&
      other.startInTray == startInTray &&
      other.keepInTray == keepInTray &&
      other.startHost == startHost &&
      other.trayNoticeShown == trayNoticeShown &&
      other.updateChannel == updateChannel &&
      other.checkUpdates == checkUpdates &&
      other.lastUpdateCheck == lastUpdateCheck &&
      other.skippedUpdate == skippedUpdate;

  @override
  int get hashCode => Object.hash(
    theme,
    openAtLogin,
    startInTray,
    keepInTray,
    startHost,
    trayNoticeShown,
    updateChannel,
    checkUpdates,
    lastUpdateCheck,
    skippedUpdate,
  );
}
