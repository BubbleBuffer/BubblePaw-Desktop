// Where the tray icon comes from. The one place that names it.

/// The tray icon as a Flutter asset. Windows draws an `.ico`; Linux a PNG.
///
/// The icon is the colour BubblePaw mark without its tile, so one set reads
/// on a light and a dark taskbar.
String trayIconAsset({required bool windows}) =>
    windows ? 'assets/icon/tray/tray.ico' : 'assets/icon/tray/tray-24.png';
