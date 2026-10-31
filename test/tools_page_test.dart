// Settings > Tools, and the rules behind it: the toolsets read from the host
// config, the entries a selection is saved as, and the approvals. The pages
// run against fake host settings, so each test reads the keys and values the
// page wrote with config.set.

import 'dart:convert';

import 'package:bubblepaw_desktop/src/core/host_settings.dart';
import 'package:bubblepaw_desktop/src/settings/toolsets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'scenes.dart';
import 'support.dart';
import 'tools_samples.dart';

Future<void> _openTools(WidgetTester tester, FakeHostSettings settings) async {
  await pumpApp(tester, Played(settings: settings).controller());
  final show = find.byKey(const ValueKey('rail-show'));
  if (show.evaluate().isNotEmpty) {
    await tester.tap(show);
    await settle(tester);
  }
  await tester.tap(find.byKey(const ValueKey('rail-settings')));
  await settle(tester);
  await tester.tap(find.byKey(const ValueKey('settings-nav-tools')));
  await settle(tester);
}

/// The writes as `key=json`, so lists compare by value.
List<String> _written(FakeHostSettings settings) => [
  for (final w in settings.writes) '${w.$1}=${jsonEncode(w.$2)}',
];

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

void main() {
  group('toolset rules', () {
    final categories = groupTools(sampleTools);

    test('tools group into the built-in categories, then one per server', () {
      expect(
        [for (final c in categories) c.id],
        [
          'files',
          'commands',
          'web',
          'agents',
          'history',
          'other',
          'mcp:filesystem',
          'mcp:github',
        ],
      );
      expect(categories.last.title, 'github');
      expect(categories.last.mcp, isTrue);
      expect(toolLabel(categories.last.tools.first), 'list_issues');
    });

    test('a full category saves as category:<id>, a partial one as names', () {
      final all = {for (final t in sampleTools) t.name};
      expect(
        entriesFor(
          selected: all.difference({'exec', 'web_search', 'web_fetch'}),
          categories: categories,
        ),
        [
          'category:files',
          'poll',
          'wait',
          'cancel',
          'jobs',
          'category:agents',
          'category:history',
          'category:other',
          'category:mcp:filesystem',
          'category:mcp:github',
        ],
      );
    });

    test('entries that match nothing now published are kept', () {
      expect(
        entriesFor(
          selected: {'read'},
          categories: categories,
          previous: ['category:gone', 'old_tool', 'list'],
        ),
        ['read', 'category:gone', 'old_tool'],
      );
    });

    test('entries resolve to the published tools they name', () {
      expect(resolveEntries(['category:web', 'read', 'nope'], sampleTools), {
        'web_search',
        'web_fetch',
        'read',
      });
    });

    test('config reads toolsets, the main toolset and approvals', () {
      final config = ToolsConfig.parse([
        const HostSetting(key: 'agent.toolset', value: 'no-web'),
        const HostSetting(key: 'toolsets.a.tools', value: ['read']),
        const HostSetting(key: 'approvals.deny', value: ['exec']),
        const HostSetting(key: 'approvals.tools.edit', value: 'allow'),
        const HostSetting(key: 'approvals.tools.write', value: 'auto'),
      ]);
      expect(config.main, 'no-web');
      expect(config.toolsets, {
        'a': ['read'],
      });
      final byName = {for (final t in sampleTools) t.name: t};
      expect(config.approvalOf(byName['exec']!), 'deny');
      expect(config.approvalOf(byName['edit']!), 'allow');
      expect(config.approvalOf(byName['write']!), isNull);
      expect(config.approvalOf(byName['read']!), 'allow');
      expect(config.approvalOf(byName['mcp__github__list_issues']!), 'ask');
    });

    test('a toolset name is checked', () {
      expect(toolsetNameError('', others: []), 'Enter a name.');
      expect(
        toolsetNameError('a b', others: []),
        'Use letters, numbers, - and _ only.',
      );
      expect(
        toolsetNameError('all', others: ['all']),
        'A toolset named all already exists.',
      );
      expect(toolsetNameError('ok-1_x', others: ['all']), isNull);
    });
  });

  group('Tools page', () {
    testWidgets('lists the toolsets with how many tools each selects', (
      tester,
    ) async {
      await _openTools(tester, sampleToolSettings());
      expect(find.text('18 of 30 tools'), findsOneWidget);
      expect(find.text('30 of 30 tools'), findsOneWidget);
      expect(find.text('28 of 30 tools'), findsOneWidget);
      expect(find.text('Built-in'), findsNWidgets(2));
      expect(
        find.text(
          'The parent agent picks a toolset when it starts a subagent.',
        ),
        findsNothing,
      );
    });

    testWidgets('a tool added to a toolset saves its entries', (tester) async {
      final settings = sampleToolSettings();
      await _openTools(tester, settings);
      await _tap(tester, 'toolset-no-web');
      await _tap(tester, 'check-web_search');
      expect(_written(settings), [
        'toolsets.no-web.tools=["category:files","category:commands",'
            '"web_search","category:agents","category:history",'
            '"category:other","category:mcp:filesystem","category:mcp:github"]',
      ]);
    });

    testWidgets('selecting a whole category saves category:<id>', (
      tester,
    ) async {
      final settings = sampleToolSettings();
      await _openTools(tester, settings);
      await _tap(tester, 'toolset-no-web');
      await _tap(tester, 'check-web');
      expect(_written(settings).single, contains('"category:web"'));
      expect(_written(settings).single, startsWith('toolsets.no-web.tools='));
      // The page reads the saved toolset back.
      await _tap(tester, 'toolset-back');
      expect(find.text('30 of 30 tools'), findsNWidgets(2));
    });

    testWidgets('clearing one tool turns its category into tool names', (
      tester,
    ) async {
      final settings = sampleToolSettings();
      await _openTools(tester, settings);
      await _tap(tester, 'toolset-no-web');
      await _tap(tester, 'check-exec');
      expect(_written(settings), [
        'toolsets.no-web.tools=["category:files","poll","wait","cancel",'
            '"jobs","category:agents","category:history","category:other",'
            '"category:mcp:filesystem","category:mcp:github"]',
      ]);
    });

    testWidgets('a built-in toolset can be read but not changed', (
      tester,
    ) async {
      final settings = sampleToolSettings();
      await _openTools(tester, settings);
      await _tap(tester, 'toolset-read-only');
      await _tap(tester, 'check-read');
      await _tap(tester, 'check-files');
      expect(settings.writes, isEmpty);
      expect(find.byKey(const ValueKey('delete-toolset')), findsNothing);
      expect(find.byKey(const ValueKey('toolset-name')), findsNothing);
    });

    testWidgets('a taken name shows an error and is not saved', (tester) async {
      final settings = sampleToolSettings();
      await _openTools(tester, settings);
      await _tap(tester, 'toolset-no-web');
      await tester.enterText(find.byKey(const ValueKey('toolset-name')), 'all');
      await settle(tester);
      expect(find.text('A toolset named all already exists.'), findsOneWidget);
      await _tap(tester, 'toolset-back');
      expect(settings.writes, isEmpty);
    });

    testWidgets('a new name renames the toolset', (tester) async {
      final settings = sampleToolSettings();
      await _openTools(tester, settings);
      await _tap(tester, 'toolset-no-web');
      await tester.enterText(
        find.byKey(const ValueKey('toolset-name')),
        'no-net',
      );
      await settle(tester);
      await _tap(tester, 'toolset-back');
      expect(
        [for (final w in settings.writes) w.$1],
        ['toolsets.no-net.tools', 'toolsets.no-web.tools'],
      );
      expect(settings.writes.last.$2, isNull);
      expect(find.byKey(const ValueKey('toolset-no-net')), findsOneWidget);
    });

    testWidgets('New toolset creates an empty one and opens it', (
      tester,
    ) async {
      final settings = sampleToolSettings();
      await _openTools(tester, settings);
      await _tap(tester, 'new-toolset');
      expect(_written(settings), ['toolsets.toolset-1.tools=[]']);
      expect(find.byKey(const ValueKey('toolset-name')), findsOneWidget);
    });

    testWidgets('Delete removes the toolset after a confirmation', (
      tester,
    ) async {
      final settings = sampleToolSettings();
      await _openTools(tester, settings);
      await _tap(tester, 'toolset-no-web');
      await _tap(tester, 'delete-toolset');
      expect(settings.writes, isEmpty);
      await tester.tap(find.text('Delete no-web'));
      await settle(tester);
      expect(_written(settings), ['toolsets.no-web.tools=null']);
      expect(find.byKey(const ValueKey('toolset-no-web')), findsNothing);
    });

    testWidgets('the toolset the main chat uses cannot be deleted', (
      tester,
    ) async {
      final settings = sampleToolSettings(extra: {'agent.toolset': 'no-web'});
      await _openTools(tester, settings);
      await _tap(tester, 'toolset-no-web');
      expect(
        find.text('Main chat uses this toolset. Choose another one first.'),
        findsOneWidget,
      );
      await _tap(tester, 'delete-toolset');
      expect(settings.writes, isEmpty);
    });

    testWidgets('a category approval sets every tool and keeps the rest', (
      tester,
    ) async {
      final settings = sampleToolSettings();
      await _openTools(tester, settings);
      // Web is mixed: web_search allows and web_fetch is denied.
      expect(find.text('Mixed'), findsWidgets);
      await _tap(tester, 'appr-web-allow');
      expect(_written(settings), [
        'approvals.deny=null',
        'approvals.tools.web_fetch="allow"',
      ]);
    });

    testWidgets('Deny adds the tool to approvals.deny', (tester) async {
      final settings = sampleToolSettings();
      await _openTools(tester, settings);
      await _tap(tester, 'approvals-toggle-files');
      await _tap(tester, 'appr-read-deny');
      expect(_written(settings), ['approvals.deny=["web_fetch","read"]']);
    });

    testWidgets('one tool takes its own approval', (tester) async {
      final settings = sampleToolSettings();
      await _openTools(tester, settings);
      await _tap(tester, 'approvals-toggle-files');
      await _tap(tester, 'appr-edit-allow');
      expect(_written(settings), ['approvals.tools.edit="allow"']);
    });

    testWidgets('an MCP server is its own group, asking by default', (
      tester,
    ) async {
      final settings = sampleToolSettings();
      await _openTools(tester, settings);
      expect(find.text('MCP'), findsNWidgets(2));
      await _tap(tester, 'appr-mcp:github-allow');
      expect(_written(settings), [
        'approvals.tools.mcp__github__list_issues="allow"',
        'approvals.tools.mcp__github__get_pull_request="allow"',
      ]);
    });

    testWidgets('a refused change shows the host reason', (tester) async {
      final settings = sampleToolSettings();
      await _openTools(tester, settings);
      settings.failWith = const HostSettingsException('Not allowed.');
      await _tap(tester, 'approvals-toggle-files');
      await _tap(tester, 'appr-edit-allow');
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('tools-error'))).data,
        'Could not change the approval for edit. Not allowed.',
      );
    });

    testWidgets('a restart_required reply says so', (tester) async {
      final settings = FakeHostSettings(
        values: sampleToolsValues(),
        toolList: sampleTools,
        restartOnly: {'approvals.tools.edit'},
      );
      await _openTools(tester, settings);
      await _tap(tester, 'approvals-toggle-files');
      await _tap(tester, 'appr-edit-allow');
      expect(find.text('Applies after restart.'), findsOneWidget);
    });
  });
}
