// The sections of Settings. MCP servers and Remote access join with their work.

enum SettingsSection {
  general('General'),
  models('Models'),
  tools('Tools'),
  skills('Skills'),
  feedback('Feedback'),
  about('About');

  const SettingsSection(this.title);

  final String title;
}
