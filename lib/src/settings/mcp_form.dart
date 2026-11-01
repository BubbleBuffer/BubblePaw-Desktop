// The Add server and Edit dialogs of the MCP servers page: one form for both.
// Nothing is written while the owner types. Add server and Done check the
// form, then write it to the host with the calls [planAdd] and [planEdit]
// work out; a refusal shows the host's reason at the field it belongs to.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/host_settings.dart';
import 'action_widgets.dart' show ActionButton, ActionKind, glyphTrash;
import 'mcp_servers.dart';
import 'settings_widgets.dart';

const LucideGlyph _glyphPlus = (
  LucideIcons.plus300,
  LucideIcons.plus,
  LucideIcons.plus500,
);

/// How the dialog ended.
class McpFormResult {
  const McpFormResult({this.removed = false, this.restart = false});

  /// The server was removed.
  final bool removed;

  /// A change only applies after the host restarts.
  final bool restart;
}

/// Opens the dialog. [config] is the server being edited, null for a new one;
/// [others] are the names of the other servers.
Future<McpFormResult?> showServerForm(
  BuildContext context, {
  required HostSettings settings,
  required Set<String> others,
  McpServerConfig? config,
  McpServerStatus? status,
}) => showModalPanel<McpFormResult>(
  context,
  // The panel is pushed above the settings shell, so it needs its own
  // SizeClassBuilder for the form's SizeClass.of calls.
  (_) => SizeClassBuilder(
    builder: (_, _) => McpServerDialog(
      settings: settings,
      others: others,
      config: config,
      status: status,
    ),
  ),
  width: 520,
  height: 760,
);

class McpServerDialog extends StatefulWidget {
  const McpServerDialog({
    super.key,
    required this.settings,
    required this.others,
    this.config,
    this.status,
  });

  final HostSettings settings;
  final Set<String> others;
  final McpServerConfig? config;
  final McpServerStatus? status;

  @override
  State<McpServerDialog> createState() => _McpServerDialogState();
}

class _McpServerDialogState extends State<McpServerDialog> {
  late final McpServerForm _before;
  late final McpServerForm _form;
  late final bool _editing = widget.config != null;
  final _name = TextEditingController();
  final _command = TextEditingController();
  final _args = TextEditingController();
  final _cwd = TextEditingController();
  final _url = TextEditingController();
  final _timeout = TextEditingController();
  final _controllers =
      <McpEntry, (TextEditingController, TextEditingController)>{};

  bool _tried = false;
  bool _busy = false;

  /// The host's reason for a refusal, by form field.
  final _refused = <String, String>{};

  @override
  void initState() {
    super.initState();
    final config = widget.config;
    _before = config == null
        ? McpServerForm()
        : McpServerForm.from(config, widget.status);
    _form = _before.copy();
    _name.text = _form.name;
    _command.text = _form.command;
    _args.text = _form.args;
    _cwd.text = _form.cwd;
    _url.text = _form.url;
    _timeout.text = _form.timeout;
    _bind(_name, () => _form.name, (v) => _form.name = v);
    _bind(_command, () => _form.command, (v) => _form.command = v);
    _bind(_args, () => _form.args, (v) => _form.args = v);
    _bind(_cwd, () => _form.cwd, (v) => _form.cwd = v);
    _bind(_url, () => _form.url, (v) => _form.url = v);
    _bind(_timeout, () => _form.timeout, (v) => _form.timeout = v);
  }

  /// Keeps one form field in step with its controller. A listener also hears
  /// selection changes; comparing with the field tells them from an edit.
  void _bind(
    TextEditingController c,
    String Function() get,
    void Function(String) set,
  ) {
    c.addListener(() {
      if (c.text == get()) return;
      setState(() {
        set(c.text);
        _refused.clear();
      });
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _command, _args, _cwd, _url, _timeout]) {
      c.dispose();
    }
    for (final pair in _controllers.values) {
      pair.$1.dispose();
      pair.$2.dispose();
    }
    super.dispose();
  }

