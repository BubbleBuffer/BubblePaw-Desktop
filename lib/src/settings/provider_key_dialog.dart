// "Add key for <provider>" and "Edit key for <provider>" (Core v0.13.0): one
// password field, Save key, and for a stored key Remove key. The typed value
// goes straight into `providers.key.set`; nothing here keeps it, and the
// field is emptied after a save and on every way out.

import 'dart:async';

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../core/host_settings.dart';
import 'action_widgets.dart';
import 'remote_dialogs.dart' show DialogFrame, dialogFooter;
import 'text_box.dart';

/// Opens the dialog for [provider]. Resolves with what the host reported
/// after a save or a removal, or null when the person left without one.
Future<ProviderKeyChange?> showProviderKeyDialog(
  BuildContext context, {
  required HostSettings settings,
  required String provider,
  required ProviderKeyStatus? status,
  required bool keyPresent,
  String? keyEnv,
}) => showModalPanel<ProviderKeyChange>(
  context,
  (_) => SizeClassBuilder(
    builder: (_, _) => ProviderKeyDialog(
      settings: settings,
      provider: provider,
      status: status,
      keyPresent: keyPresent,
      keyEnv: keyEnv,
    ),
  ),
  width: 460,
  height: 560,
  shrink: true,
);

class ProviderKeyDialog extends StatefulWidget {
  const ProviderKeyDialog({
    super.key,
    required this.settings,
    required this.provider,
    required this.status,
    required this.keyPresent,
    this.keyEnv,
  });

  final HostSettings settings;
  final String provider;

  /// What `providers.key.get` said; null when it could not be read.
  final ProviderKeyStatus? status;

  /// Whether the host's provider list found a key. Decides Add or Edit when
  /// [status] is unknown.
  final bool keyPresent;

  /// The provider's environment variable, if it has one.
  final String? keyEnv;

  @override
  State<ProviderKeyDialog> createState() => _ProviderKeyDialogState();
}

class _ProviderKeyDialogState extends State<ProviderKeyDialog> {
  final _key = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _isSet => widget.status?.isSet ?? widget.keyPresent;

  /// Only a stored key can be removed; an environment key is not the app's
  /// to remove.
  bool get _stored => widget.status?.source == ProviderKeySource.stored;

  bool get _fromEnvironment =>
      widget.status?.source == ProviderKeySource.environment;

  @override
  void initState() {
    super.initState();
    _key.addListener(_changed);
  }

  void _changed() => setState(() => _error = null);

  @override
  void dispose() {
    // Whatever way the dialog closed, the typed value goes with it.
    _key.removeListener(_changed);
    _key.clear();
    _key.dispose();
    super.dispose();
  }

  Future<void> _run(Future<ProviderKeyChange> Function() call) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    ProviderKeyChange? change;
    String? error;
    try {
      change = await call();
    } on HostSettingsException catch (e) {
      error = e.message;
    } on Object {
      error = 'Something went wrong. The key was not changed.';
    }
    if (!mounted) return;
    if (change != null) {
      _key.clear();
      Navigator.of(context).pop(change);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  void _save() {
    final value = _key.text.trim();
    if (value.isEmpty) return;
    unawaited(
      _run(() => widget.settings.setProviderKey(widget.provider, value)),
    );
  }

  void _remove() =>
      unawaited(_run(() => widget.settings.removeProviderKey(widget.provider)));

  void _cancel() {
    _key.clear();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final ready = _key.text.trim().isNotEmpty && !_busy;
    final env = widget.keyEnv;
    return DialogFrame(
      title: '${_isSet ? 'Edit' : 'Add'} key for ${widget.provider}',
      body: [
        if (_fromEnvironment && env != null) ...[
          Text(
            'The host now uses the key in its environment variable $env. A '
            'stored key replaces it.',
            key: const ValueKey('key-dialog-environment'),
            style: ts(theme.typeScale.uiSmall, theme.muted),
          ),
          const SizedBox(height: 12),
        ],
        LabeledField(
          label: 'API key',
          hint: 'Stored on the host that runs this provider.',
          error: _error ?? '',
          child: TextBox(
            controller: _key,
            fieldKey: const ValueKey('key-field'),
            label: 'API key',
            obscure: true,
            invalid: _error != null,
            onSubmitted: (_) => _save(),
          ),
        ),
        if (_stored) ...[
          const SizedBox(height: 4),
          Text(
            env == null
                ? 'Removing the stored key leaves this provider without a '
                      'key until you add one.'
                : 'Removing the stored key makes the host fall back to the '
                      'environment variable $env when it is set.',
            key: const ValueKey('key-remove-note'),
            style: ts(theme.typeScale.uiSmall, theme.muted),
          ),
        ],
      ],
      footer: dialogFooter(
        [
          ActionButton(
            key: const ValueKey('key-cancel'),
            label: 'Cancel',
            onTap: _cancel,
          ),
          Opacity(
            opacity: ready ? 1 : .5,
            child: ActionButton(
              key: const ValueKey('key-save'),
              label: _busy ? 'Saving…' : 'Save key',
              kind: ActionKind.primary,
              onTap: ready ? _save : () {},
            ),
          ),
        ],
        leading: _stored
            ? Align(
                alignment: Alignment.centerLeft,
                child: OutlineButton(
                  key: const ValueKey('key-remove'),
                  label: 'Remove key',
                  danger: true,
                  onTap: _busy ? null : _remove,
                ),
              )
            : null,
      ),
    );
  }
}
