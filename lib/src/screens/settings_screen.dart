// Settings: the BubblePaw binary, the workspace, the data directory and extra
// host arguments.
// Shown on first run, when the binary is missing, and from the rail.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart' show AgentBackend;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../config.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.initial,
    required this.onSave,
    this.onCancel,
    this.scripted = false,
    this.firstRun = false,
    this.backend,
  });

  /// The values the fields start with.
  final AppConfig initial;

  /// Save the fields and start the host with them.
  final ValueChanged<AppConfig> onSave;

  /// Leave without saving. Null when there is nothing to go back to.
  final VoidCallback? onCancel;

  /// The scripted backend is running instead of a host.
  final bool scripted;

  /// No config has been saved yet.
  final bool firstRun;

  /// The running backend. With it, the providers section shows what the host
  /// reports; without one (first run, a failed host) there is nothing to ask.
  final AgentBackend? backend;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _binary = TextEditingController(text: widget.initial.binaryPath);
  late final _workspace = TextEditingController(
    text: widget.initial.workspaceDirectory,
  );
  late final _data = TextEditingController(text: widget.initial.dataDirectory);
  late final _arguments = TextEditingController(
    text: widget.initial.extraArguments,
  );
  String? _error;

  @override
  void dispose() {
    _binary.dispose();
    _workspace.dispose();
    _data.dispose();
    _arguments.dispose();
    super.dispose();
  }

  void _save() {
    // The recent workspaces carry over; a changed workspace joins them.
    final typed = widget.initial.copyWith(
      binaryPath: _binary.text.trim(),
      dataDirectory: _data.text.trim(),
      extraArguments: _arguments.text.trim(),
    );
    final workspace = _workspace.text.trim();
    final config = workspace.isEmpty
        ? typed.copyWith(workspaceDirectory: workspace)
        : typed.withWorkspace(workspace);
    final missing = [
      if (config.binaryPath.isEmpty) 'binary',
      if (config.workspaceDirectory.isEmpty) 'workspace',
      if (config.dataDirectory.isEmpty) 'data directory',
    ];
    if (missing.isNotEmpty) {
      setState(() => _error = 'Enter the ${missing.join(', ')} to continue.');
      return;
    }
    setState(() => _error = null);
    widget.onSave(config);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final intro = widget.firstRun
        ? 'BubblePaw is not set up yet. Set the binary to start chatting.'
        : widget.scripted
        ? 'The scripted backend is running. Saving starts the BubblePaw host '
              'instead.'
        : 'Saving restarts the host with these values.';
    return ColoredBox(
      color: theme.canvas,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SettingsHeading('Settings', primary: true),
                Text(intro, style: ts(theme.typeScale.body, theme.muted)),
                const SizedBox(height: 16),
                const SettingsHeading('BubblePaw host'),
                SettingsRow(
                  label: 'Binary',
                  description: 'Path to the bubblepaw executable.',
                  stack: true,
                  trailing: SettingsField(
                    controller: _binary,
                    mono: true,
                    autofocus: true,
                    placeholder: 'Path to bubblepaw',
                    fieldKey: const ValueKey('settings-binary'),
                    onSubmitted: (_) => _save(),
                  ),
                ),
                SettingsRow(
                  label: 'Workspace',
                  description: 'The directory the agent works in.',
                  stack: true,
                  trailing: SettingsField(
                    controller: _workspace,
                    mono: true,
                    fieldKey: const ValueKey('settings-workspace'),
                    onSubmitted: (_) => _save(),
                  ),
                ),
                SettingsRow(
                  label: 'Data directory',
                  description:
                      'Where this app’s chats are stored. Do not share it '
                      'with another BubblePaw host.',
                  stack: true,
                  trailing: SettingsField(
                    controller: _data,
                    mono: true,
                    fieldKey: const ValueKey('settings-data'),
                    onSubmitted: (_) => _save(),
                  ),
                ),
                SettingsRow(
                  label: 'Extra host arguments',
                  description:
                      'Added to the host’s command line, for example '
                      '--provider demo. Optional.',
                  stack: true,
                  trailing: SettingsField(
                    controller: _arguments,
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
                      label: 'Save and start',
                      height: 36,
                      onTap: _save,
                    ),
                    if (widget.onCancel != null) ...[
                      const SizedBox(width: 8),
                      SecondaryButton(
                        key: const ValueKey('settings-cancel'),
                        label: 'Cancel',
                        height: 36,
                        onTap: widget.onCancel,
                      ),
                    ],
                  ],
                ),
                if (widget.backend != null) ...[
                  const SizedBox(height: 24),
                  ProviderSettings(backend: widget.backend!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