  (TextEditingController, TextEditingController) _pair(McpEntry entry) {
    return _controllers.putIfAbsent(entry, () {
      final name = TextEditingController(text: entry.name);
      final value = TextEditingController(text: entry.value);
      name.addListener(() {
        if (name.text == entry.name) return;
        setState(() {
          entry.name = name.text;
          if (entry.stored) {
            entry.stored = false;
            entry.value = '';
            value.text = '';
          }
          _refused.clear();
        });
      });
      value.addListener(() {
        if (value.text == entry.value) return;
        setState(() {
          entry.value = value.text;
          if (entry.stored) entry.stored = false;
          _refused.clear();
        });
      });
      return (name, value);
    });
  }

  McpFormErrors get _errors => validateServer(
    _form,
    others: widget.others,
    showRequired: _tried,
    editing: _editing,
  );

  String get _serverName => _editing ? widget.config!.name : _form.name.trim();

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _tried = true);
    if (_errors.any) return;
    final ops = _editing
        ? planEdit(
            name: _serverName,
            before: _before,
            after: _form,
            raw: widget.config!.raw,
          )
        : planAdd(_form);
    if (ops.isEmpty) {
      Navigator.of(context).pop(const McpFormResult());
      return;
    }
    setState(() {
      _busy = true;
      _refused.clear();
    });
    final result = await applyOps(widget.settings, _serverName, ops);
    if (!mounted) return;
    if (result.ok) {
      Navigator.of(context).pop(McpFormResult(restart: result.restart));
      return;
    }
    if (!_editing) {
      // A half-written new server is not left behind.
      try {
        await widget.settings.set('mcp.servers.$_serverName', null);
      } on HostSettingsException {
        // The next load shows what the host holds.
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _refused[result.field ?? 'general'] = result.message ?? 'Could not save.';
    });
  }

  Future<void> _remove() async {
    if (_busy) return;
    final name = _serverName;
    final sure = await showConfirm(
      context,
      title: 'Remove $name?',
      message:
          'The server $name and its settings are removed. Its tools are no '
          'longer available.',
      confirmLabel: 'Remove $name',
      danger: true,
    );
    if (!sure || !mounted) return;
    setState(() {
      _busy = true;
      _refused.clear();
    });
    try {
      final change = await widget.settings.set('mcp.servers.$name', null);
      if (!mounted) return;
      Navigator.of(context).pop(
        McpFormResult(
          removed: true,
          restart: change.applied == SettingApplied.restartRequired,
        ),
      );
    } on HostSettingsException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _refused['general'] = error.message;
      });
    }
  }

  void _setKind(McpKind kind) => setState(() {
    _form.kind = kind;
    _refused.clear();
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final errors = _errors;
    final title = _editing ? 'Edit ${widget.config!.name}' : 'Add server';
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      namesRoute: true,
      label: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: ts(theme.typeScale.h2, theme.ink, weight: 600),
                    ),
                  ),
                ),
                IconBtn(
                  Ico.close,
                  key: const ValueKey('srv-close'),
                  size: 32,
                  semanticLabel: 'Close',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: theme.seam)),
            ),
            child: const SizedBox(width: double.infinity),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Labeled(
                    label: 'Name',
                    error: errors.name,
                    child: _TextBox(
                      controller: _name,
                      fieldKey: const ValueKey('srv-name'),
                      placeholder: 'filesystem',
                      label: 'Name',
                      readOnly: _editing,
                      invalid: errors.name.isNotEmpty,
                    ),
                  ),
                  _Labeled(
                    label: 'Type',
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SegmentedChoice<McpKind>(
                        options: McpKind.values,
                        value: _form.kind,
                        labelOf: (k) =>
                            k == McpKind.command ? 'Command' : 'URL',
                        onChanged: _setKind,
                        idPrefix: 'srv-kind',
                      ),
                    ),
                  ),
                  if (_form.kind == McpKind.command)
                    ..._commandFields(errors)
                  else
                    ..._urlFields(errors),
                  _Labeled(
                    label: 'Request timeout',
                    hint: 'Seconds.',
                    error: errors.timeout.isNotEmpty
                        ? errors.timeout
                        : _refused['timeout'] ?? '',
                    child: _TextBox(
                      controller: _timeout,
                      fieldKey: const ValueKey('srv-timeout'),
                      placeholder: '$defaultCallTimeout',
                      label: 'Request timeout',
                      mono: true,
                      invalid: errors.timeout.isNotEmpty,
                    ),
                  ),
                  if (_refused['general'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          'Could not save. ${_refused['general']}',
                          key: const ValueKey('srv-error'),
                          style: ts(theme.typeScale.ui, theme.dangerInk),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: _footer(),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    final theme = context.bb;
    final compact = SizeClass.of(context).isCompact;
    final remove = OutlineButton(
      key: const ValueKey('srv-remove'),
      label: 'Remove server',
      danger: true,
      icon: glyphIcon(glyphTrash, size: 15, color: theme.dangerInk),
      onTap: _busy ? null : _remove,
    );
    final save = ActionButton(
      key: const ValueKey('srv-save'),
      label: _editing ? 'Done' : 'Add server',
      kind: ActionKind.primary,
      onTap: _busy ? () {} : _save,
    );
    if (_editing) {
      return Row(children: [remove, const Spacer(), save]);
    }
    final cancel = ActionButton(
      key: const ValueKey('srv-cancel'),
      label: 'Cancel',
      onTap: () => Navigator.of(context).maybePop(),
    );
    return compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [save, const SizedBox(height: 8), cancel],
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [cancel, const SizedBox(width: 8), save],
          );
  }

  List<Widget> _commandFields(McpFormErrors errors) {
    return [
      _Labeled(
        label: 'Command',
        error: errors.command.isNotEmpty
            ? errors.command
            : _refused['command'] ?? '',
        child: _TextBox(
          controller: _command,
          fieldKey: const ValueKey('srv-command'),
          placeholder: 'npx',
          label: 'Command',
          mono: true,
          invalid: errors.command.isNotEmpty,
        ),
      ),
      _Labeled(
        label: 'Arguments',
        hint: 'Separated by spaces.',
        error: _refused['args'] ?? '',
        child: _TextBox(
          controller: _args,
          fieldKey: const ValueKey('srv-args'),
          placeholder: '-y @modelcontextprotocol/server-filesystem .',
          label: 'Arguments',
          mono: true,
        ),
      ),
      _Labeled(
        label: 'Working folder',
        hint: 'Optional.',
        error: _refused['cwd'] ?? '',
        child: _TextBox(
          controller: _cwd,
          fieldKey: const ValueKey('srv-cwd'),
          placeholder: '/home/maya/projects/garden-api',
          label: 'Working folder',
          mono: true,
        ),
      ),
      _Labeled(
        label: 'Environment variables',
        hint:
            'Values are hidden. Choose From env var to read the value from a '
            'variable instead.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _form.env.length; i++)
              _EntryRow(
                key: ObjectKey(_form.env[i]),
                id: 'env-$i',
                entry: _form.env[i],
                controllers: _pair(_form.env[i]),
                error: i < errors.env.length
                    ? errors.env[i]
                    : const EntryError(),
                namePlaceholder: 'NAME',
                named: true,
                label: 'entry ${i + 1}',
                onSource: (s) => setState(() => _changeSource(_form.env[i], s)),
                onRemove: () => setState(() => _form.env.removeAt(i)),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: ActionButton(
                key: const ValueKey('env-add'),
                label: 'Add variable',
                kind: ActionKind.quiet,
                glyph: _glyphPlus,
                onTap: () => setState(() => _form.env.add(McpEntry())),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _urlFields(McpFormErrors errors) {
    final theme = context.bb;
    return [
      _Labeled(
        label: 'URL',
        error: errors.url.isNotEmpty ? errors.url : _refused['url'] ?? '',
        child: _TextBox(
          controller: _url,
          fieldKey: const ValueKey('srv-url'),
          placeholder: 'https://mcp.example.com/github',
          label: 'URL',
          mono: true,
          invalid: errors.url.isNotEmpty,
        ),
      ),
      _Labeled(
        label: 'Authentication',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedChoice<McpAuth>(
              options: McpAuth.values,
              value: _form.auth,
              labelOf: (a) => switch (a) {
                McpAuth.none => 'None',
                McpAuth.oauth => 'OAuth',
                McpAuth.token => 'Header token',
              },
              onChanged: (a) => setState(() {
                _form.auth = a;
                _refused.clear();
              }),
              idPrefix: 'srv-auth',
            ),
            if (_form.auth == McpAuth.oauth)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Sign in from the server’s row.',
                  style: ts(theme.typeScale.uiSmall, theme.muted),
                ),
              ),
          ],
        ),
      ),
      if (_form.auth == McpAuth.token)
        _Labeled(
          label: 'Token',
          hint: 'Sent in the Authorization header. Hidden.',
          error: _refused['token'] ?? '',
          child: _EntryRow(
            key: ObjectKey(_form.token),
            id: 'token',
            entry: _form.token,
            controllers: _pair(_form.token),
            error: errors.token,
            namePlaceholder: '',
            named: false,
            label: 'the token',
            onSource: (s) => setState(() => _changeSource(_form.token, s)),
          ),
        ),
      _Labeled(
        label: 'Headers',
        hint:
            'Values are hidden. Choose From env var to read the value from a '
            'variable instead.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _form.headers.length; i++)
              _EntryRow(
                key: ObjectKey(_form.headers[i]),
                id: 'hdr-$i',
                entry: _form.headers[i],
                controllers: _pair(_form.headers[i]),
                error: i < errors.headers.length
                    ? errors.headers[i]
                    : const EntryError(),
                refused: _refused['hdr:$i'],
                namePlaceholder: 'Header-Name',
                named: true,
                label: 'entry ${i + 1}',
                onSource: (s) =>
                    setState(() => _changeSource(_form.headers[i], s)),
                onRemove: () => setState(() => _form.headers.removeAt(i)),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: ActionButton(
                key: const ValueKey('hdr-add'),
                label: 'Add header',
                kind: ActionKind.quiet,
                glyph: _glyphPlus,
                onTap: () => setState(() => _form.headers.add(McpEntry())),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  void _changeSource(McpEntry entry, EntrySource source) {
    if (entry.source == source) return;
    entry.source = source;
    entry.stored = false;
    entry.value = '';
    _controllers[entry]?.$2.text = '';
    _refused.clear();
  }
}

/// A label, an optional hint, the field and its error line.
class _Labeled extends StatelessWidget {
  const _Labeled({
    required this.label,
    required this.child,
    this.hint,
    this.error = '',
  });

  final String label;
  final String? hint;
  final String error;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: ts(theme.typeScale.uiSmall, theme.ink, weight: 600),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                hint!,
                style: ts(theme.typeScale.uiSmall, theme.muted),
              ),
            ),
          const SizedBox(height: 6),
          child,
          if (error.isNotEmpty) _ErrorText(error),
        ],
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(text, style: ts(theme.typeScale.uiSmall, theme.dangerInk)),
    );
  }
}

