import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/config.dart';
import 'src/host_controller.dart';

/// `--scripted` runs the kit's scripted backend instead of a BubblePaw host.
/// `--config-dir DIR` keeps config.json (and the default data) in DIR.
void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  final scripted = args.contains('--scripted');
  final at = args.indexOf('--config-dir');
  final directory = at >= 0 && at + 1 < args.length
      ? Directory(args[at + 1])
      : appSupportDirectory(Platform.environment);
  final controller = HostController(
    store: ConfigStore(directory),
    scripted: scripted,
  );
  unawaited(controller.init());
  runApp(BubblePawApp(controller: controller));
}
