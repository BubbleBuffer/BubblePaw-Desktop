// General: theme, and what happens at login and when the window closes.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';

import 'dart:async';

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
        const SettingsHeading('Storage', top: 24),
        _DataDirectoryRow(controller: controller),
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

/// Where the chats are stored. Saved with "Save and restart": the host is
/// opened again on the new directory.
class _DataDirectoryRow extends StatefulWidget {
  const _DataDirectoryRow({required this.controller});

  final HostController controller;

  @override
  State<_DataDirectoryRow> createState() => _DataDirectoryRowState();
}

class _DataDirectoryRowState extends State<_DataDirectoryRow> {
  late final TextEditingController _text;
  String? _error;

  String get _stored => widget.controller.formConfig.dataDirectory;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: _stored)..addListener(_changed);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  bool get _dirty => _text.text.trim() != _stored;

  void _save() {
    final typed = _text.text.trim();
    if (typed.isEmpty) {
      setState(() => _error = 'Enter the data directory to continue.');
      return;
    }
    setState(() => _error = null);
    unawaited(widget.controller.setDataDirectory(typed));
  }

  void _cancel() {
    setState(() {
      _error = null;
      _text.text = _stored;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsRow(
          label: 'Data directory',
          description:
              'Where this app’s chats are stored. Do not share it with '
              'another BubblePaw host.',
          stack: true,
          trailing: SettingsField(
            controller: _text,
            mono: true,
            fieldKey: const ValueKey('settings-data'),
            onSubmitted: (_) => _save(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              key: const ValueKey('settings-error'),
              style: ts(theme.typeScale.ui, theme.dangerInk),
            ),
          ),
        ],
        if (_dirty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              PrimaryButton(
                key: const ValueKey('settings-save'),
                label: 'Save and restart',
                height: 36,
                onTap: _save,
              ),
              const SizedBox(width: 8),
              SecondaryButton(
                key: const ValueKey('settings-cancel'),
                label: 'Cancel',
                height: 36,
                onTap: _cancel,
              ),
            ],
          ),
        ],
      ],
    );
  }
}
