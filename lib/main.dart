import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitType;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/app_licences.dart';
import 'src/config.dart';
import 'src/core/core_manager.dart';
import 'src/core/detect.dart';
import 'src/host_controller.dart';
import 'src/platform/desktop_adapters.dart';
import 'src/platform/desktop_integration.dart';
import 'src/platform/download.dart';
import 'src/platform/releases.dart';
import 'src/updates/update_controller.dart';

/// `--scripted` runs the kit's scripted backend instead of a BubblePaw host.
/// `--config-dir DIR` keeps config.json (and the default data) in DIR.
/// `--hidden` starts with the window hidden in the tray (a login start with
/// "Start in the tray" on adds it).
void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicences();
  final scripted = args.contains('--scripted');
  final hidden = args.contains(hiddenFlag);
  final at = args.indexOf('--config-dir');
  final directory = at >= 0 && at + 1 < args.length
      ? Directory(args[at + 1])
      : appSupportDirectory(Platform.environment);
  const fetcher = DartHttpFetcher();
  final sep = Platform.pathSeparator;
  final platform = CorePlatform.current();
  final core = CoreManager(
    store: CoreStore(
      Directory('${directory.path}${sep}core'),
      binaryName: platform?.binaryName ?? 'bubblepaw',
    ),
    releases: GitHubCoreReleases(fetcher),
    fetcher: fetcher,
    detector: InstalledCoreDetector.system(),
  );
  final updates = UpdateController(
    fetcher: fetcher,
    downloads: Directory('${directory.path}${sep}updates'),
    installer: Platform.isWindows
        ? const WindowsUpdateInstaller()
        : const ManualUpdateInstaller(),
    platform: currentUpdatePlatform(),
    // Ends the app the way closing the last window does; the lifecycle
    // listener in the app stops the host first.
    quit: () => ServicesBinding.instance.exitApplication(AppExitType.required),
  );
  final controller = HostController(
    store: ConfigStore(directory),
    scripted: scripted,
    versionReader: readHostVersion,
    core: core,
    updates: updates,
  );
  unawaited(
    controller.init().then((_) {
      if (scripted) return;
      unawaited(core.refresh());
      unawaited(updates.checkOnStart());
    }),
  );
  runApp(BubblePawApp(controller: controller));
  unawaited(_attachDesktop(controller, hidden: hidden));
}

/// The tray, window hiding and login entry. Closing the window quits when
/// none of them can be set up.
Future<void> _attachDesktop(
  HostController controller, {
  required bool hidden,
}) async {
  try {
    final desktop = DesktopIntegration(
      host: controller,
      tray: SystemTray(),
      window: SystemWindow(),
      startup: SystemStartup(),
    );
    await desktop.init();
    // The native runner leaves the window hidden for --hidden; every other
    // start shows it by itself.
    if (hidden && !controller.trayAvailable) await desktop.showWindow();
  } on Object {
    controller.trayAvailable = false;
  }
}
