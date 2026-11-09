// MCP servers: the servers in the host config, their status, sign-in and
// tools. The list comes from `mcp.servers.list` and stays current through the
// host's `mcp.server` notifications; what a row says about a server's command
// or address comes from the config (`config.get`). A server on or off is its
// `enabled` leaf, a tool on or off is the server's `exclude_tools` (and
// `include_tools`), and Add server and Edit open the form in mcp_form.dart.

import 'dart:async';

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/host_settings.dart';
import '../platform/releases.dart';
import 'action_widgets.dart';
import 'mcp_form.dart';
import 'mcp_servers.dart';
import 'settings_widgets.dart';

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

class McpPage extends StatefulWidget {
  const McpPage({
    super.key,
    required this.settings,
    this.services = const PlatformServices(),
    this.onBack,
  });

  /// The host's settings; null while the host is not running.
  final HostSettings? settings;

  /// Opens the sign-in address in the browser.
  final PlatformServices services;
  final VoidCallback? onBack;

  @override
  State<McpPage> createState() => _McpPageState();
}

class _McpPageState extends State<McpPage> {
  List<McpServerStatus>? _servers;
  Map<String, McpServerConfig> _configs = const {};
  String? _loadError;
  String? _error;
  bool _restart = false;
  int _ticket = 0;
  StreamSubscription<McpServerStatus>? _updates;
  final _open = <String>{};
  final _busy = <String>{};

  HostSettings? get _settings => widget.settings;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _load();
  }

  @override
  void didUpdateWidget(McpPage old) {
    super.didUpdateWidget(old);
    if (old.settings != widget.settings) {
      _servers = null;
      _subscribe();
      _load();
    }
  }

  @override
  void dispose() {
    _updates?.cancel();
    super.dispose();
  }

  void _subscribe() {
    _updates?.cancel();
    _updates = _settings?.mcpUpdates().listen(
      _onStatus,
      onError: (Object _) {},
    );
  }

  void _onStatus(McpServerStatus status) {
    final servers = _servers;
    if (!mounted || servers == null) return;
    setState(() {
      final at = servers.indexWhere((s) => s.name == status.name);
      if (status.removed) {
        if (at >= 0) _servers = [...servers]..removeAt(at);
        return;
      }
      _servers = at >= 0
          ? [...servers.sublist(0, at), status, ...servers.sublist(at + 1)]
          : [...servers, status];
    });
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
      final servers = await settings.mcpServers();
      final configs = McpServerConfig.parse(await settings.get('mcp.servers'));
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _servers = [
          for (final s in servers)
            if (!s.removed) s,
        ];
        _configs = configs;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted || ticket != _ticket) return;
      setState(() => _loadError = _describe(error));
    }
  }

  /// Runs [action] for [server] and reads the servers again.
  Future<void> _run(
    String server,
    String failure,
    Future<void> Function(HostSettings settings) action,
  ) async {
    final settings = _settings;
    if (settings == null || !_busy.add(server)) return;
    setState(() => _error = null);
    try {
      await action(settings);
    } catch (error) {
      _error = '$failure ${_describe(error)}';
    }
    await _load();
    if (mounted) setState(() => _busy.remove(server));
  }

  Future<void> _setEnabled(McpServerStatus server, bool on) => _run(
    server.name,
    'Could not turn ${server.name} ${on ? 'on' : 'off'}.',
    (s) async {
      final change = await s.set('mcp.servers.${server.name}.enabled', on);
      if (change.applied == SettingApplied.restartRequired) _restart = true;
    },
  );

  Future<void> _toggleTool(McpServerStatus server, McpTool tool, bool on) =>
      _run(server.name, 'Could not turn ${tool.name} ${on ? 'on' : 'off'}.', (
        s,
      ) async {
        final config =
            _configs[server.name] ?? McpServerConfig(name: server.name);
        final result = await applyOps(
          s,
          server.name,
          planToolToggle(config, tool.name, enable: on),
        );
        if (!result.ok) throw HostSettingsException(result.message!);
        if (result.restart) _restart = true;
      });

  Future<void> _signIn(McpServerStatus server) =>
      _run(server.name, 'Could not sign in to ${server.name}.', (s) async {
        final url = await s.mcpSignIn(server.name);
        _patch(server.name, (v) => v.withAuth(McpAuthState.waiting));
        await widget.services.open(Uri.parse(url));
      });

  Future<void> _signOut(McpServerStatus server, {required bool cancel}) => _run(
    server.name,
    cancel
        ? 'Could not cancel the sign-in to ${server.name}.'
        : 'Could not sign out of ${server.name}.',
    (s) async {
      await s.mcpSignOut(server.name);
    },
  );

  void _patch(String name, McpServerStatus Function(McpServerStatus) change) {
    final servers = _servers;
    if (servers == null || !mounted) return;
    setState(() {
      _servers = [
        for (final s in servers)
          if (s.name == name) change(s) else s,
      ];
    });
  }

  Future<void> _form({McpServerStatus? server}) async {
    final settings = _settings;
    if (settings == null) return;
    final names = {
      for (final s in _servers ?? const <McpServerStatus>[]) s.name,
    };
    final config = server == null ? null : _configs[server.name];
    if (server != null && config == null) {
      setState(() => _error = 'Could not read the settings of ${server.name}.');
      return;
    }
    final result = await showServerForm(
      context,
      settings: settings,
      others: {...names}..remove(server?.name),
      config: config,
      status: server,
    );
    if (result == null || !mounted) {
      await _load();
      return;
    }
    if (result.restart) _restart = true;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final servers = _servers;
    final Widget body;
    if (widget.settings == null) {
      body = Text(
        'The host is not running. Start it in Core to see its MCP servers.',
        key: const ValueKey('mcp-no-host'),
        style: ts(theme.typeScale.ui, theme.muted),
      );
    } else if (servers == null) {
      body = _loadError == null
          ? Text('Loading servers…', style: ts(theme.typeScale.ui, theme.muted))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Could not load the servers. $_loadError',
                  key: const ValueKey('mcp-load-error'),
                  style: ts(theme.typeScale.ui, theme.dangerInk),
                ),
                const SizedBox(height: 8),
                SecondaryButton(
                  key: const ValueKey('mcp-retry'),
                  label: 'Try again',
                  height: 32,
                  onTap: _load,
                ),
              ],
            );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HeadingWithAction(
            title: 'Servers',
            action: ActionButton(
              key: const ValueKey('add-server'),
              label: 'Add server',
              glyph: _glyphPlus,
              onTap: () => _form(),
            ),
          ),
          if (servers.isEmpty)
            Text(
              'No servers yet.',
              key: const ValueKey('mcp-empty'),
              style: ts(theme.typeScale.ui, theme.muted),
            ),
          for (final server in servers)
            _ServerCard(
              key: ValueKey('server-${server.name}'),
              status: server,
              line: _configs[server.name]?.line ?? '',
              open: _open.contains(server.name),
              busy: _busy.contains(server.name),
              onOpen: () => setState(() {
                if (!_open.remove(server.name)) _open.add(server.name);
              }),
              onEdit: () => _form(server: server),
              onEnabled: (on) => _setEnabled(server, on),
              onSignIn: () => _signIn(server),
              onSignOut: () => _signOut(server, cancel: false),
              onCancel: () => _signOut(server, cancel: true),
              onTool: (tool, on) => _toggleTool(server, tool, on),
            ),
        ],
      );
    }
    return SettingsPage(
      title: 'MCP servers',
      onBack: widget.onBack,
      backKey: const ValueKey('settings-page-back'),
      children: [
        body,
        if (_restart)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Applies after restart.',
              key: const ValueKey('mcp-restart'),
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
                key: const ValueKey('mcp-error'),
                style: ts(theme.typeScale.ui, theme.dangerInk),
              ),
            ),
          ),
      ],
    );
  }
}

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

