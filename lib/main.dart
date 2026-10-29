import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/app_licences.dart';
import 'src/config.dart';
import 'src/feedback/feedback_controller.dart';
import 'src/feedback/log_buffer.dart';
import 'src/host_controller.dart';
import 'src/platform/desktop_adapters.dart';
import 'src/platform/desktop_integration.dart';
import 'src/platform/releases.dart';

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
  installLogHooks();
  final controller = HostController(
    store: ConfigStore(directory),
    log: LogBuffer.instance,
    scripted: scripted,
    bundledBinary: bundledBinaryPath(),
    versionReader: readHostVersion,
  );
  final feedback = FeedbackController.inside(
    directory,
    host: controller,
    log: LogBuffer.instance,
  );
  unawaited(feedback.load());
  unawaited(controller.init());
  runApp(BubblePawApp(controller: controller, feedback: feedback));
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
