// Where the tray icon comes from. The one place that names it.

/// The tray icon as a Flutter asset. Windows draws an `.ico`; Linux a PNG.
///
/// [lightTaskbar] picks the charcoal glyph for a light taskbar; the milk
/// glyph is for a dark one.
String trayIconAsset({required bool windows, bool lightTaskbar = false}) {
  final name = lightTaskbar ? 'tray-light' : 'tray';
  return windows
      ? 'assets/icon/tray/$name.ico'
      : 'assets/icon/tray/$name-24.png';
}
