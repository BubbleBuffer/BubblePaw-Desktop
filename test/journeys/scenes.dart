// Starting states for measured journeys. All host activity stays in memory.

import 'dart:async';

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:bb_ui/bb_ui.dart' show Density;
import 'package:bubblepaw_desktop/src/core/host_settings.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/remote/host_links.dart';
import 'package:bubblepaw_desktop/src/remote/link_scanner.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_remote.dart';
import '../fakes.dart';
import '../local_search_fakes.dart';
import '../scenes.dart';
import '../support.dart';

const journeyMessage = 'List the failing tests';
const journeyWorkspace = '/home/user/garden';
const journeyPairingLink = 'bubblepaw://pair?v=1&code=K7M2QX9PD4';

class JourneyScene {
  const JourneyScene({required this.verify});

  /// Checks the host-side effect as well as the JSON's visible success state.
  final Future<void> Function() verify;
}

/// Pumps the starting scene for a JSON filename (without its extension).
/// Setup does not perform any of the actions being measured. This helper owns
/// controller, scanner, timer, reduced-motion and viewport cleanup.
Future<JourneyScene> pumpJourneyScene(WidgetTester tester, String id) async {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

  late final HostController controller;
  late final Future<void> Function() verify;
  FakeWorkspaceTrust? notice;
  var phone = false;

  switch (id) {
    case 'first-message':
      final played = Played(scripts: [finishedScript()]);
      controller = played.controller();
      verify = () async {
        expect(
          played.backend.commands.where(
            (command) => command.name == 'createChat',
          ),
          hasLength(1),
        );
        final sent = played.backend.commands.singleWhere(
          (command) => command.name == 'send',
        );
        final loaded = played.backend.commands.lastWhere(
          (command) => command.name == 'loadChat',
        );
        expect(sent.args[0], loaded.args[0]);
        expect(sent.args[0], isNot('done-chat'));
        expect(sent.args[1], journeyMessage);
      };
    case 'add-provider-key':
      final settings = FakeHostSettings(
        values: {'model.main': 'demo/scripted'},
      );
      final played = Played(
        scripts: [finishedScript()],
        capabilities: hostControlCapabilities,
        providers: sampleProviders,
        models: sampleModels,
        settings: settings,
      );
      controller = played.controller();
      verify = () async {
        expect(settings.storedKeys['openrouter'], markerKey);
        expect(settings.keyCalls.where((call) => call.startsWith('set:')), [
          'set:openrouter',
        ]);
        expect(find.textContaining(markerKey), findsNothing);
      };
    case 'switch-chat-model':
      final played = Played(
        scripts: [finishedScript()],
        capabilities: KitCapabilities([
          ...stdioCapabilities.values,
          KitCapability.models,
        ]),
        providers: sampleProviders,
        models: sampleModels,
      );
      controller = played.controller();
      verify = () async {
        final call = played.backend.commands.singleWhere(
          (command) => command.name == 'setModel',
        );
        expect(call.args, ['done-chat', 'demo/scripted-fast']);
        expect(
          played.backend.stateOf('done-chat')?.model,
          'demo/scripted-fast',
        );
      };
    case 'add-mcp-server':
      final settings = _JourneyMcpSettings();
      controller = Played(
        scripts: [finishedScript()],
        settings: settings,
      ).controller();
      verify = () async {
        expect(settings.writes.single.$1, 'mcp.servers.journey-files');
        expect(settings.writes.single.$2, {'command': 'journey-mcp-fake'});
        expect(
          settings.values['mcp.servers.journey-files.command'],
          'journey-mcp-fake',
        );
      };
    case 'trust-workspace':
      final trust = FakeWorkspaceTrust();
      notice = trust;
      controller = Played(
        scripts: [finishedScript()],
        trust: trust,
      ).controller();
      verify = () async {
        expect(trust.calls, [
          'trust:$journeyWorkspace',
          'revoke:$journeyWorkspace',
        ]);
        expect(trust.trusted, isEmpty);
      };
    case 'find-old-chat':
      final fixture = LocalFixture();
      controller = fixture.controller();
      verify = () async {
        expect(fixture.searches.single['query'], 'plan');
        expect(fixture.backend.loaded.last, 'c3');
      };
    case 'review-file-diff':
      // Reuse the quota approval's real diff while leaving out its earlier
      // edits, so the pending approval is the sole Review diff affordance.
      final approval = quotaReconnectScript().steps.singleWhere(
        (step) => step.event['kind'] == 'approval.requested',
      );
      controller = Played(
        scripts: [
          ChatScript(
            chatId: 'review-file',
            title: 'Review the changed quota file',
            steps: [
              const ScriptStep(Duration.zero, {
                'kind': 'run.started',
                'runId': 'run-quota-1',
              }),
              ScriptStep(Duration.zero, approval.event),
            ],
          ),
        ],
      ).controller();
      verify = () async {
        final path = tester.widget<Text>(
          find.byKey(const ValueKey('diff-path')),
        );
        expect(path.data, 'crates/harbor-runtime/src/usage/mod.rs');
        expect(find.byKey(const ValueKey('diff-close')), findsOneWidget);
      };
    case 'phone-add-host':
      phone = true;
      final links = _ConfirmingHostLinks();
      var scans = 0;
      final previousScanner = linkScanner;
      linkScanner = (_) async {
        scans++;
        return journeyPairingLink;
      };
      addTearDown(() {
        linkScanner = previousScanner;
        links.confirmation?.cancel();
      });
      controller = Played(hostLinks: links).controller(
        localHost: false,
        phoneAccess: (_) => FakeRemoteAccess(),
        remoteStarter: (_, _) => Played().start(sampleConfig),
      );
      verify = () async {
        expect(scans, 1);
        expect(links.receivedLinks, [journeyPairingLink]);
        expect(links.saved.single.id, links.nextPairing.id);
        expect(links.pairings, hasLength(1));
      };
    default:
      throw ArgumentError.value(id, 'id', 'Unknown journey scene');
  }

  addTearDown(() async {
    await controller.close();
    controller.dispose();
  });
  await pumpApp(
    tester,
    controller,
    size: phone ? const Size(375, 812) : wide,
    density: phone ? Density.touch : Density.pointer,
  );
  if (notice != null) {
    notice.untrusted(journeyWorkspace);
    await settle(tester);
  }
  return JourneyScene(verify: verify);
}

/// FakeHostSettings stores new entries already; reflect their registration in
/// its status list too. The fake command is never launched, so report stopped.
class _JourneyMcpSettings extends FakeHostSettings {
  @override
  Future<List<McpServerStatus>> mcpServers() async => [
    ...await super.mcpServers(),
    if (values.containsKey('mcp.servers.journey-files.command'))
      const McpServerStatus(name: 'journey-files', state: 'stopped'),
  ];
}

/// Simulates the other device's owner confirming after the comparison screen
/// is visible. The journey still performs the scan and checks both UI states.
class _ConfirmingHostLinks extends FakeHostLinks {
  final receivedLinks = <String>[];
  Timer? confirmation;

  @override
  Future<HostPairingHandle> pair(String link, String deviceName) async {
    receivedLinks.add(link);
    final pairing = await super.pair(link, deviceName);
    confirmation = Timer(const Duration(seconds: 2), () {
      pairings.single.confirm();
    });
    return pairing;
  }
}
