// Core: the BubblePaw host process. Its state with Restart (or Detach for a
// host that was already running), which Core it runs (downloaded, installed
// or a custom binary), where its data lives and the extra arguments it
// starts with. Binary, data directory and arguments are saved with "Save and
// restart".

import 'dart:async';

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart'
    show BubblePawBackend;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../config.dart';
import '../core/core_manager.dart';
import '../core/detect.dart';
import '../host_controller.dart';
import '../platform/download.dart';
import '../semver.dart';
import 'action_widgets.dart';
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
String coreSummary(HostController controller) => controller.attached
    ? 'Attached'
    : switch (controller.phase) {
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
  String? _customVersion;
  bool _detecting = false;

  CoreDraft get _draft => widget.draft;
  HostController get _host => widget.controller;
  CoreManager get _core => _host.core;

  @override
  void initState() {
    super.initState();
    _host.addListener(_changed);
    // After this frame: the first notifications must not land during a build.
    scheduleMicrotask(() {
      if (!mounted) return;
      if (_core.detected == null) unawaited(_detect());
      unawaited(_readCustomVersion());
      if (!_core.checked) unawaited(_core.refresh());
    });
  }

  @override
  void dispose() {
    _host.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _detect() async {
    setState(() => _detecting = true);
    await _core.detect();
    if (mounted) setState(() => _detecting = false);
  }

  Future<void> _readCustomVersion() async {
    final path = _draft.binary.text.trim();
    final version = path.isEmpty ? null : await _host.readVersion(path);
    if (mounted) setState(() => _customVersion = version);
  }

  Future<void> _save() async {
    final source = _draft.source;
    if (source == BinarySource.installed && _core.detected == null) {
      await _detect();
    }
    if (!mounted) return;
    final stored = _core.versionToRun(_host.formConfig.coreVersion);
    final typed = _host.formConfig.copyWith(
      binarySource: source,
      binaryPath: _draft.binary.text.trim(),
      dataDirectory: _draft.data.text.trim(),
      extraArguments: _draft.arguments.text.trim(),
      coreVersion: source == BinarySource.downloaded && stored != null
          ? stored.toString()
          : null,
    );
    final missing = [
      if (source == BinarySource.custom && typed.binaryPath.isEmpty) 'binary',
      if (typed.dataDirectory.isEmpty) 'data directory',
    ];
    String? error;
    if (missing.isNotEmpty) {
      error = 'Enter the ${missing.join(', ')} to continue.';
    } else if (source == BinarySource.downloaded && stored == null) {
      error = 'Download Core first, or choose Installed or Custom.';
    } else if (source == BinarySource.installed &&
        !(_core.detected?.usable ?? false)) {
      error =
          'Installed Core can’t be used until it is found and recent enough.';
    }
    setState(() => _error = error);
    if (error == null) widget.onSave(typed);
  }

  void _cancel() {
    setState(() {
      _error = null;
      _draft.reset(_host.formConfig);
    });
    unawaited(_readCustomVersion());
  }

  Future<void> _browse() async {
    final path = await widget.pickBinary();
    if (path == null || path.trim().isEmpty || !mounted) return;
    setState(() => _draft.binary.text = path.trim());
    unawaited(_readCustomVersion());
  }

  void _choose(BinarySource source) {
    setState(() => _draft.source = source);
    if (source == BinarySource.installed) unawaited(_detect());
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final source = _draft.source;
    return SettingsPage(
      title: 'Core',
      onBack: widget.onBack,
      backKey: const ValueKey('settings-page-back'),
      children: [
        _statusRow(theme),
        if (_host.attached) ..._runningHost(),
        const SettingsHeading('Binary', top: 24),
        ChoiceCard(
          key: const ValueKey('binary-downloaded'),
          title: 'Downloaded (default)',
          description:
              'BubblePaw downloads the Core release that matches this '
              'version, checks its SHA256 and stores it in its data folder.',
          selected: source == BinarySource.downloaded,
          onTap: () => _choose(BinarySource.downloaded),
        ),
        if (source == BinarySource.downloaded) _downloadedPanel(theme),
        ChoiceCard(
          key: const ValueKey('binary-installed'),
          title: 'Installed on this computer',
          description: _installedSummary(),
          selected: source == BinarySource.installed,
          onTap: () => _choose(BinarySource.installed),
        ),
        if (source == BinarySource.installed) _installedPanel(),
        ChoiceCard(
          key: const ValueKey('binary-custom'),
          title: 'Custom binary',
          description: 'Run a bubblepaw executable from a path you choose.',
          selected: source == BinarySource.custom,
          onTap: () => _choose(BinarySource.custom),
        ),
        if (source == BinarySource.custom) _customPanel(theme),
        const SettingsHeading('Background', top: 24),
        SwitchRow(
          id: 'start-host',
          label: 'Start the host when BubblePaw starts',
          description:
              'The host is the Core process. Off, BubblePaw opens with it '
              'stopped until you start it here.',
          value: _host.prefs.startHost,
          onChanged: (v) =>
              _host.updatePrefs(_host.prefs.copyWith(startHost: v)),
        ),
        const SettingsHeading('Host options', top: 24),
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
            onSubmitted: (_) => unawaited(_save()),
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
            onSubmitted: (_) => unawaited(_save()),
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
              onTap: () => unawaited(_save()),
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

  // ---- status ----

  Widget _statusRow(BbTheme theme) {
    final host = _host;
    final running = host.phase == HostPhase.running;
    final String? description = host.usingScripted
        ? 'The scripted backend is running. Saving starts the BubblePaw host '
              'instead.'
        : host.attached
        ? 'Attached to the running host'
        : running
        ? [
            if (host.hostVersion != null) 'bubblepaw ${host.hostVersion}',
            'protocol ${BubblePawBackend.protocolVersion}',
          ].join(' · ')
        : host.phase == HostPhase.failed || host.phase == HostPhase.stopped
        ? (_noCoreToStart() ? 'No Core is available to start' : null)
        : null;
    final Widget? action = host.attached
        ? ActionButton(
            key: const ValueKey('core-detach'),
            label: 'Detach',
            onTap: () => unawaited(host.detach()),
          )
        : running
        ? ActionButton(
            key: const ValueKey('core-restart'),
            label: 'Restart',
            glyph: glyphRefresh,
            onTap: () => unawaited(host.restart()),
          )
        : host.phase == HostPhase.stopped || host.phase == HostPhase.failed
        ? ActionButton(
            key: const ValueKey('core-restart'),
            label: 'Start host',
            glyph: glyphRefresh,
            onTap: () => unawaited(host.restart()),
          )
        : null;
    return SettingsRow(
      label: 'Status',
      description: description,
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
          if (action != null) ...[const SizedBox(width: 8), action],
        ],
      ),
    );
  }

  bool _noCoreToStart() {
    final config = _host.config;
    if (config == null) return false;
    return switch (config.binarySource) {
      BinarySource.downloaded => _host.coreVersionFor(config) == null,
      BinarySource.installed => !(_core.detected?.usable ?? false),
      BinarySource.custom => false,
    };
  }

  List<Widget> _runningHost() {
    final config = _host.config;
    return [
      const SettingsHeading('Running host', top: 24),
      GroupCard(
        children: [
          KeyValueRow(
            'Version',
            _host.hostVersion ?? 'Not reported',
            valueKey: const ValueKey('attached-version'),
          ),
          KeyValueRow(
            'Data directory',
            config?.dataDirectory ?? '',
            mono: true,
          ),
        ],
      ),
    ];
  }

  // ---- Downloaded ----

  Widget _downloadedPanel(BbTheme theme) {
    final state = _core.state;
    final version = _core.versionToRun(_host.formConfig.coreVersion);
    final offline = !_core.checked
        ? false
        : (_core.lookupError?.kind == FetchFailure.offline);
    final children = <Widget>[];
    if (state is CoreDownloading) {
      children.addAll([
        ProgressLine(value: state.fraction, label: 'Core download'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                megabytes(state.received, state.total),
                key: const ValueKey('core-progress'),
                style: ts(theme.typeScale.uiSmall, theme.ink),
              ),
            ),
            Text(
              state.fraction == null
                  ? ''
                  : '${(state.fraction! * 100).round()}%',
              style: ts(theme.typeScale.uiSmall, theme.muted),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ActionButton(
          key: const ValueKey('core-cancel'),
          label: 'Cancel',
          onTap: _core.cancel,
        ),
      ]);
    } else {
      if (state is CoreFailed) {
        children.addAll([
          NoticeBox(
            key: const ValueKey('core-download-error'),
            tone: NoticeTone.danger,
            child: Text(_failureText(state, version != null)),
          ),
          const SizedBox(height: 12),
          ActionButton(
            key: const ValueKey('core-retry'),
            label: 'Retry',
            kind: ActionKind.primary,
            glyph: glyphRefresh,
            onTap: () => unawaited(_host.downloadCore()),
          ),
          if (version != null) const SizedBox(height: 12),
        ]);
      } else if (version == null && offline) {
        children.addAll([
          NoticeBox(
            key: const ValueKey('core-download-error'),
            tone: NoticeTone.danger,
            child: Text(
              _failureText(
                const CoreFailed(
                  FetchFailure.offline,
                  'Core could not be downloaded because this computer is '
                  'offline.',
                ),
                false,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ActionButton(
            key: const ValueKey('core-retry'),
            label: 'Retry',
            kind: ActionKind.primary,
            glyph: glyphRefresh,
            onTap: () => unawaited(_host.downloadCore()),
          ),
        ]);
      }
      if (version != null) {
        final update = _core.updateAvailable(version);
        children.addAll([
          GroupCard(
            children: [
              KeyValueRow(
                'Version',
                update ? '$version' : '$version, up to date',
                valueKey: const ValueKey('core-version'),
              ),
              if (update)
                KeyValueRow('Update available', '${_core.latest!.version}'),
              const KeyValueRow(
                'Source',
                'BubblePaw-Core releases, SHA256 checked',
                mono: false,
              ),
              KeyValueRow('Saved to', _core.directory),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (update)
                ActionButton(
                  key: const ValueKey('core-update-button'),
                  label: 'Update',
                  kind: ActionKind.primary,
                  glyph: glyphDownload,
                  onTap: () => unawaited(_host.downloadCore()),
                ),
              ActionButton(
                key: const ValueKey('core-remove'),
                label: 'Remove',
                glyph: glyphTrash,
                onTap: () => unawaited(_host.removeCore(version)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Only versions compatible with this BubblePaw are offered.',
            style: ts(theme.typeScale.uiSmall, theme.muted),
          ),
        ]);
      } else if (state is! CoreFailed && !offline) {
        children.addAll([
          GroupCard(
            children: [
              const KeyValueRow(
                'Source',
                'BubblePaw-Core releases, SHA256 checked',
                mono: false,
              ),
              KeyValueRow('Saved to', _core.directory),
            ],
          ),
          Row(
            children: [
              ActionButton(
                key: const ValueKey('core-download'),
                label: 'Download',
                kind: ActionKind.primary,
                glyph: glyphDownload,
                onTap: () => unawaited(_host.downloadCore()),
              ),
              const SizedBox(width: 12),
              Text(
                'Not downloaded yet.',
                style: ts(theme.typeScale.uiSmall, theme.muted),
              ),
            ],
          ),
        ]);
      }
    }
    return _SubPanel(children: children);
  }

  String _failureText(CoreFailed failed, bool hasCore) {
    const choose =
        'choose Installed or Custom to use a bubblepaw you already '
        'have.';
    if (failed.offline) {
      final stored = hasCore
          ? ''
          : ' No Core is stored yet, so the host cannot start.';
      return '${failed.message}$stored Retry when you are online, or $choose';
    }
    final stopped = failed.received == null
        ? ''
        : ' It stopped at ${megabytes(failed.received!, failed.total)}.';
    return '${failed.message}$stopped Nothing was stored. Retry, or $choose';
  }

  // ---- Installed ----

  String _installedSummary() {
    final found = _core.detected;
    if (found == null) {
      return 'Looks in PATH and the standard install locations.';
    }
    return switch (found.status) {
      DetectStatus.found => 'Found ${found.path}, version ${found.version}.',
      DetectStatus.outOfRange =>
        'Found version ${found.version}. It is not supported.',
      DetectStatus.unreadable => 'Found ${found.path}. It reported no version.',
      DetectStatus.notFound => 'Not found on this computer.',
    };
  }

  Widget _installedPanel() {
    final found = _core.detected;
    final detect = ActionButton(
      key: const ValueKey('core-detect'),
      label: _detecting ? 'Checking' : 'Detect again',
      glyph: glyphRefresh,
      onTap: _detecting ? () {} : () => unawaited(_detect()),
    );
    if (found == null) return _SubPanel(children: [detect]);
    return _SubPanel(
      children: [
        switch (found.status) {
          DetectStatus.found => GroupCard(
            children: [
              KeyValueRow('Path', found.path!, trailing: detect),
              KeyValueRow('Version', '${found.version}'),
            ],
          ),
          DetectStatus.notFound => NoticeBox(
            key: const ValueKey('core-detect-notice'),
            tone: NoticeTone.danger,
            trailing: detect,
            child: Text(
              'No bubblepaw was found. BubblePaw looked in PATH'
              '${_folderList(_core.detector.standardFolders())}. Install '
              'Core, then detect again.',
            ),
          ),
          DetectStatus.outOfRange => NoticeBox(
            key: const ValueKey('core-detect-notice'),
            tone: NoticeTone.attention,
            trailing: detect,
            child: Text(
              'Version ${found.version} at ${found.path} is not supported. '
              'BubblePaw needs Core ${coreCompatibleRange.describe()}. '
              'Update it outside BubblePaw, then detect again.',
            ),
          ),
          DetectStatus.unreadable => NoticeBox(
            key: const ValueKey('core-detect-notice'),
            tone: NoticeTone.attention,
            trailing: detect,
            child: Text(
              'The bubblepaw at ${found.path} did not report a version. '
              'Check that it runs, then detect again.',
            ),
          ),
        },
      ],
    );
  }

  String _folderList(List<String> folders) => folders.isEmpty
      ? ''
      : folders.length == 1
      ? ' and ${folders.single}'
      : ', ${folders.take(folders.length - 1).join(', ')} and ${folders.last}';

  // ---- Custom ----

  Widget _customPanel(BbTheme theme) => _SubPanel(
    children: [
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
                onChanged: (_) => unawaited(_readCustomVersion()),
                onSubmitted: (_) => unawaited(_save()),
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
      if (_draft.binary.text.trim().isNotEmpty)
        Text(
          _customVersion == null
              ? 'Version not reported'
              : 'Version $_customVersion',
          key: const ValueKey('custom-version'),
          style: ts(theme.typeScale.uiSmall, theme.muted, mono: true),
        ),
    ],
  );
}

/// The block under a chosen binary option, set in from the card.
class _SubPanel extends StatelessWidget {
  const _SubPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 0, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final child in children)
          if (child is ActionButton)
            Align(alignment: Alignment.centerLeft, child: child)
          else
            child,
      ],
    ),
  );
}
