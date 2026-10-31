// Tools and approvals: the toolsets (the built-in `read-only` and `all`, and
// the ones in the host config), which toolset the main chat uses, and the
// approval each tool has (Ask, Allow or Deny). Everything goes through the
// host settings: a toolset is `toolsets.<name>.tools`, the main chat's choice
// is `agent.toolset`, an approval is `approvals.tools.<tool>` or an entry of
// `approvals.deny`. Each change is written at once and the page reads the
// settings again, so it shows what the host holds.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/host_settings.dart';
import '../feedback/glyphs.dart';
import 'action_widgets.dart' show ActionButton, ActionKind;
import 'settings_widgets.dart';
import 'toolsets.dart';

const LucideGlyph _glyphChevronLeft = (
  LucideIcons.chevronLeft300,
  LucideIcons.chevronLeft,
  LucideIcons.chevronLeft500,
);
const LucideGlyph _glyphChevronRight = (
  LucideIcons.chevronRight300,
  LucideIcons.chevronRight,
  LucideIcons.chevronRight500,
);
const LucideGlyph _glyphChevronDown = (
  LucideIcons.chevronDown300,
  LucideIcons.chevronDown,
  LucideIcons.chevronDown500,
);
const LucideGlyph _glyphPlus = (
  LucideIcons.plus300,
  LucideIcons.plus,
  LucideIcons.plus500,
);

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key, required this.settings, this.onBack});

  /// The host's settings; null while the host is not running.
  final HostSettings? settings;
  final VoidCallback? onBack;

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  List<HostTool>? _tools;
  ToolsConfig _config = const ToolsConfig();
  String? _loadError;
  String? _error;
  bool _busy = false;
  bool _restart = false;
  int _ticket = 0;

  /// The toolset open in the editor; null shows the list.
  String? _editing;
  final _name = TextEditingController();
  String? _nameError;
  final _editorClosed = <String>{};
  final _approvalsOpen = <String>{};

  HostSettings? get _settings => widget.settings;

  @override
  void initState() {
    super.initState();
    _name.addListener(_nameChanged);
    _load();
  }

  @override
  void didUpdateWidget(ToolsPage old) {
    super.didUpdateWidget(old);
    if (old.settings != widget.settings) {
      _tools = null;
      _editing = null;
      _load();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  static String _describe(Object error) => switch (error) {
    HostSettingsException() => error.message,
    _ => 'Something went wrong.',
  };

  Future<void> _load() async {
    final settings = _settings;
    if (settings == null) return;
    final ticket = ++_ticket;
    try {
      final tools = await settings.tools();
      final config = ToolsConfig.parse([
        ...await settings.get('toolsets'),
        ...await settings.get('agent.toolset'),
        ...await settings.get('approvals'),
      ]);
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _tools = tools;
        _config = config;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted || ticket != _ticket) return;
      setState(() => _loadError = _describe(error));
    }
  }

  /// Runs [writes], then reads the settings again. A failure shows [failure]
  /// and the host's reason.
  Future<bool> _apply(
    String failure,
    Future<void> Function(HostSettings settings) writes,
  ) async {
    final settings = _settings;
    if (settings == null || _busy) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    var ok = true;
    try {
      await writes(settings);
    } catch (error) {
      ok = false;
      _error = '$failure ${_describe(error)}';
    }
    await _load();
    if (mounted) setState(() => _busy = false);
    return ok;
  }

  Future<void> _write(HostSettings settings, String key, Object? value) async {
    final change = await settings.set(key, value);
    if (change.applied == SettingApplied.restartRequired) _restart = true;
  }

  List<ToolCategory> get _categories => groupTools(_tools ?? const []);

  List<String> get _setNames => [
    ...builtinToolsets,
    ..._config.toolsets.keys.where((n) => !builtinToolsets.contains(n)),
  ];

  Set<String> _selected(String name) {
    final tools = _tools ?? const <HostTool>[];
    return switch (name) {
      'all' => {for (final t in tools) t.name},
      'read-only' => {
        for (final t in tools)
          if (t.readOnly) t.name,
      },
      _ => resolveEntries(_config.toolsets[name] ?? const [], tools),
    };
  }

  // ---- toolsets ----

  void _openToolset(String name) => setState(() {
    _editing = name;
    _error = null;
    _name.text = name;
    _nameError = null;
  });

  void _nameChanged() {
    final editing = _editing;
    if (editing == null || builtinToolsets.contains(editing)) return;
    final error = toolsetNameError(
      _name.text,
      others: _setNames.where((n) => n != editing),
    );
    if (error != _nameError) setState(() => _nameError = error);
  }

  Future<void> _closeEditor() async {
    await _commitName();
    if (mounted) setState(() => _editing = null);
  }

  /// Renames the open toolset to the typed name when it is valid and new.
  Future<void> _commitName() async {
    final editing = _editing;
    if (editing == null || builtinToolsets.contains(editing)) return;
    final typed = _name.text.trim();
    if (typed == editing || _nameError != null) return;
    final entries = _config.toolsets[editing] ?? const <String>[];
    final wasMain = _config.main == editing;
    final ok = await _apply('Could not rename $editing.', (s) async {
      await _write(s, 'toolsets.$typed.tools', entries);
      if (wasMain) await _write(s, 'agent.toolset', typed);
      await _write(s, 'toolsets.$editing.tools', null);
    });
    if (ok && mounted) setState(() => _editing = typed);
  }

  Future<void> _newToolset() async {
    var n = 1;
    while (_setNames.contains('toolset-$n')) {
      n++;
    }
    final name = 'toolset-$n';
    final ok = await _apply(
      'Could not create $name.',
      (s) => _write(s, 'toolsets.$name.tools', const <String>[]),
    );
    if (ok && mounted) _openToolset(name);
  }

  Future<void> _deleteToolset(String name) async {
    final sure = await showConfirm(
      context,
      title: 'Delete $name?',
      message: 'The toolset $name is removed from the list.',
      confirmLabel: 'Delete $name',
      danger: true,
    );
    if (!sure || !mounted) return;
    final ok = await _apply(
      'Could not delete $name.',
      (s) => _write(s, 'toolsets.$name.tools', null),
    );
    if (ok && mounted) setState(() => _editing = null);
  }

  Future<void> _saveSelection(String name, Set<String> selected) {
    final entries = entriesFor(
      selected: selected,
      categories: _categories,
      previous: _config.toolsets[name] ?? const [],
    );
    return _apply(
      'Could not change $name.',
      (s) => _write(s, 'toolsets.$name.tools', entries),
    );
  }

  Future<void> _toggleTool(String set, HostTool tool) {
    final selected = {..._selected(set)};
    if (!selected.remove(tool.name)) selected.add(tool.name);
    return _saveSelection(set, selected);
  }

  Future<void> _toggleCategory(String set, ToolCategory category) {
    final selected = {..._selected(set)};
    final names = {for (final t in category.tools) t.name};
    if (selected.containsAll(names)) {
      selected.removeAll(names);
    } else {
      selected.addAll(names);
    }
    return _saveSelection(set, selected);
  }

  Future<void> _chooseMain(String name) => _apply(
    'Could not change the toolset the main chat uses.',
    (s) => _write(s, 'agent.toolset', name),
  );

  // ---- approvals ----

  Future<void> _setApproval(List<HostTool> tools, String mode) {
    final deny = [..._config.deny];
    final writes = <String, Object?>{};
    for (final tool in tools) {
      final denied = deny.contains(tool.name);
      if (mode == 'deny') {
        if (!denied) deny.add(tool.name);
        continue;
      }
      if (denied) deny.remove(tool.name);
      if (tool.name.contains('.')) continue;
      final explicit = _config.perTool[tool.name];
      final effective = explicit ?? (tool.isMcp ? _config.confirm : 'allow');
      if (denied || effective != mode) {
        writes['approvals.tools.${tool.name}'] = mode;
      }
    }
    final denyChanged =
        deny.length != _config.deny.length ||
        !deny.every(_config.deny.contains);
    final what = tools.length == 1 ? toolLabel(tools.first) : 'these tools';
    return _apply('Could not change the approval for $what.', (s) async {
      if (denyChanged) {
        await _write(s, 'approvals.deny', deny.isEmpty ? null : deny);
      }
      for (final entry in writes.entries) {
        await _write(s, entry.key, entry.value);
      }
    });
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final editing = _editing;
    final Widget body;
    if (_settings == null) {
      body = Text(
        'The host is not running. Start it in Core to see its tools.',
        key: const ValueKey('tools-no-host'),
        style: ts(theme.typeScale.ui, theme.muted),
      );
    } else if (_tools == null) {
      body = _loadError == null
          ? Text('Loading tools…', style: ts(theme.typeScale.ui, theme.muted))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Could not load the tools. $_loadError',
                  key: const ValueKey('tools-load-error'),
                  style: ts(theme.typeScale.ui, theme.dangerInk),
                ),
                const SizedBox(height: 8),
                SecondaryButton(
                  key: const ValueKey('tools-retry'),
                  label: 'Try again',
                  height: 32,
                  onTap: _load,
                ),
              ],
            );
    } else if (editing != null) {
      body = _editor(editing);
    } else {
      body = _overview();
    }
    final compact = SizeClass.of(context).isCompact;
    return SettingsPage(
      title: editing == null ? 'Tools' : 'Toolset',
      onBack: editing == null ? widget.onBack : _closeEditor,
      backKey: const ValueKey('settings-page-back'),
      children: [
        if (editing != null && !compact && _tools != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16, top: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ActionButton(
                key: const ValueKey('toolset-back'),
                label: 'Tools',
                kind: ActionKind.quiet,
                glyph: _glyphChevronLeft,
                onTap: _closeEditor,
              ),
            ),
          ),
        body,
        if (_restart)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Applies after restart.',
              key: const ValueKey('tools-restart'),
              style: ts(theme.typeScale.uiSmall, theme.muted),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                key: const ValueKey('tools-error'),
                style: ts(theme.typeScale.ui, theme.dangerInk),
              ),
            ),
          ),
      ],
    );
  }

  Widget _overview() {
    final theme = context.bb;
    final categories = _categories;
    final total = _tools!.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeadingWithAction(
          title: 'Toolsets',
          action: ActionButton(
            key: const ValueKey('new-toolset'),
            label: 'New toolset',
            glyph: _glyphPlus,
            onTap: _busy ? () {} : _newToolset,
          ),
        ),
        for (final name in _setNames)
          _ToolsetRow(
            key: ValueKey('toolset-$name'),
            name: name,
            count: _selected(name).length,
            total: total,
            builtin: builtinToolsets.contains(name),
            onTap: () => _openToolset(name),
          ),
        const SettingsHeading('Main chat uses', top: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: SelectButton<String>(
            key: const ValueKey('main-toolset'),
            value: _setNames.contains(_config.main) ? _config.main : 'all',
            options: _setNames,
            labelOf: (n) => n,
            title: 'Main chat uses',
            onChanged: _busy ? null : _chooseMain,
          ),
        ),
        const SettingsHeading('Approvals', top: 24),
        if (categories.isEmpty)
          Text(
            'The host lists no tools.',
            style: ts(theme.typeScale.ui, theme.muted),
          ),
        for (final category in categories) _approvalGroup(category),
      ],
    );
  }

  Widget _approvalGroup(ToolCategory category) {
    final theme = context.bb;
    final modes = {for (final t in category.tools) _config.approvalOf(t)};
    final mixed = modes.length > 1;
    final open = _approvalsOpen.contains(category.id);
    return _Card(
      key: ValueKey('approvals-${category.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
            child: Row(
              children: [
                _Chevron(
                  open: open,
                  label: category.title,
                  idKey: ValueKey('approvals-toggle-${category.id}'),
                  onTap: () => setState(() {
                    if (!_approvalsOpen.remove(category.id)) {
                      _approvalsOpen.add(category.id);
                    }
                  }),
                ),
                Expanded(child: _CategoryName(category)),
                if (mixed)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      'Mixed',
                      style: ts(theme.typeScale.uiSmall, theme.muted),
                    ),
                  ),
                _ApprovalChoice(
                  idPrefix: 'appr-${category.id}',
                  name: category.title,
                  value: mixed ? null : modes.first,
                  onChanged: _busy
                      ? null
                      : (mode) => _setApproval(category.tools, mode),
                ),
              ],
            ),
          ),
          if (open)
            for (final tool in category.tools)
              Padding(
                padding: const EdgeInsets.fromLTRB(44, 4, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        toolLabel(tool),
                        style: ts(theme.typeScale.ui, theme.ink, mono: true),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _ApprovalChoice(
                      idPrefix: 'appr-${tool.name}',
                      name: toolLabel(tool),
                      value: _config.approvalOf(tool),
                      onChanged: _busy
                          ? null
                          : (mode) => _setApproval([tool], mode),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _editor(String name) {
    final theme = context.bb;
    final builtin = builtinToolsets.contains(name);
    final selected = _selected(name);
    final isMain = _config.main == name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Name',
          style: ts(theme.typeScale.uiSmall, theme.ink, weight: 600),
        ),
        if (builtin)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Built-in toolsets can’t be renamed or deleted.',
              style: ts(theme.typeScale.uiSmall, theme.muted),
            ),
          ),
        const SizedBox(height: 6),
        if (builtin)
          Opacity(
            opacity: .6,
            child: Text(
              name,
              key: const ValueKey('toolset-name-fixed'),
              style: ts(theme.typeScale.ui, theme.ink),
            ),
          )
        else
          SettingsField(
            controller: _name,
            fieldKey: const ValueKey('toolset-name'),
            onSubmitted: (_) => _commitName(),
          ),
        if (_nameError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _nameError!,
              key: const ValueKey('toolset-name-error'),
              style: ts(theme.typeScale.uiSmall, theme.dangerInk),
            ),
          ),
        const SettingsHeading('Tools', top: 20),
        for (final category in _categories)
          _editorCategory(name, category, selected, builtin),
        if (!builtin) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlineButton(
                  key: const ValueKey('delete-toolset'),
                  label: 'Delete toolset',
                  danger: true,
                  icon: glyphIcon(glyphTrash, size: 15, color: theme.dangerInk),
                  onTap: isMain ? null : () => _deleteToolset(name),
                ),
                if (isMain)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        'Main chat uses this toolset. Choose another one '
                        'first.',
                        style: ts(theme.typeScale.uiSmall, theme.muted),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _editorCategory(
    String set,
    ToolCategory category,
    Set<String> selected,
    bool builtin,
  ) {
    final theme = context.bb;
    final count = category.tools.where((t) => selected.contains(t.name)).length;
    final state = count == 0
        ? _CheckState.off
        : count == category.tools.length
        ? _CheckState.on
        : _CheckState.mixed;
    final open = !_editorClosed.contains(category.id);
    return _Card(
      key: ValueKey('editor-${category.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
            child: Row(
              children: [
                _Chevron(
                  open: open,
                  label: category.title,
                  idKey: ValueKey('editor-toggle-${category.id}'),
                  onTap: () => setState(() {
                    if (!_editorClosed.remove(category.id)) {
                      _editorClosed.add(category.id);
                    }
                  }),
                ),
                Expanded(
                  child: _CheckRow(
                    key: ValueKey('check-${category.id}'),
                    state: state,
                    label: _CategoryName(category),
                    semantic: category.title,
                    onTap: builtin || _busy
                        ? null
                        : () => _toggleCategory(set, category),
                  ),
                ),
                Text(
                  '$count of ${category.tools.length}',
                  style: ts(theme.typeScale.uiSmall, theme.muted, mono: true),
                ),
              ],
            ),
          ),
          if (open)
            for (final tool in category.tools)
              Padding(
                padding: const EdgeInsets.fromLTRB(44, 2, 12, 2),
                child: _CheckRow(
                  key: ValueKey('check-${tool.name}'),
                  state: selected.contains(tool.name)
                      ? _CheckState.on
                      : _CheckState.off,
                  label: Text(
                    toolLabel(tool),
                    style: ts(theme.typeScale.ui, theme.ink, mono: true),
                  ),
                  semantic: toolLabel(tool),
                  onTap: builtin || _busy ? null : () => _toggleTool(set, tool),
                ),
              ),
          if (open) const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// A section heading with an action at its right end.
class _HeadingWithAction extends StatelessWidget {
  const _HeadingWithAction({required this.title, required this.action});

  final String title;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SettingsHeading(title),
        Positioned.fill(
          child: Align(alignment: Alignment.topRight, child: action),
        ),
      ],
    );
  }
}