/// One server: its header row, then what is under it.
class _ServerCard extends StatelessWidget {
  const _ServerCard({
    super.key,
    required this.status,
    required this.line,
    required this.open,
    required this.busy,
    required this.onOpen,
    required this.onEdit,
    required this.onEnabled,
    required this.onSignIn,
    required this.onSignOut,
    required this.onCancel,
    required this.onTool,
  });

  final McpServerStatus status;

  /// The command or address the row shows.
  final String line;
  final bool open;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final ValueChanged<bool> onEnabled;
  final VoidCallback onSignIn;
  final VoidCallback onSignOut;
  final VoidCallback onCancel;
  final void Function(McpTool tool, bool on) onTool;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final phase = mcpPhase(status);
    final waiting =
        phase == McpPhase.needsSignIn && status.auth == McpAuthState.waiting;
    final name = status.name;
    final (String pillText, PillTone tone) = switch (phase) {
      McpPhase.running => ('Running', PillTone.good),
      McpPhase.error => ('Error', PillTone.bad),
      McpPhase.needsSignIn => ('Sign-in needed', PillTone.attention),
      McpPhase.expired => ('Sign-in expired', PillTone.attention),
      McpPhase.stopped => ('Stopped', PillTone.plain),
    };
    final signIn =
        (phase == McpPhase.needsSignIn && !waiting) || phase == McpPhase.expired
        ? ActionButton(
            key: ValueKey('sign-in-$name'),
            label: phase == McpPhase.expired ? 'Sign in again' : 'Sign in',
            kind: ActionKind.primary,
            onTap: busy ? () {} : onSignIn,
          )
        : null;
    final actions = <Widget>[
      StatePill(pillText, tone: tone),
      ?signIn,
      ActionButton(
        key: ValueKey('server-edit-$name'),
        label: 'Edit',
        kind: ActionKind.quiet,
        onTap: onEdit,
      ),
      _Switch(
        id: 'server-$name',
        label: 'Server $name',
        value: status.enabled,
        onChanged: busy ? null : onEnabled,
      ),
    ];
    final compact = SizeClass.of(context).isCompact;
    final title = Hover(
      key: ValueKey('server-open-$name'),
      onTap: onOpen,
      borderRadius: BorderRadius.circular(6),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Semantics(
        button: true,
        expanded: open,
        label: '$name. $line',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3, right: 8),
              child: glyphIcon(
                open ? _glyphChevronDown : _glyphChevronRight,
                size: 16,
                color: theme.muted,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: ts(theme.typeScale.ui, theme.ink, weight: 600),
                  ),
                  if (line.isNotEmpty)
                    Text(
                      line,
                      style: ts(
                        theme.typeScale.uiSmall,
                        theme.muted,
                        mono: true,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                const SizedBox(height: 4),
                Row(
                  children: [
                    actions.first,
                    const Spacer(),
                    ...[
                      for (final w in actions.skip(1)) ...[
                        w,
                        const SizedBox(width: 8),
                      ],
                    ]..removeLast(),
                  ],
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: title),
                const SizedBox(width: 12),
                for (final w in actions) ...[w, const SizedBox(width: 8)],
              ]..removeLast(),
            ),
    );
    final rows = <Widget>[];
    final errorText = phase == McpPhase.error
        ? status.error
        : status.auth == McpAuthState.failed
        ? status.authError ?? status.error
        : null;
    if (errorText != null && errorText.isNotEmpty) {
      rows.add(_Band(tone: _BandTone.danger, child: Text(errorText)));
    }
    if (waiting) {
      rows.add(
        _Band(
          tone: _BandTone.quiet,
          glyph: null,
          leading: const Spinner(size: 15),
          trailing: ActionButton(
            key: ValueKey('cancel-sign-in-$name'),
            label: 'Cancel',
            onTap: busy ? () {} : onCancel,
          ),
          child: const Text('Waiting for sign-in in your browser'),
        ),
      );
    }
    if (open) {
      if (phase == McpPhase.running) {
        if (status.auth == McpAuthState.signedIn) {
          rows.add(
            _Band(
              tone: _BandTone.quiet,
              glyph: glyphCheckCircle,
              trailing: ActionButton(
                key: ValueKey('sign-out-$name'),
                label: 'Sign out',
                onTap: busy ? () {} : onSignOut,
              ),
              child: const Text('Signed in'),
            ),
          );
        }
        if (status.tools.isEmpty) {
          rows.add(const _Note('The server has not listed any tools.'));
        }
        for (final tool in status.tools) {
          rows.add(
            _ToolRow(
              server: name,
              tool: tool,
              onChanged: busy ? null : (on) => onTool(tool, on),
            ),
          );
        }
      } else {
        rows.add(
          _Note(switch (phase) {
            McpPhase.error =>
              'No tools are listed while the server has an error.',
            McpPhase.needsSignIn => 'Sign in to list its tools.',
            McpPhase.expired =>
              'Tools are not available until you sign in again.',
            _ => 'Turn the server on to list its tools.',
          }),
        );
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.seam),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ColoredBox(color: theme.surface, child: header),
              for (final row in rows)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: theme.seam)),
                  ),
                  child: row,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _BandTone { danger, quiet }

