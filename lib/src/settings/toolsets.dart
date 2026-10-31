// What the Tools page works from: the host's tool catalog grouped into
// categories, the toolsets and approvals read from the config, and the rules
// that turn a selection back into the entries Core saves. Pure Dart, so the
// page's tests and the rules stay apart from the widgets.

import '../core/host_settings.dart';

/// The built-in toolsets, which the host defines and nobody can change.
const builtinToolsets = ['read-only', 'all'];

/// The three approval modes the page offers.
const approvalModes = ['ask', 'allow', 'deny'];

/// A group of tools: a built-in category or one MCP server's tools.
class ToolCategory {
  const ToolCategory({
    required this.id,
    required this.title,
    required this.mcp,
    required this.tools,
  });

  /// `files`, ..., `other` or `mcp:<server>`.
  final String id;
  final String title;
  final bool mcp;
  final List<HostTool> tools;
}

const _categoryOrder = [
  'files',
  'commands',
  'web',
  'agents',
  'history',
  'other',
];

/// [tools] grouped by category: the built-in categories in their fixed order,
/// then one per MCP server in the order the host listed them.
List<ToolCategory> groupTools(List<HostTool> tools) {
  final byId = <String, List<HostTool>>{};
  for (final tool in tools) {
    byId.putIfAbsent(tool.category, () => []).add(tool);
  }
  final ids = [
    for (final id in _categoryOrder)
      if (byId.containsKey(id)) id,
    for (final id in byId.keys)
      if (!_categoryOrder.contains(id)) id,
  ];
  return [
    for (final id in ids)
      ToolCategory(
        id: id,
        title: id.startsWith('mcp:')
            ? id.substring(4)
            : '${id[0].toUpperCase()}${id.substring(1)}',
        mcp: id.startsWith('mcp:'),
        tools: byId[id]!,
      ),
  ];
}

/// The name a tool shows: an MCP tool without its `mcp__<server>__` prefix.
String toolLabel(HostTool tool) {
  final server = tool.server;
  if (tool.isMcp && server != null) {
    final prefix = 'mcp__${server}__';
    if (tool.name.startsWith(prefix) && tool.name.length > prefix.length) {
      return tool.name.substring(prefix.length);
    }
  }
  return tool.name;
}

/// The tool names a toolset's [entries] select. An entry is a tool name or
/// `category:<id>`; entries that match nothing the host publishes are ignored.
Set<String> resolveEntries(Iterable<String> entries, List<HostTool> tools) {
  final names = <String>{};
  for (final entry in entries) {
    if (entry.startsWith('category:')) {
      final id = entry.substring('category:'.length);
      names.addAll([
        for (final t in tools)
          if (t.category == id) t.name,
      ]);
    } else {
      names.add(entry);
    }
  }
  final known = {for (final t in tools) t.name};
  return names.intersection(known);
}

/// The entries that save [selected]: a category with every tool selected is
/// `category:<id>`, a partly selected one lists its tool names. Entries in
/// [previous] that match no published tool or category stay as they were, so
/// a tool that is not published now is not dropped from the config.
List<String> entriesFor({
  required Set<String> selected,
  required List<ToolCategory> categories,
  List<String> previous = const [],
}) {
  final categoryIds = {for (final c in categories) c.id};
  final toolNames = {
    for (final c in categories)
      for (final t in c.tools) t.name,
  };
  final kept = [
    for (final entry in previous)
      if (entry.startsWith('category:')
          ? !categoryIds.contains(entry.substring('category:'.length))
          : !toolNames.contains(entry))
        entry,
  ];
  final entries = <String>[];
  for (final category in categories) {
    final chosen = [
      for (final t in category.tools)
        if (selected.contains(t.name)) t.name,
    ];
    if (chosen.isEmpty) continue;
    if (chosen.length == category.tools.length) {
      entries.add('category:${category.id}');
    } else {
      entries.addAll(chosen);
    }
  }
  return [...entries, ...kept];
}

/// The toolsets, main-chat choice and approvals as `config.get` reports them.
class ToolsConfig {
  const ToolsConfig({
    this.toolsets = const {},
    this.main = 'all',
    this.perTool = const {},
    this.deny = const [],
    this.confirm = 'ask',
  });

  /// The toolsets the config defines, by name, with their entries.
  final Map<String, List<String>> toolsets;

  /// The toolset the main chat uses (`agent.toolset`).
  final String main;

  /// `approvals.tools`: the mode each tool is set to.
  final Map<String, String> perTool;

  /// `approvals.deny`: tools that are always refused.
  final List<String> deny;

  /// `approvals.confirm`: the mode for a tool that asks by default.
  final String confirm;

  /// Reads the settings of the sections `toolsets`, `agent.toolset` and
  /// `approvals`. A table may come as one entry holding a map or as one entry
  /// per leaf; both are read.
  factory ToolsConfig.parse(Iterable<HostSetting> settings) {
    final toolsets = <String, List<String>>{};
    final perTool = <String, String>{};
    var deny = <String>[];
    var main = 'all';
    var confirm = 'ask';
    List<String>? strings(Object? v) => v is List
        ? [
            for (final e in v)
              if (e is String) e,
          ]
        : null;
    for (final s in settings) {
      final key = s.key;
      final value = s.value;
      if (key == 'agent.toolset' && value is String) {
        main = value;
      } else if (key == 'approvals.confirm' && value is String) {
        confirm = value;
      } else if (key == 'approvals.deny') {
        deny = strings(value) ?? deny;
      } else if (key == 'approvals.tools' && value is Map) {
        value.forEach((k, v) {
          if (k is String && v is String) perTool[k] = v;
        });
      } else if (key.startsWith('approvals.tools.') && value is String) {
        perTool[key.substring('approvals.tools.'.length)] = value;
      } else if (key == 'toolsets' && value is Map) {
        value.forEach((k, v) {
          final list = v is Map ? strings(v['tools']) : null;
          if (k is String && list != null) toolsets[k] = list;
        });
      } else if (key.startsWith('toolsets.') && key.endsWith('.tools')) {
        final name = key.substring('toolsets.'.length, key.length - 6);
        final list = strings(value);
        if (name.isNotEmpty && !name.contains('.') && list != null) {
          toolsets[name] = list;
        }
      }
    }
    return ToolsConfig(
      toolsets: toolsets,
      main: main,
      perTool: perTool,
      deny: deny,
      confirm: approvalModes.contains(confirm) ? confirm : 'ask',
    );
  }

  /// The approval [tool] has now, or null when it is set to a mode the page
  /// does not offer (such as `auto`).
  String? approvalOf(HostTool tool) {
    if (deny.contains(tool.name)) return 'deny';
    final mode = perTool[tool.name] ?? (tool.isMcp ? confirm : 'allow');
    return approvalModes.contains(mode) ? mode : null;
  }
}

/// The name rules the editor shows an error for; null when [name] is fine.
String? toolsetNameError(String name, {required Iterable<String> others}) {
  final v = name.trim();
  if (v.isEmpty) return 'Enter a name.';
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*$').hasMatch(v)) {
    return 'Use letters, numbers, - and _ only.';
  }
  if (others.contains(v)) return 'A toolset named $v already exists.';
  return null;
}
