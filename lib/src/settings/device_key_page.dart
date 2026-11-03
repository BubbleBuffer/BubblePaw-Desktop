// Remote access > Device key: this device's identity, the key file to export
// or import, and regenerating it. The dialogs here ask for the passphrase and
// say what the change breaks before it happens.

import 'dart:async';

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../platform/releases.dart';
import '../remote/remote_access.dart';
import '../remote/remote_controller.dart';
import 'action_widgets.dart';
import 'remote_dialogs.dart';
import 'remote_glyphs.dart';
import 'settings_widgets.dart';
import 'text_box.dart';

class DeviceKeyPage extends StatelessWidget {
  const DeviceKeyPage({
    super.key,
    required this.remote,
    required this.services,
    required this.onBack,
    this.hostCount = 0,
  });

  final RemoteController remote;
  final PlatformServices services;

  /// How many hosts this device can open; they stop recognising it when the
  /// key changes.
  final int hostCount;

  /// Back to Remote access.
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final key = remote.key;
    final compact = SizeClass.of(context).isCompact;
    return SettingsPage(
      title: 'Device key',
      onBack: onBack,
      backKey: const ValueKey('settings-page-back'),
      children: [
        if (!compact)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ActionButton(
                key: const ValueKey('key-back'),
                label: 'Remote access',
                kind: ActionKind.quiet,
                glyph: glyphChevronLeft,
                onTap: onBack,
              ),
            ),
          ),
        const SettingsHeading('Current key'),
        GroupCard(
          children: [
            KeyValueRow(
              'Device ID',
              key?.id ?? '',
              valueKey: const ValueKey('key-id'),
              trailing: ActionButton(
                key: const ValueKey('key-copy'),
                label: 'Copy',
                kind: ActionKind.quiet,
                glyph: glyphCopy,
                onTap: () => unawaited(services.copy(key?.id ?? '')),
              ),
            ),
            KeyValueRow(
              'Fingerprint',
              _spaced(key?.fingerprint ?? ''),
              valueKey: const ValueKey('key-fingerprint'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const SettingsHeading('Key file', top: 12),
        SettingsRow(
          label: 'Export key file',
          description:
              'Saves a .bpkey file locked with a passphrase you choose. The '
              'same key works in other BubbleBuffer apps.',
          trailing: ActionButton(
            key: const ValueKey('key-export'),
            label: 'Export…',
            glyph: glyphDownload,
            onTap: () => unawaited(
              showModalPanel<void>(
                context,
                (_) => SizeClassBuilder(
                  builder: (_, _) =>
                      _ExportDialog(remote: remote, services: services),
                ),
                width: 460,
                height: 560,
                shrink: true,
              ),
            ),
          ),
        ),
        SettingsRow(
          label: 'Import key file',
          description:
              "Replaces this device's key. Existing pairings stop working.",
          trailing: ActionButton(
            key: const ValueKey('key-import'),
            label: 'Import…',
            glyph: glyphFolderOpen,
            onTap: () => unawaited(
              showModalPanel<void>(
                context,
                (_) => SizeClassBuilder(
                  builder: (_, _) => _ImportDialog(
                    remote: remote,
                    services: services,
                    hostCount: hostCount,
                  ),
                ),
                width: 460,
                height: 640,
                shrink: true,
              ),
            ),
          ),
        ),
        const SettingsHeading('Regenerate', top: 12),
        NoticeBox(
          key: const ValueKey('key-regen-warning'),
          tone: NoticeTone.danger,
          child: Text(_consequence(remote.devices.length, hostCount)),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlineButton(
            key: const ValueKey('key-regenerate'),
            label: 'Regenerate device key…',
            danger: true,
            icon: glyphIcon(glyphTrash, size: 15, color: theme.dangerInk),
            onTap: () => unawaited(
              showModalPanel<void>(
                context,
                (_) => SizeClassBuilder(
                  builder: (_, _) =>
                      _RegenerateDialog(remote: remote, hostCount: hostCount),
                ),
                width: 460,
                height: 520,
                shrink: true,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Groups of four, as the fingerprint is easier to compare.
String _spaced(String hex) => [
  for (var i = 0; i < hex.length; i += 4)
    hex.substring(i, i + 4 > hex.length ? hex.length : i + 4),
].join(' ');

String _consequence(int devices, int hosts) {
  if (devices + hosts == 0) {
    return 'Regenerating creates a new device ID. This device has no '
        'pairings yet, so nothing else breaks.';
  }
  return 'Regenerating creates a new device ID. All '
      '${_counted(devices, 'paired device', 'paired devices')} and '
      '${_counted(hosts, 'host you can open', 'hosts you can open')} stop '
      'recognising this device, and each pairing has to be done again.';
}

String _counted(int n, String one, String many) => '$n ${n == 1 ? one : many}';

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.remote, required this.services});

  final RemoteController remote;
  final PlatformServices services;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  bool _busy = false;
  String? _savedAs;
  String? _error;

  @override
  void initState() {
    super.initState();
    _first.addListener(_changed);
    _second.addListener(_changed);
  }

  void _changed() => setState(() => _error = null);

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  bool get _short => _first.text.isNotEmpty && _first.text.length < 8;
  bool get _differs => _second.text.isNotEmpty && _first.text != _second.text;
  bool get _ready => _first.text.length >= 8 && _first.text == _second.text;

  Future<void> _save() async {
    final id = widget.remote.key?.id ?? 'key';
    final name = 'bubblepaw-${id.length >= 9 ? id.substring(0, 9) : id}.bpkey';
    final path = await widget.services.saveKeyFile(name);
    if (path == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.remote.exportKey(path, _first.text);
      if (mounted) setState(() => _savedAs = path);
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Could not save the key file. Choose a file name that does '
              'not exist yet.',
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final saved = _savedAs;
    if (saved != null) {
      return DialogFrame(
        title: 'Key file saved',
        body: [
          NoticeBox(
            key: const ValueKey('export-saved'),
            tone: NoticeTone.good,
            child: Text('Saved ${saved.split(RegExp(r'[\\/]')).last}.'),
          ),
          const SizedBox(height: 12),
          Text(
            'The file cannot be opened without its passphrase, and the '
            'passphrase cannot be recovered.',
            style: ts(theme.typeScale.uiSmall, theme.muted),
          ),
        ],
        footer: dialogFooter([
          ActionButton(
            key: const ValueKey('export-done'),
            label: 'Done',
            kind: ActionKind.primary,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ]),
      );
    }
    return DialogFrame(
      title: 'Export key file',
      body: [
        Text(
          "The file holds this device's key. Anyone with the file and "
          'passphrase can act as this device.',
          style: ts(theme.typeScale.ui, theme.ink),
        ),
        const SizedBox(height: 12),
        LabeledField(
          label: 'Passphrase',
          hint: 'At least 8 characters.',
          error: _short ? 'Use at least 8 characters.' : '',
          child: TextBox(
            controller: _first,
            fieldKey: const ValueKey('export-pass1'),
            label: 'Passphrase',
            obscure: true,
            invalid: _short,
          ),
        ),
        LabeledField(
          label: 'Repeat the passphrase',
          error: _differs ? 'The passphrases differ.' : '',
          child: TextBox(
            controller: _second,
            fieldKey: const ValueKey('export-pass2'),
            label: 'Repeat the passphrase',
            obscure: true,
            invalid: _differs,
          ),
        ),
        if (_error != null)
          Text(
            _error!,
            key: const ValueKey('export-error'),
            style: ts(theme.typeScale.ui, theme.dangerInk),
          ),
      ],
      footer: dialogFooter([
        ActionButton(
          label: 'Cancel',
          onTap: () => Navigator.of(context).maybePop(),
        ),
        Opacity(
          opacity: _ready ? 1 : .5,
          child: ActionButton(
            key: const ValueKey('export-save'),
            label: 'Save key file',
            kind: ActionKind.primary,
            glyph: glyphDownload,
            onTap: _ready && !_busy ? () => unawaited(_save()) : () {},
          ),
        ),
      ]),
    );
  }
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({
    required this.remote,
    required this.services,
    required this.hostCount,
  });

  final RemoteController remote;
  final int hostCount;
  final PlatformServices services;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _pass = TextEditingController();
  String? _file;
  bool _busy = false;
  KeyChange? _done;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pass.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    final path = await widget.services.pickKeyFile();
    if (path != null && mounted) setState(() => _file = path);
  }

  Future<void> _import() async {
    final file = _file;
    if (file == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final change = await widget.remote.importKey(file, _pass.text);
      if (mounted) setState(() => _done = change);
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'The key was not imported. Check the passphrase and the '
              'file. Nothing changed.',
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final done = _done;
    if (done != null) {
      return DialogFrame(
        title: 'Key imported',
        body: [
          NoticeBox(
            key: const ValueKey('import-done'),
            tone: NoticeTone.good,
            child: Text(
              done.clearedDevices + done.clearedHosts == 0 &&
                      done.oldId == done.id
                  ? 'This device already had this key. Nothing changed.'
                  : 'This device is now ${done.id}. All pairings were cleared.',
            ),
          ),
        ],
        footer: dialogFooter([
          ActionButton(
            key: const ValueKey('import-close'),
            label: 'Done',
            kind: ActionKind.primary,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ]),
      );
    }
    final count = widget.remote.devices.length;
    final ready = _file != null && _pass.text.isNotEmpty;
    return DialogFrame(
      title: 'Import key file',
      body: [
        NoticeBox(
          tone: NoticeTone.danger,
          child: Text(
            'Importing replaces this device\'s key. All '
            '${_counted(count, 'paired device', 'paired devices')} and '
            '${_counted(widget.hostCount, 'host', 'hosts')} stop '
            'recognising it and are cleared.',
          ),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Key file',
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _file ?? 'No file chosen',
                  key: const ValueKey('import-file'),
                  overflow: TextOverflow.ellipsis,
                  style: ts(theme.typeScale.uiSmall, theme.ink, mono: true),
                ),
              ),
              const SizedBox(width: 8),
              ActionButton(
                key: const ValueKey('import-choose'),
                label: 'Choose file…',
                glyph: glyphFolderOpen,
                onTap: () => unawaited(_choose()),
              ),
            ],
          ),
        ),
        LabeledField(
          label: 'Passphrase',
          error: _error ?? '',
          child: TextBox(
            controller: _pass,
            fieldKey: const ValueKey('import-pass'),
            label: 'Passphrase',
            obscure: true,
            invalid: _error != null,
          ),
        ),
      ],
      footer: dialogFooter([
        ActionButton(
          label: 'Cancel',
          onTap: () => Navigator.of(context).maybePop(),
        ),
        Opacity(
          opacity: ready ? 1 : .5,
          child: OutlineButton(
            key: const ValueKey('import-key'),
            label: 'Import key',
            danger: true,
            onTap: ready && !_busy ? () => unawaited(_import()) : null,
          ),
        ),
      ]),
    );
  }
}

class _RegenerateDialog extends StatefulWidget {
  const _RegenerateDialog({required this.remote, required this.hostCount});

  final RemoteController remote;
  final int hostCount;

  @override
  State<_RegenerateDialog> createState() => _RegenerateDialogState();
}

class _RegenerateDialogState extends State<_RegenerateDialog> {
  bool _busy = false;
  KeyChange? _done;
  String? _error;

  Future<void> _regenerate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final change = await widget.remote.regenerateKey();
      if (mounted) setState(() => _done = change);
    } on Object {
      if (mounted) {
        setState(() => _error = 'The key was not changed. Try again.');
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final done = _done;
    if (done != null) {
      return DialogFrame(
        title: 'Key regenerated',
        body: [
          NoticeBox(
            key: const ValueKey('regen-done'),
            tone: NoticeTone.good,
            child: Text(
              'This device is now ${done.id}. All pairings were cleared.',
            ),
          ),
        ],
        footer: dialogFooter([
          ActionButton(
            key: const ValueKey('regen-close'),
            label: 'Done',
            kind: ActionKind.primary,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ]),
      );
    }
    return DialogFrame(
      title: 'Regenerate device key?',
      body: [
        NoticeBox(
          tone: NoticeTone.danger,
          child: Text(
            _consequence(widget.remote.devices.length, widget.hostCount),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'This cannot be undone. Export the current key file first if you '
          'may want it back.',
          style: ts(theme.typeScale.ui, theme.ink),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            key: const ValueKey('regen-error'),
            style: ts(theme.typeScale.ui, theme.dangerInk),
          ),
        ],
      ],
      footer: dialogFooter([
        ActionButton(
          label: 'Cancel',
          onTap: () => Navigator.of(context).maybePop(),
        ),
        OutlineButton(
          key: const ValueKey('regen-confirm'),
          label: 'Regenerate and clear pairings',
          danger: true,
          icon: glyphIcon(glyphTrash, size: 15, color: theme.dangerInk),
          onTap: _busy ? null : () => unawaited(_regenerate()),
        ),
      ]),
    );
  }
}
