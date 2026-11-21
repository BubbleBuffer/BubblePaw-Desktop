// The main screen and every settings page at widths from a phone to a wide
// window, at larger system text sizes and, at phone widths, at touch density
// too, with no overflow and no layout error. Fast: nothing is compared with
// PNGs.

import 'package:bb_ui/bb_ui.dart' show Density;
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/settings/settings_section.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'scenes.dart';
import 'support.dart';

/// Widths across both size class boundaries (600 and 1000).
const _widths = [360.0, 480.0, 800.0, 1440.0];

/// System text sizes: default, a common larger setting, and the largest the
/// app follows.
const _textScales = [1.0, 1.3, 2.0];

const _height = 900.0;

HostController _controller() => HostController(
  store: MemoryConfigStore(sampleConfig),
  starter: (c) => Played().start(c),
);

/// Taps [key] after scrolling it into view.
Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

/// Catches layout errors (an overflow is one) while [body] runs, and names
/// the library line that drew them.
Future<List<String>> _layoutErrors(Future<void> Function() body) async {
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.toString();
    final at = RegExp(r'(lib/src/[a-z_/]+\.dart:\d+)')
        .firstMatch(text)
        ?.group(1);
    errors.add(
      '${details.exceptionAsString().split('\n').first}'
      '${at == null ? '' : ' at $at'}',
    );
  };
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return errors;
}

void main() {
  for (final (width, density) in [
    for (final w in _widths) (w, Density.pointer),
    for (final w in _widths.where((w) => w < 600)) (w, Density.touch),
  ]) {
    for (final scale in _textScales) {
      final size = Size(width, _height);
      final name = '${width.toInt()} px, ${density.name}, text x$scale';
      void textScale(WidgetTester tester) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      }

      testWidgets('main screen at $name', (tester) async {
        textScale(tester);
        final errors = await _layoutErrors(
          () => pumpApp(tester, _controller(), size: size, density: density),
        );
        expect(errors, isEmpty, reason: errors.toSet().join('\n'));
      });

      for (final section in SettingsSection.values) {
        testWidgets('settings ${section.name} at $name', (tester) async {
          textScale(tester);
          final errors = await _layoutErrors(() async {
            await pumpApp(tester, _controller(), size: size, density: density);
            final show = find.byKey(const ValueKey('rail-show'));
            if (show.evaluate().isNotEmpty) await _tap(tester, 'rail-show');
            await _tap(tester, 'rail-settings');
            await _tap(tester, 'settings-nav-${section.name}');
          });
          expect(errors, isEmpty, reason: errors.toSet().join('\n'));
        });
      }
    }
  }
}
