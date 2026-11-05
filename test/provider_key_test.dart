// Provider keys (Core v0.13.0) on Settings > Models: the Add key and Edit key
// dialog, Remove key, the environment source, a saved host that does not give
// this device the Full profile, a host that refuses, a host without the
// methods, and that a key value never stays anywhere in the app. Runs against
// fake host settings: no host, no model.

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bb_ui/bb_ui.dart' show SecondaryButton;
import 'package:bubblepaw_desktop/src/core/host_settings.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_remote.dart';
import 'fakes.dart';
import 'scenes.dart';
import 'support.dart';

Future<void> _show(WidgetTester tester, String section) async {
  final show = find.byKey(const ValueKey('rail-show'));
  if (show.evaluate().isNotEmpty) {
    await tester.tap(show);
    await settle(tester);
  }
  await tester.tap(find.byKey(const ValueKey('rail-settings')));
  await settle(tester);
  await tester.tap(find.byKey(ValueKey('settings-nav-$section')));
  await settle(tester);
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

Played _host(FakeHostSettings settings, {ProviderSetup? providers}) => Played(
  capabilities: hostControlCapabilities,
  providers: providers ?? sampleKeyProviders,
  models: sampleModels,
  settings: settings,
);

/// Settings > Models of this computer's host, or of a saved host this device
/// holds [profile] on.
Future<HostController> _models(
  WidgetTester tester,
  FakeHostSettings settings, {
  String? profile,
  Size size = wide,
}) async {
  final HostController controller;
  if (profile == null) {
    controller = _host(settings).controller();
    await pumpApp(tester, controller, size: size);
  } else {
    final saved = fakeSavedHost(profile: profile);
    final remote = _host(settings);
    controller = Played(hostLinks: FakeHostLinks(hosts: [saved]))
        .controller(remoteStarter: (links, id) => remote.start(sampleConfig));
    addTearDown(controller.close);
    await pumpApp(tester, controller, size: size);
    await tester.runAsync(() => controller.openRemoteHost(saved.id));
    await settle(tester);
  }
  await _show(tester, 'models');
  return controller;
}

Future<void> _enterKey(WidgetTester tester, String value) async {
  await tester.enterText(find.byKey(const ValueKey('key-field')), value);
  await settle(tester);
}

/// The field's controller, to look at after the dialog is gone.
TextEditingController _fieldController(WidgetTester tester) => tester
    .widget<EditableText>(find.byKey(const ValueKey('key-field')))
    .controller;

/// Whether the Add key or Edit key button of that key responds to a tap.
bool _enabled(WidgetTester tester, String key) =>
    tester.widget<SecondaryButton>(find.byKey(ValueKey(key))).onTap != null;

void main() {
  group('Add key and Edit key', () {
    testWidgets('a provider without a key offers Add key', (tester) async {
      final settings = keyedHostSettings();
      await _models(tester, settings);
      final card = find.byKey(const ValueKey('provider-openrouter'));
      await tester.ensureVisible(card);
      expect(
        find.descendant(of: card, matching: find.text('No key')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Add key')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text('Add a key to use these models.'),
        ),
        findsOneWidget,
      );
      // The other two have a key: Edit key, no hint to add one.
      for (final name in ['deepseek', 'anthropic']) {
        final other = find.byKey(ValueKey('provider-$name'));
        expect(
          find.descendant(of: other, matching: find.text('Key set')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: other, matching: find.text('Edit key')),
          findsOneWidget,
        );
      }
      // The scripted provider needs no key and shows no key controls.
      expect(find.byKey(const ValueKey('key-button-demo')), findsNothing);
    });

    testWidgets('Save key hands the value to the host and shows Key set', (
      tester,
    ) async {
      final settings = keyedHostSettings();
      await _models(tester, settings);
      await _tap(tester, 'key-button-openrouter');
      expect(find.text('Add key for openrouter'), findsOneWidget);
      expect(find.text('API key'), findsWidgets);
      expect(
        find.text('Stored on the host that runs this provider.'),
        findsOneWidget,
      );
      // Nothing to save yet.
      await _tap(tester, 'key-save');
      expect(settings.keyCalls.where((c) => c.startsWith('set:')), isEmpty);
      expect(find.text('Add key for openrouter'), findsOneWidget);

      await _enterKey(tester, '  $markerKey  ');
      final field = _fieldController(tester);
      await _tap(tester, 'key-save');

      // The host got the key once, without the spaces around it.
      expect(settings.keyCalls.where((c) => c.startsWith('set:')), [
        'set:openrouter',
      ]);
      expect(settings.storedKeys['openrouter'], markerKey);
      // The dialog closed and its field was emptied.
      expect(find.text('Add key for openrouter'), findsNothing);
      expect(field.text, isEmpty);
      // The card now says Key set, with Edit key.
      final card = find.byKey(const ValueKey('provider-openrouter'));
      expect(
        find.descendant(of: card, matching: find.text('Key set')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Edit key')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('provider-key-openrouter')),
        findsNothing,
      );
    });

    testWidgets('Edit key replaces a stored key', (tester) async {
      final settings = keyedHostSettings();
      await _models(tester, settings);
      await _tap(tester, 'key-button-deepseek');
      expect(find.text('Edit key for deepseek'), findsOneWidget);
      await _enterKey(tester, '$markerKey-NEW');
      await _tap(tester, 'key-save');
      expect(settings.storedKeys['deepseek'], '$markerKey-NEW');
      expect(find.text('Edit key for deepseek'), findsNothing);
    });

    testWidgets('Cancel sends nothing and empties the field', (tester) async {
      final settings = keyedHostSettings();
      await _models(tester, settings);
      await _tap(tester, 'key-button-openrouter');
      await _enterKey(tester, markerKey);
      final field = _fieldController(tester);
      expect(field.text, markerKey);
      await _tap(tester, 'key-cancel');
      expect(find.text('Add key for openrouter'), findsNothing);
      expect(field.text, isEmpty);
      expect(settings.keyCalls.where((c) => !c.startsWith('get:')), isEmpty);
      expect(find.textContaining(markerKey), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('provider-openrouter')),
          matching: find.text('No key'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('closing the dialog with the X empties the field too', (
      tester,
    ) async {
      final settings = keyedHostSettings();
      await _models(tester, settings);
      await _tap(tester, 'key-button-openrouter');
      await _enterKey(tester, markerKey);
      final field = _fieldController(tester);
      await _tap(tester, 'dialog-close');
      expect(find.text('Add key for openrouter'), findsNothing);
      expect(field.text, isEmpty);
      expect(settings.keyCalls.where((c) => c.startsWith('set:')), isEmpty);
    });

    testWidgets('the field hides what is typed', (tester) async {
      await _models(tester, keyedHostSettings());
      await _tap(tester, 'key-button-openrouter');
      final field = tester.widget<EditableText>(
        find.byKey(const ValueKey('key-field')),
      );
      expect(field.obscureText, isTrue);
    });

    testWidgets('a host that applies the key after a restart says so', (
      tester,
    ) async {
      final settings = keyedHostSettings()..keyRestartNeeded = true;
      await _models(tester, settings);
      await _tap(tester, 'key-button-openrouter');
      await _enterKey(tester, markerKey);
      await _tap(tester, 'key-save');
      expect(
        find.text('Saved. The host applies the key after it restarts.'),
        findsOneWidget,
      );
    });
  });

  group('Remove key', () {
    testWidgets('a stored key can be removed and the dialog says what '
        'happens next', (tester) async {
      final settings = keyedHostSettings();
      await _models(tester, settings);
      await _tap(tester, 'key-button-deepseek');
      expect(
        find.text(
          'Removing the stored key makes the host fall back to the '
          'environment variable DEEPSEEK_API_KEY when it is set.',
        ),
        findsOneWidget,
      );
      await _tap(tester, 'key-remove');
      expect(settings.keyCalls.where((c) => c.startsWith('remove:')), [
        'remove:deepseek',
      ]);
      expect(settings.storedKeys.containsKey('deepseek'), isFalse);
      expect(find.text('Edit key for deepseek'), findsNothing);
      final card = find.byKey(const ValueKey('provider-deepseek'));
      expect(
        find.descendant(of: card, matching: find.text('No key')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Add key')),
        findsOneWidget,
      );
    });

    testWidgets('Add key has no Remove key', (tester) async {
      await _models(tester, keyedHostSettings());
      await _tap(tester, 'key-button-openrouter');
      expect(find.byKey(const ValueKey('key-remove')), findsNothing);
    });

    testWidgets('removing falls back to the environment when one is set', (
      tester,
    ) async {
      final settings = FakeHostSettings(
        values: {'model.main': 'demo/scripted'},
        environmentKeys: {'deepseek'},
      )..storedKeys['deepseek'] = '$markerKey-STORED';
      await _models(tester, settings);
      await _tap(tester, 'key-button-deepseek');
      await _tap(tester, 'key-remove');
      final card = find.byKey(const ValueKey('provider-deepseek'));
      // Still a key, now from the environment.
      expect(
        find.descendant(of: card, matching: find.text('Key set')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('provider-key-source-deepseek')),
        findsOneWidget,
      );
    });
  });

  group('the environment source', () {
    testWidgets('says Key set and names the environment', (tester) async {
      await _models(tester, keyedHostSettings());
      final card = find.byKey(const ValueKey('provider-anthropic'));
      await tester.ensureVisible(card);
      expect(
        find.descendant(of: card, matching: find.text('Key set')),
        findsOneWidget,
      );
      expect(
        find.text(
          'The key comes from the environment variable ANTHROPIC_API_KEY on '
          'the host. A stored key replaces it.',
        ),
        findsOneWidget,
      );
      // A stored key does not get that line.
      expect(
        find.byKey(const ValueKey('provider-key-source-deepseek')),
        findsNothing,
      );
    });

    testWidgets('the dialog can replace it and has nothing to remove', (
      tester,
    ) async {
      final settings = keyedHostSettings();
      await _models(tester, settings);
      await _tap(tester, 'key-button-anthropic');
      expect(find.text('Edit key for anthropic'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('key-dialog-environment')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('key-remove')), findsNothing);
      await _enterKey(tester, markerKey);
      await _tap(tester, 'key-save');
      expect(settings.storedKeys['anthropic'], markerKey);
      // Now stored: the environment line is gone.
      expect(
        find.byKey(const ValueKey('provider-key-source-anthropic')),
        findsNothing,
      );
    });
  });

  group('a saved host', () {
    testWidgets('with the Full profile takes a key', (tester) async {
      final settings = keyedHostSettings();
      await _models(tester, settings, profile: 'full');
      expect(
        find.byKey(const ValueKey('provider-key-blocked-openrouter')),
        findsNothing,
      );
      await _tap(tester, 'key-button-openrouter');
      await _enterKey(tester, markerKey);
      await _tap(tester, 'key-save');
      expect(settings.storedKeys['openrouter'], markerKey);
    });

    for (final profile in ['read', 'edit']) {
      testWidgets('with the $profile profile shows the state and says why '
          'the buttons do not work', (tester) async {
        final settings = keyedHostSettings();
        await _models(tester, settings, profile: profile);
        final name = profile == 'read' ? 'Read' : 'Edit';
        final reason =
            'Changing a key needs the Full profile. This device has the '
            '$name profile on this host.';
        // The state is read (the Read profile may do that).
        expect(settings.keyCalls, contains('get:openrouter'));
        final card = find.byKey(const ValueKey('provider-openrouter'));
        await tester.ensureVisible(card);
        expect(
          find.descendant(of: card, matching: find.text('No key')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.text(reason)),
          findsOneWidget,
        );
        // The buttons are there and unavailable, before any key is typed.
        for (final provider in ['openrouter', 'deepseek', 'anthropic']) {
          expect(find.byKey(ValueKey('key-button-$provider')), findsOneWidget);
          expect(_enabled(tester, 'key-button-$provider'), isFalse);
        }
        await tester.tap(find.byKey(const ValueKey('key-button-openrouter')));
        await settle(tester);
        expect(find.text('Add key for openrouter'), findsNothing);
        expect(settings.keyCalls.where((c) => !c.startsWith('get:')), isEmpty);
      });
    }

    testWidgets('that kept no profile is left to refuse', (tester) async {
      final settings = keyedHostSettings()
        ..keyFails = const HostSettingsException(
          "This device's profile does not allow changing provider keys. It "
          'needs the Full profile.',
          code: profileRefusedCode,
        );
      await _models(tester, settings, profile: '');
      expect(
        find.byKey(const ValueKey('provider-key-blocked-openrouter')),
        findsNothing,
      );
      await _tap(tester, 'key-button-openrouter');
      await _enterKey(tester, markerKey);
      await _tap(tester, 'key-save');
      // Core's refusal is shown in the dialog, which stays open.
      expect(find.text('Add key for openrouter'), findsOneWidget);
      expect(find.textContaining('It needs the Full profile.'), findsOneWidget);
      expect(_markerOutsideField(), isEmpty);
    });
  });

  group('a host that refuses', () {
    testWidgets('shows the host message, keeps the dialog and no key text', (
      tester,
    ) async {
      final settings = keyedHostSettings()
        ..keyFails = const HostSettingsException(
          'The host could not write the key.',
          code: -32013,
        );
      await _models(tester, settings);
      await _tap(tester, 'key-button-openrouter');
      await _enterKey(tester, markerKey);
      await _tap(tester, 'key-save');
      expect(find.text('Add key for openrouter'), findsOneWidget);
      expect(find.text('The host could not write the key.'), findsOneWidget);
      expect(settings.storedKeys.containsKey('openrouter'), isFalse);
      // Still no Key set behind the dialog.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('provider-openrouter')),
          matching: find.text('No key'),
        ),
        findsOneWidget,
      );
      // Typing again clears the message; Cancel leaves cleanly.
      await _enterKey(tester, '$markerKey-2');
      expect(find.text('The host could not write the key.'), findsNothing);
      await _tap(tester, 'key-cancel');
      expect(find.text('Add key for openrouter'), findsNothing);
    });

    testWidgets('a failure that is not a refusal gets a plain message', (
      tester,
    ) async {
      final settings = _ThrowingKeys();
      await _models(tester, settings);
      await _tap(tester, 'key-button-openrouter');
      await _enterKey(tester, markerKey);
      await _tap(tester, 'key-save');
      expect(
        find.text('Something went wrong. The key was not changed.'),
        findsOneWidget,
      );
      expect(_markerOutsideField(), isEmpty);
    });
  });

  group('a host without the methods', () {
    testWidgets('keeps the old hint and says what to update', (tester) async {
      final settings = keyedHostSettings()..keyApi = false;
      await _models(tester, settings);
      expect(
        find.byKey(const ValueKey('provider-keys-unsupported')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('key-button-openrouter')), findsNothing);
      // The pill still comes from the provider list.
      final card = find.byKey(const ValueKey('provider-openrouter'));
      await tester.ensureVisible(card);
      expect(
        find.descendant(of: card, matching: find.text('No key')),
        findsOneWidget,
      );
      expect(
        find.text(
          'The host did not find OPENROUTER_API_KEY. Set it for the host '
          'and restart it to use this provider.',
        ),
        findsOneWidget,
      );
    });
  });

  group('a key never stays in the app', () {
    testWidgets('after saving, in a report, in a log or on screen', (
      tester,
    ) async {
      final settings = keyedHostSettings();
      final controller = await _models(tester, settings);
      await _tap(tester, 'key-button-openrouter');
      await _enterKey(tester, markerKey);
      await _tap(tester, 'key-save');
      // Only the host's fake store holds it.
      expect(settings.storedKeys['openrouter'], markerKey);
      expect('${settings.values}', isNot(contains(markerKey)));
      expect('${settings.writes}', isNot(contains(markerKey)));

      // Not on screen: no text, no editable field.
      expect(find.textContaining(markerKey), findsNothing);
      expect(find.byKey(const ValueKey('key-field')), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is EditableText && w.controller.text.contains(markerKey),
        ),
        findsNothing,
      );

      // Not in the app's own log, nor in the diagnostics a report would hold.
      final lines = [
        for (final l in controller.log.desktopLines) l.text,
        for (final l in controller.log.hostLines) l.text,
        for (final e in controller.log.errors) '${e.error} ${e.stack}',
      ];
      expect(lines.join('\n'), isNot(contains(markerKey)));
      final storage = MemoryFeedbackStorage();
      final feedback = TestFeedback(controller, storage: storage);
      final diagnostics = feedback.diagnostics();
      expect(diagnostics, isNot(contains(markerKey)));

      // Not in a saved report.
      await feedback.save(text: 'Saved a key.', diagnostics: diagnostics);
      for (final draft in storage.drafts.values) {
        expect(draft.reportMarkdown, isNot(contains(markerKey)));
      }
    });

    testWidgets('after a refusal, nor in the message', (tester) async {
      final settings = keyedHostSettings()
        ..keyFails = const HostSettingsException(
          'The host rejected the key.',
          code: -32012,
        );
      final controller = await _models(tester, settings);
      await _tap(tester, 'key-button-openrouter');
      await _enterKey(tester, markerKey);
      await _tap(tester, 'key-save');
      await _tap(tester, 'key-cancel');
      expect(find.textContaining(markerKey), findsNothing);
      final lines = [
        for (final l in controller.log.desktopLines) l.text,
        for (final l in controller.log.hostLines) l.text,
        for (final e in controller.log.errors) '${e.error} ${e.stack}',
      ];
      expect(lines.join('\n'), isNot(contains(markerKey)));
      expect(
        TestFeedback(controller).diagnostics(),
        isNot(contains(markerKey)),
      );
    });
  });

  group('at narrow width', () {
    testWidgets('the cards and the dialog fit', (tester) async {
      final settings = keyedHostSettings();
      await _models(tester, settings, size: narrow);
      expect(
        find.byKey(const ValueKey('key-button-openrouter')),
        findsOneWidget,
      );
      await _tap(tester, 'key-button-openrouter');
      expect(find.text('Add key for openrouter'), findsOneWidget);
      await _enterKey(tester, markerKey);
      await _tap(tester, 'key-save');
      expect(settings.storedKeys['openrouter'], markerKey);
    });
  });
}

/// Host settings whose key write fails with something that is not a refusal.
class _ThrowingKeys extends FakeHostSettings {
  _ThrowingKeys() : super(values: {'model.main': 'demo/scripted'});

  @override
  Future<ProviderKeyChange> setProviderKey(String provider, String value) {
    keyCalls.add('set:$provider');
    return Future<ProviderKeyChange>.error(StateError('boom'));
  }
}

/// Text on screen that shows the marker, other than the key field itself
/// (which keeps what was typed while the dialog is open to retry).
List<Element> _markerOutsideField() => find
    .textContaining(markerKey)
    .evaluate()
    .where((e) => e.widget is! EditableText)
    .toList();
