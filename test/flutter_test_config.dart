// Loads the bundled fonts for every test, so goldens draw real text and icons.

import 'dart:async';

import 'package:agent_kit/testing.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadKitFonts('assets/fonts');
  await testMain();
}