class _ToolsetRow extends StatelessWidget {
  const _ToolsetRow({
    super.key,
    required this.name,
    required this.count,
    required this.total,
    required this.builtin,
    required this.onTap,
  });

  final String name;
  final int count;
  final int total;
  final bool builtin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      button: true,
      label: '$name. $count of $total tools${builtin ? '. Built-in' : ''}',
      excludeSemantics: true,
      child: Hover(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: ts(theme.typeScale.ui, theme.ink, weight: 600),
                  ),
                  Text(
                    '$count of $total tools',
                    style: ts(theme.typeScale.uiSmall, theme.muted),
                  ),
                ],
              ),
            ),
            if (builtin) ...[
              const StatePill('Built-in'),
              const SizedBox(width: 8),
            ],
            glyphIcon(_glyphChevronRight, size: 18, color: theme.muted),
          ],
        ),
      ),
    );
  }
}

/// A tinted card holding one category.
class _Card extends StatelessWidget {
  const _Card({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.surface2,
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      ),
    );
  }
}

class _CategoryName extends StatelessWidget {
  const _CategoryName(this.category);

  final ToolCategory category;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          category.title,
          style: ts(theme.typeScale.ui, theme.ink, weight: 600),
        ),
        if (category.mcp)
          Text(
            'MCP',
            style: ts(theme.typeScale.uiSmall, theme.faint, mono: true),
          ),
      ],
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron({
    required this.open,
    required this.label,
    required this.idKey,
    required this.onTap,
  });

  final bool open;
  final String label;
  final Key idKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      button: true,
      expanded: open,
      label: '${open ? 'Collapse' : 'Expand'} $label',
      excludeSemantics: true,
      child: Hover(
        key: idKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        padding: const EdgeInsets.all(6),
        child: glyphIcon(
          open ? _glyphChevronDown : _glyphChevronRight,
          size: 16,
          color: theme.muted,
        ),
      ),
    );
  }
}

