// The sections of Settings. Remote access joins with the remote work.

enum SettingsSection {
  general('General'),
  core('Core'),
  models('Models'),
  about('About');

  const SettingsSection(this.title);

  final String title;
}
