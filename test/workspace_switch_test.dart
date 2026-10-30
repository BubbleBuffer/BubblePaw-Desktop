import 'package:bubblepaw_desktop/src/config.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bubblepaw_desktop/src/scripted.dart';

import 'support.dart';

const _data = '/home/user/.local/share/bubblepaw-desktop/data';

AppConfig _config({List<String> recent = const []}) => AppConfig(
  workspaceDirectory: '/home/user/project',
  dataDirectory: _data,
  recentWorkspaces: recent,
);

/// A scripted backend per start, so each start and each disposal is visible.
class _Starts {
  final configs = <AppConfig>[];
  var disposed = 0;

  Future<StartedBackend> start(AppConfig config) async {
    configs.add(config);
    final backend = await playedScript();
    return StartedBackend(
      backend,
      () async => disposed++,
      now: backend.clock.now(),
    );
  }
}

void main() {
  group('recent workspaces', () {
    test('the newest leads, without repeats, at most 8', () {
      var config = _config();
      for (var i = 0; i < 12; i++) {
        config = config.withWorkspace('/w/$i');
      }
      expect(config.workspaceDirectory, '/w/11');
      expect(config.recentWorkspaces, hasLength(8));
      expect(config.recentWorkspaces.first, '/w/11');
      // Going back to an older one moves it to the head once.
      config = config.withWorkspace('/w/8');
      expect(config.recentWorkspaces.first, '/w/8');
      expect(config.recentWorkspaces.where((p) => p == '/w/8'), hasLength(1));
      expect(config.recentWorkspaces, hasLength(8));
      // The workspace it replaced is remembered too.
      expect(config.recentWorkspaces[1], '/w/11');
    });

    test('they survive JSON; a config without them has none', () {
      final config = _config().withWorkspace('/w/a');
      expect(AppConfig.fromJson(config.toJson()), config);
      expect(
        AppConfig.fromJson({'workspaceDirectory': 'w', 'dataDirectory': 'd'})!
            .recentWorkspaces,
        isEmpty,
      );
    });
  });

  group('the rail menu', () {
    Future<(HostController, _Starts, MemoryConfigStore)> open(
      WidgetTester tester, {
      Future<String?> Function()? pickFolder,
    }) async {
      final starts = _Starts();
      final store = MemoryConfigStore(
        _config(recent: ['/home/user/project', '/home/user/other']),
      );
      final controller = HostController(store: store, starter: starts.start);
      addTearDown(controller.close);
      await pumpApp(tester, controller, pickFolder: pickFolder);
      expect(starts.configs, hasLength(1));
      await tester.tap(find.text('project'));
      await settle(tester);
      return (controller, starts, store);
    }

    testWidgets('lists the recent workspaces and Open folder', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('workspace-menu-item-0')), findsOne);
      expect(find.byKey(const ValueKey('workspace-menu-item-1')), findsOne);
      expect(find.text('other'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workspace-menu-open-folder')),
        findsOneWidget,
      );
    });

    testWidgets('picking one restarts the host with it and keeps the data', (
      tester,
    ) async {
      final (controller, starts, store) = await open(tester);
      await tester.tap(find.byKey(const ValueKey('workspace-menu-item-1')));
      await settle(tester);
      expect(starts.disposed, 1, reason: 'the old backend is disposed');
      expect(starts.configs, hasLength(2));
      expect(starts.configs.last.workspaceDirectory, '/home/user/other');
      expect(starts.configs.last.dataDirectory, _data);
      expect(controller.phase, HostPhase.running);
      expect(controller.workspaceLabel, 'other');
      expect(store.saved!.workspaceDirectory, '/home/user/other');
      expect(store.saved!.recentWorkspaces.first, '/home/user/other');
      expect(find.text('other'), findsWidgets);
      expect(find.byKey(const ValueKey('workspace-menu-item-0')), findsNothing);
    });

    testWidgets('picking the open workspace changes nothing', (tester) async {
      final (_, starts, _) = await open(tester);
      await tester.tap(find.byKey(const ValueKey('workspace-menu-item-0')));
      await settle(tester);
      expect(starts.configs, hasLength(1));
      expect(starts.disposed, 0);
    });

    testWidgets('Open folder switches to the folder picked', (tester) async {
      final (_, starts, store) = await open(
        tester,
        pickFolder: () async => '/home/user/fresh',
      );
      await tester.tap(
        find.byKey(const ValueKey('workspace-menu-open-folder')),
      );
      await settle(tester);
      expect(starts.configs.last.workspaceDirectory, '/home/user/fresh');
      expect(starts.disposed, 1);
      expect(store.saved!.recentWorkspaces.take(2), [
        '/home/user/fresh',
        '/home/user/project',
      ]);
    });

    testWidgets('a cancelled picker leaves the host alone', (tester) async {
      final (_, starts, _) = await open(tester, pickFolder: () async => null);
      await tester.tap(
        find.byKey(const ValueKey('workspace-menu-open-folder')),
      );
      await settle(tester);
      expect(starts.configs, hasLength(1));
      expect(starts.disposed, 0);
    });
  });
}