enum _CheckState { off, mixed, on }

/// A checkbox with a label: checked, partly checked or empty.
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    super.key,
    required this.state,
    required this.label,
    required this.semantic,
    required this.onTap,
  });

  final _CheckState state;
  final Widget label;
  final String semantic;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final filled = state != _CheckState.off;
    return Semantics(
      label: semantic,
      checked: state == _CheckState.on,
      mixed: state == _CheckState.mixed,
      enabled: onTap != null,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? .7 : 1,
        child: Hover(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: filled ? theme.accent : theme.surface,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: filled ? theme.accent : theme.threadStrong,
                  ),
                ),
                child: filled
                    ? Center(
                        child: glyphIcon(
                          state == _CheckState.on ? glyphCheck : glyphMinus,
                          size: 12,
                          color: theme.onAccent,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Flexible(child: label),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ask, Allow and Deny; none is marked when [value] is null (a mixed group).
class _ApprovalChoice extends StatelessWidget {
  const _ApprovalChoice({
    required this.idPrefix,
    required this.name,
    required this.value,
    required this.onChanged,
  });

  final String idPrefix;
  final String name;
  final String? value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Approval for $name',
      container: true,
      child: IgnorePointer(
        ignoring: onChanged == null,
        child: SegmentedChoice<String?>(
          idPrefix: idPrefix,
          options: approvalModes,
          value: value,
          labelOf: (m) => '${m![0].toUpperCase()}${m.substring(1)}',
          onChanged: (m) => onChanged?.call(m!),
        ),
      ),
    );
  }
}
