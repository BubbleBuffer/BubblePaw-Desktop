// The sections of Settings. Remote access joins with its work.

enum SettingsSection {
  general('General'),
  models('Models'),
  tools('Tools'),
  mcp('MCP servers'),
  skills('Skills'),
  feedback('Feedback'),
  about('About');

  const SettingsSection(this.title);

  final String title;
}
