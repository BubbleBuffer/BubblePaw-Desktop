// The sections of Settings.

enum SettingsSection {
  general('General'),
  models('Models'),
  tools('Tools'),
  mcp('MCP servers'),
  skills('Skills'),
  remote('Remote access'),
  feedback('Feedback'),
  about('About');

  const SettingsSection(this.title);

  final String title;
}