/// A full-width line under a server's header: an error, the wait for a
/// sign-in, or the signed-in state.
class _Band extends StatelessWidget {
  const _Band({
    required this.tone,
    required this.child,
    this.glyph = glyphAlert,
    this.leading,
    this.trailing,
  });

  final _BandTone tone;
  final Widget child;
  final LucideGlyph? glyph;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final danger = tone == _BandTone.danger;
    final ink = danger ? theme.dangerInk : theme.ink;
    return ColoredBox(
      color: danger ? theme.danger : theme.surface2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 8)],
            if (glyph != null && leading == null) ...[
              glyphIcon(glyph!, size: 15, color: ink),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: DefaultTextStyle(
                style: ts(theme.typeScale.ui, ink),
                child: child,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return ColoredBox(
      color: theme.surface2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(text, style: ts(theme.typeScale.uiSmall, theme.muted)),
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.server,
    required this.tool,
    required this.onChanged,
  });

  final String server;
  final McpTool tool;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return ColoredBox(
      color: theme.surface2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                tool.name,
                style: ts(theme.typeScale.ui, theme.ink, mono: true),
              ),
            ),
            _Switch(
              id: 'tool-$server-${tool.name}',
              label: 'Tool ${tool.name}',
              value: tool.enabled,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

/// A switch with its On or Off word.
class _Switch extends StatelessWidget {
  const _Switch({
    required this.id,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String id;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      label: label,
      toggled: value,
      enabled: onChanged != null,
      child: Opacity(
        opacity: onChanged == null ? .5 : 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Toggle(
              key: ValueKey('toggle-$id'),
              value: value,
              onChanged: onChanged,
            ),
            SizedBox(
              width: 28,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  value ? 'On' : 'Off',
                  style: ts(theme.typeScale.uiSmall, theme.muted, weight: 600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
