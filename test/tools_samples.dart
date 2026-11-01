// The host's tools, toolsets, approvals and skills as the Tools and Skills
// goldens and tests show them: the data of the approved mockups.

import 'package:bubblepaw_desktop/src/core/host_settings.dart';

import 'fakes.dart';

const _readOnly = {
  'list',
  'read',
  'search',
  'wait',
  'jobs',
  'web_search',
  'web_fetch',
  'agent_status',
  'history_chapters',
  'history_search',
  'history_read',
  'js',
  'question',
  'todo',
  'reload',
  'environments',
  'tool_search',
  'call_tool',
};

const _builtin = {
  'files': ['list', 'read', 'search', 'edit', 'write'],
  'commands': ['exec', 'poll', 'wait', 'cancel', 'jobs'],
  'web': ['web_search', 'web_fetch'],
  'agents': ['agent', 'agent_send', 'agent_status'],
  'history': ['history_chapters', 'history_search', 'history_read'],
  'other': [
    'js',
    'question',
    'todo',
    'reload',
    'environments',
    'tool_search',
    'call_tool',
  ],
};

const _mcp = {
  'filesystem': ['read_text_file', 'list_directory', 'search_files'],
  'github': ['list_issues', 'get_pull_request'],
};

/// Thirty tools: twenty-five built in and two MCP servers' five.
final sampleTools = [
  for (final entry in _builtin.entries)
    for (final name in entry.value)
      HostTool(
        name: name,
        category: entry.key,
        readOnly: _readOnly.contains(name),
      ),
  for (final entry in _mcp.entries)
    for (final name in entry.value)
      HostTool(
        name: 'mcp__${entry.key}__$name',
        category: 'mcp:${entry.key}',
        source: 'mcp',
        server: entry.key,
      ),
];

const _asking = {
  'edit',
  'write',
  'exec',
  'cancel',
  'agent',
  'agent_send',
  'js',
  'reload',
  'call_tool',
};

/// The config behind the Tools page: a toolset `no-web`, the main chat on
/// `all`, and an approval for every built-in tool.
Map<String, Object?> sampleToolsValues() => {
  'agent.toolset': 'all',
  'toolsets.no-web.tools': [
    'category:files',
    'category:commands',
    'category:agents',
    'category:history',
    'category:other',
    'category:mcp:filesystem',
    'category:mcp:github',
  ],
  'approvals.confirm': 'ask',
  'approvals.deny': ['web_fetch'],
  for (final entry in _builtin.entries)
    for (final name in entry.value)
      'approvals.tools.$name': _asking.contains(name) ? 'ask' : 'allow',
};

const sampleSkills = [
  HostSkill(
    name: 'release-notes',
    description: 'Draft release notes from the merged pull requests.',
    source: 'workspace',
    path:
        '/home/maya/projects/garden-api/.claude/skills/release-notes/SKILL.md',
    enabled: true,
  ),
  HostSkill(
    name: 'db-migration',
    description: 'Write and check a database migration.',
    source: 'workspace',
    path: '/home/maya/projects/garden-api/.agents/skills/db-migration/SKILL.md',
    enabled: true,
  ),
  HostSkill(
    name: 'commit-style',
    description: 'Write commit messages in the style of this team.',
    source: 'user',
    path: '/home/maya/.config/bubblepaw/skills/commit-style/SKILL.md',
    enabled: false,
  ),
];

/// A host's settings with the sample tools, toolsets, approvals and skills.
FakeHostSettings sampleToolSettings({
  bool skills = true,
  Map<String, Object?>? extra,
}) => FakeHostSettings(
  values: {...sampleToolsValues(), ...?extra},
  toolList: sampleTools,
  skillList: skills ? sampleSkills : const [],
);

/// The five servers of the approved MCP mockups: a running command server with
/// one tool off, a signed-in URL server, one that needs sign-in, one that
/// failed to start, and one turned off.
const sampleMcpServers = [
  McpServerStatus(
    name: 'filesystem',
    tools: [
      McpTool(name: 'read_text_file', enabled: true),
      McpTool(name: 'list_directory', enabled: true),
      McpTool(name: 'search_files', enabled: true),
      McpTool(name: 'edit_file', enabled: false),
    ],
  ),
  McpServerStatus(
    name: 'github',
    transport: 'http',
    auth: McpAuthState.signedIn,
    headers: ['X-Org'],
    tools: [
      McpTool(name: 'list_issues', enabled: true),
      McpTool(name: 'get_pull_request', enabled: true),
      McpTool(name: 'create_issue_comment', enabled: false),
    ],
  ),
  McpServerStatus(
    name: 'docs',
    transport: 'http',
    auth: McpAuthState.needsSignIn,
  ),
  McpServerStatus(
    name: 'garden-api',
    state: 'error',
    error: "Exited with code 1: Cannot find module './tools/garden-mcp.js'",
  ),
  McpServerStatus(
    name: 'sqlite',
    enabled: false,
    state: 'stopped',
    tools: [
      McpTool(name: 'query', enabled: true),
      McpTool(name: 'list_tables', enabled: true),
    ],
  ),
];

/// The config behind [sampleMcpServers].
Map<String, Object?> sampleMcpValues() => {
  'mcp.servers.filesystem.command': 'npx',
  'mcp.servers.filesystem.args': [
    '-y',
    '@modelcontextprotocol/server-filesystem',
    '/home/maya/projects/garden-api',
  ],
  'mcp.servers.filesystem.cwd': '/home/maya/projects/garden-api',
  'mcp.servers.filesystem.env': {'LOG_LEVEL': 'info'},
  'mcp.servers.filesystem.env_from': {'API_TOKEN': 'GARDEN_TOKEN'},
  'mcp.servers.filesystem.call_timeout_secs': 60,
  'mcp.servers.filesystem.exclude_tools': ['edit_file'],
  'mcp.servers.github.url': 'https://mcp.example.com/github',
  'mcp.servers.github.oauth': true,
  'mcp.servers.github.call_timeout_secs': 30,
  'mcp.servers.github.exclude_tools': ['create_issue_comment'],
  'mcp.servers.docs.url': 'https://mcp.example.com/docs',
  'mcp.servers.docs.oauth': true,
  'mcp.servers.docs.call_timeout_secs': 60,
  'mcp.servers.garden-api.command': 'node',
  'mcp.servers.garden-api.args': ['./tools/garden-mcp.js'],
  'mcp.servers.sqlite.command': 'uvx',
  'mcp.servers.sqlite.args': ['mcp-server-sqlite', '--db-path', './garden.db'],
  'mcp.servers.sqlite.enabled': false,
};

/// A host's settings with the sample MCP servers.
FakeHostSettings sampleMcpSettings({
  List<McpServerStatus> servers = sampleMcpServers,
  Map<String, Object?>? extra,
}) => FakeHostSettings(
  values: {...sampleMcpValues(), ...?extra},
  mcpList: servers,
);