/// One text input: a framed field that can hide its text and show an error.
class _TextBox extends StatefulWidget {
  const _TextBox({
    required this.controller,
    required this.label,
    this.fieldKey,
    this.placeholder = '',
    this.mono = false,
    this.obscure = false,
    this.invalid = false,
    this.readOnly = false,
  });

  final TextEditingController controller;
  final String label;
  final Key? fieldKey;
  final String placeholder;
  final bool mono;
  final bool obscure;
  final bool invalid;
  final bool readOnly;

  @override
  State<_TextBox> createState() => _TextBoxState();
}

class _TextBoxState extends State<_TextBox> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final style = ts(theme.typeScale.ui, theme.ink, mono: widget.mono);
    final field = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.readOnly ? null : _focus.requestFocus,
      child: FieldFrame(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Semantics(
          label: widget.label,
          textField: true,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              ListenableBuilder(
                listenable: widget.controller,
                builder: (_, _) => widget.controller.text.isEmpty
                    ? IgnorePointer(
                        child: Text(
                          widget.placeholder,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: style.copyWith(color: theme.faint),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              EditableText(
                key: widget.fieldKey,
                controller: widget.controller,
                focusNode: _focus,
                style: style,
                cursorColor: theme.ink,
                backgroundCursorColor: theme.faint,
                selectionColor: theme.accent.withValues(alpha: 0.3),
                selectionControls: noteSelectionControls,
                obscureText: widget.obscure,
                readOnly: widget.readOnly,
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
    final framed = widget.invalid
        ? DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.dangerInk),
            ),
            child: field,
          )
        : field;
    return widget.readOnly ? Opacity(opacity: .6, child: framed) : framed;
  }
}

/// One environment variable, header or token: name, value and where the
/// value comes from.
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    super.key,
    required this.id,
    required this.entry,
    required this.controllers,
    required this.error,
    required this.namePlaceholder,
    required this.named,
    required this.label,
    required this.onSource,
    this.onRemove,
    this.refused,
  });

  final String id;
  final McpEntry entry;
  final (TextEditingController, TextEditingController) controllers;
  final EntryError error;
  final String namePlaceholder;
  final bool named;
  final String label;
  final ValueChanged<EntrySource> onSource;
  final VoidCallback? onRemove;

  /// The host's reason for refusing this entry's stored value.
  final String? refused;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final compact = SizeClass.of(context).isCompact;
    final byValue = entry.source == EntrySource.value;
    final name = _stack(
      _TextBox(
        controller: controllers.$1,
        fieldKey: ValueKey('$id-name'),
        placeholder: namePlaceholder,
        label: 'Name for $label',
        mono: true,
        invalid: error.name.isNotEmpty,
      ),
      error.name,
    );
    final value = _stack(
      _TextBox(
        controller: controllers.$2,
        fieldKey: ValueKey('$id-value'),
        placeholder: entry.stored
            ? '••••••'
            : byValue
            ? 'Value, hidden'
            : 'VAR_NAME',
        label: byValue ? 'Value for $label' : 'Variable name for $label',
        mono: true,
        obscure: byValue,
        invalid: error.value.isNotEmpty || (refused ?? '').isNotEmpty,
      ),
      error.value.isNotEmpty ? error.value : refused ?? '',
    );
    final source = DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.thread),
        borderRadius: BorderRadius.circular(6),
        color: theme.surface2,
      ),
      child: SelectButton<EntrySource>(
        key: ValueKey('$id-source'),
        value: entry.source,
        options: EntrySource.values,
        labelOf: (s) => s == EntrySource.value ? 'Value' : 'From env var',
        title: 'Source of $label',
        onChanged: onSource,
      ),
    );
    final remove = onRemove == null
        ? const SizedBox.shrink()
        : IconBtn(
            Ico.close,
            key: ValueKey('$id-remove'),
            size: 32,
            semanticLabel: 'Remove $label',
            onTap: onRemove,
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: compact && named
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                name,
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: value),
                    const SizedBox(width: 8),
                    source,
                    remove,
                  ],
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (named) ...[Expanded(child: name), const SizedBox(width: 8)],
                Expanded(child: value),
                const SizedBox(width: 8),
                source,
                remove,
              ],
            ),
    );
  }

  Widget _stack(Widget field, String error) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [field, if (error.isNotEmpty) _ErrorText(error)],
  );
}
