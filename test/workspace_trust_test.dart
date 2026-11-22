// Workspace trust: the prompt in the chat while the host skips a workspace's
// project config, and Settings > Workspace trust with Revoke.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'scenes.dart';
import 'support.dart';

const _garden = '/home/user/garden';

void main() {
  testWidgets('an untrusted workspace asks in the chat; Trust calls the host', (
    tester,
  ) async {
    final trust = FakeWorkspaceTrust();
    await pumpApp(tester, Played(trust: trust).controller());
    expect(find.byKey(const ValueKey('trust-notice')), findsNothing);

    trust.untrusted(_garden);
    await settle(tester);
    expect(find.text('Trust garden?'), findsOneWidget);

    // Not now closes it and records nothing.
    await tester.tap(find.byKey(const ValueKey('trust-notice-dismiss')));
    await settle(tester);
    expect(find.byKey(const ValueKey('trust-notice')), findsNothing);
    expect(trust.calls, isEmpty);

    trust.untrusted(_garden);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('trust-notice-trust')));
    await settle(tester);
    expect(trust.calls, ['trust:$_garden']);
    expect(find.byKey(const ValueKey('trust-notice')), findsNothing);
  });

  testWidgets('Settings lists trusted workspaces; Revoke calls the host', (
    tester,
  ) async {
    final trust = FakeWorkspaceTrust(['/home/user/lab']);
    await pumpApp(tester, Played(trust: trust).controller());
    final show = find.byKey(const ValueKey('rail-show'));
    if (show.evaluate().isNotEmpty) {
      await tester.tap(show);
      await settle(tester);
    }
    await tester.tap(find.byKey(const ValueKey('rail-settings')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('settings-nav-trust')));
    await settle(tester);
    expect(find.text('/home/user/lab'), findsOneWidget);
    expect(find.text('2026-11-21'), findsOneWidget);

    // The host's own state event brings a workspace trusted elsewhere.
    trust.trusted.add('/home/user/orchard');
    trust.untrusted('/home/user/orchard');
    await settle(tester);
    expect(
      find.byKey(const ValueKey('trust-row-/home/user/orchard')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('trust-revoke-/home/user/lab')));
    await settle(tester);
    expect(trust.calls, ['revoke:/home/user/lab']);
    expect(find.text('/home/user/lab'), findsNothing);
  });
}
