// BubblePaw on a phone: a client for hosts it is paired with. There is no
// host on the device, so no sharing, tray, window or app updates.

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'src/app.dart';
import 'src/app_licences.dart';
import 'src/config.dart';
import 'src/feedback/feedback_controller.dart';
import 'src/feedback/log_buffer.dart';
import 'src/host_controller.dart';
import 'src/platform/qr_scan_page.dart';
import 'src/remote/link_scanner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicences();
  installLogHooks();
  final support = await getApplicationSupportDirectory();
  final directory = Directory(support.path);
  linkScanner = scanQrCode;
  final controller = HostController(
    store: ConfigStore(directory),
    log: LogBuffer.instance,
    localHost: false,
  );
  unawaited(controller.init());
  final feedback = FeedbackController.inside(
    directory,
    host: controller,
    log: LogBuffer.instance,
  );
  unawaited(feedback.load());
  runApp(BubblePawApp(controller: controller, feedback: feedback));
}
