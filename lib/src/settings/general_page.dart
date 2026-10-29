// General: theme, and what happens at login and when the window closes.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../host_controller.dart';
import '../preferences.dart';
import 'settings_widgets.dart';

/// The line the section list shows under "General".
String themeSummary(ThemeSetting theme) => switch (theme) {
  ThemeSetting.system => 'System theme',
  ThemeSetting.light => 'Light theme',
  ThemeSetting.dark => 'Dark theme',
};

class GeneralPage extends StatelessWidget {
  const GeneralPage({super.key, required this.controller, this.onBack});

  final HostController controller;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final prefs = controller.prefs;
    final tray = controller.trayAvailable;
    void set(AppPrefs next) => controller.updatePrefs(next);
    return SettingsPage(
      title: 'General',
      onBack: onBack,
      backKey: const ValueKey('settings-page-back'),
      children: [
        const SettingsHeading('Appearance'),
        SettingsRow(
          label: 'Theme',
          description: 'System follows the operating system.',
          trailing: SegmentedChoice<ThemeSetting>(
            idPrefix: 'theme',
            options: ThemeSetting.values,
            value: prefs.theme,
            labelOf: (t) => switch (t) {
              ThemeSetting.system => 'System',
              ThemeSetting.light => 'Light',
              ThemeSetting.dark => 'Dark',
            },
            onChanged: (t) => set(prefs.copyWith(theme: t)),
          ),
        ),
        const SettingsHeading('Startup', top: 24),
        SwitchRow(
          id: 'open-at-login',
          label: 'Open at login',
          description: 'BubblePaw starts with this computer.',
          value: prefs.openAtLogin,
          onChanged: (v) => set(prefs.copyWith(openAtLogin: v)),
        ),
        SwitchRow(
          id: 'start-in-tray',
          label: 'Start in the tray',
          description: prefs.openAtLogin
              ? 'The window stays hidden when BubblePaw starts at login.'
              : 'Needs Open at login.',
          value: prefs.effectiveStartInTray,
          enabled: prefs.openAtLogin && tray,
          onChanged: (v) => set(prefs.copyWith(startInTray: v)),
        ),
        SwitchRow(
          id: 'keep-in-tray',
          label: 'Keep running in the tray when the window is closed',
          description: tray
              ? 'Closing the window hides it to the tray. Quit from the tray '
                    'menu.'
              : 'This system shows no tray icon, so closing the window quits.',
          value: prefs.keepInTray && tray,
          enabled: tray,
          onChanged: (v) => set(prefs.copyWith(keepInTray: v)),
        ),
        if (controller.startupFailed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                'The login entry could not be changed. BubblePaw will not '
                'start at login until it can.',
                key: const ValueKey('startup-error'),
                style: ts(theme.typeScale.ui, theme.dangerInk),
              ),
            ),
          ),
      ],
    );
  }
}
