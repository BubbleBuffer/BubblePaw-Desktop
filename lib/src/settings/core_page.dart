// Core: the BubblePaw host process. Its state with Restart, which binary it
// runs, where its data lives and the extra arguments it starts with.
// Binary, data directory and arguments are saved with "Save and restart".

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart'
    show BubblePawBackend;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../config.dart';
import '../host_controller.dart';
import 'settings_widgets.dart';

/// What the Core form holds before it is saved. The shell owns it, so the
/// text survives switching to another section and back.
class CoreDraft {
  CoreDraft(AppConfig initial)
    : source = initial.binarySource,
      binary = TextEditingController(text: initial.binaryPath),
      data = TextEditingController(text: initial.dataDirectory),
      arguments = TextEditingController(text: initial.extraArguments);

  BinarySource source;
  final TextEditingController binary;
  final TextEditingController data;
  final TextEditingController arguments;

  void reset(AppConfig saved) {
    source = saved.binarySource;
    binary.text = saved.binaryPath;
    data.text = saved.dataDirectory;
    arguments.text = saved.extraArguments;
  }

  void dispose() {
    binary.dispose();
    data.dispose();
    arguments.dispose();
  }
}

/// The line the section list shows under "Core".
String coreSummary(HostController controller) => switch (controller.phase) {
  HostPhase.running => 'Running',
  HostPhase.starting => 'Starting',
  HostPhase.stopped => 'Not started',
  HostPhase.failed => 'Stopped',
  HostPhase.setup => 'Not set up',
};

class CorePage extends StatefulWidget {
  const CorePage({
    super.key,
    required this.controller,
    required this.draft,
    required this.onSave,
    required this.pickBinary,
    this.firstRun = false,
    this.onBack,
  });

  final HostController controller;
  final CoreDraft draft;

  /// Save the form and start the host with it.
  final ValueChanged<AppConfig> onSave;

  /// Asks for a file (the native picker).
  final Future<String?> Function() pickBinary;

  /// No config has been saved yet.
  final bool firstRun;
  final VoidCallback? onBack;

  @override
  State<CorePage> createState() => _CorePageState();
}

class _CorePageState extends State<CorePage> {
  String? _error;

  CoreDraft get _draft => widget.draft;
  HostController get _host => widget.controller;

  void _save() {
    final typed = _host.formConfig.copyWith(
      binarySource: _draft.source,
      binaryPath: _draft.binary.text.trim(),
      dataDirectory: _draft.data.text.trim(),
      extraArguments: _draft.arguments.text.trim(),
    );
    final missing = [
      if (typed.binarySource == BinarySource.custom && typed.binaryPath.isEmpty)
        'binary',
      if (typed.binarySource == BinarySource.bundled && !_host.bundledAvailable)
        'binary',
      if (typed.dataDirectory.isEmpty) 'data directory',
    ];
    if (missing.isNotEmpty) {
      setState(() => _error = 'Enter the ${missing.join(', ')} to continue.');
      return;
    }
    setState(() => _error = null);
    widget.onSave(typed);
  }

  void _cancel() {
    setState(() {
      _error = null;
      _draft.reset(_host.formConfig);
    });
  }

  Future<void> _browse() async {
    final path = await widget.pickBinary();
    if (path == null || path.trim().isEmpty || !mounted) return;
    setState(() => _draft.binary.text = path.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final host = _host;
    final bundled = _draft.source == BinarySource.bundled;
    final running = host.phase == HostPhase.running;
    final saved = host.config?.binarySource == BinarySource.bundled;
    final version = host.hostVersion;
    return SettingsPage(
      title: 'Core',
      onBack: widget.onBack,
      backKey: const ValueKey('settings-page-back'),
      children: [
        const SettingsHeading('Core'),
        SettingsRow(
          label: 'Status',
          description: host.usingScripted
              ? 'The scripted backend is running. Saving starts the '
                    'BubblePaw host instead.'
              : running
              ? [
                  if (version != null) 'bubblepaw $version',
                  'protocol ${BubblePawBackend.protocolVersion}',
                ].join(' · ')
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatePill(
                coreSummary(host),
                key: const ValueKey('core-status'),
                tone: switch (host.phase) {
                  HostPhase.running => PillTone.good,
                  HostPhase.failed => PillTone.bad,
                  _ => PillTone.plain,
                },
              ),
              const SizedBox(width: 8),
              OutlineButton(
                key: const ValueKey('core-restart'),
                label: host.phase == HostPhase.running ? 'Restart' : 'Start',
                icon: Icon20(Ico.turnInto, size: 16, color: theme.ink),
                onTap:
                    host.phase == HostPhase.setup ||
                        host.phase == HostPhase.starting
                    ? null
                    : () => host.restart(),
              ),
            ],
          ),
        ),
        const SettingsHeading('Binary', top: 24),
        ChoiceCard(
          key: const ValueKey('binary-bundled'),
          title: 'Bundled with BubblePaw',
          description: !host.bundledAvailable
              ? 'Not available: there is no bubblepaw executable next to '
                    'the app.'
              : saved && version != null && running
              ? 'Version $version. It updates with the app.'
              : 'It updates with the app.',
          selected: bundled,
          available: host.bundledAvailable,
          onTap: () => setState(() => _draft.source = BinarySource.bundled),
        ),
        ChoiceCard(
          key: const ValueKey('binary-custom'),
          title: 'Custom binary',
          description: 'Run a bubblepaw executable you installed yourself.',
          selected: !bundled,
          onTap: () => setState(() => _draft.source = BinarySource.custom),
        ),
        if (!bundled)
          SettingsRow(
            label: 'Binary path',
            description: 'Path to the bubblepaw executable.',
            stack: true,
            trailing: Row(
              children: [
                Expanded(
                  child: SettingsField(
                    controller: _draft.binary,
                    mono: true,
                    autofocus: widget.firstRun,
                    placeholder: 'Path to bubblepaw',
                    fieldKey: const ValueKey('settings-binary'),
                    onSubmitted: (_) => _save(),
                  ),
                ),
                const SizedBox(width: 8),
                OutlineButton(
                  key: const ValueKey('settings-browse'),
                  label: 'Browse',
                  onTap: _browse,
                ),
              ],
            ),
          ),
        const SettingsHeading('Background', top: 24),
        SwitchRow(
          id: 'start-host',
          label: 'Start the host when BubblePaw starts',
          description:
              'The host is the Core process. Off, BubblePaw opens with it '
              'stopped until you start it here.',
          value: host.prefs.startHost,
          onChanged: (v) =>
              host.updatePrefs(host.prefs.copyWith(startHost: v)),
        ),
        const SettingsHeading('Settings', top: 24),
        SettingsRow(
          label: 'Data directory',
          description:
              'Where this app’s chats are stored. Do not share it with '
              'another BubblePaw host.',
          stack: true,
          trailing: SettingsField(
            controller: _draft.data,
            mono: true,
            fieldKey: const ValueKey('settings-data'),
            onSubmitted: (_) => _save(),
          ),
        ),
        SettingsRow(
          label: 'Extra arguments',
          description:
              'Added to the host’s command line, for example --provider '
              'demo. Optional.',
          stack: true,
          trailing: SettingsField(
            controller: _draft.arguments,
            mono: true,
            placeholder: 'None',
            fieldKey: const ValueKey('settings-arguments'),
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
        const SizedBox(height: 16),
        Row(
          children: [
            PrimaryButton(
              key: const ValueKey('settings-save'),
              label: widget.firstRun ? 'Save and start' : 'Save and restart',
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
    );
  }
}
