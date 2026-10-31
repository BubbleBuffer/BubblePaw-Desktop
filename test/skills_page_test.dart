// Settings > Skills: the skills the host found, where each one lives, and the
// switch that writes `skills.<name>.enabled`.

import 'package:bubblepaw_desktop/src/core/host_settings.dart';
import 'package:bubblepaw_desktop/src/settings/skills_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'scenes.dart';
import 'support.dart';
import 'tools_samples.dart';

Future<void> _openSkills(WidgetTester tester, FakeHostSettings settings) async {
  await pumpApp(tester, Played(settings: settings).controller());
  final show = find.byKey(const ValueKey('rail-show'));
  if (show.evaluate().isNotEmpty) {
    await tester.tap(show);
    await settle(tester);
  }
  await tester.tap(find.byKey(const ValueKey('rail-settings')));
  await settle(tester);
  await tester.tap(find.byKey(const ValueKey('settings-nav-skills')));
  await settle(tester);
}

void main() {
  group('skill folder', () {
    HostSkill at(String path, {String source = 'workspace'}) => HostSkill(
      name: 'x',
      description: '',
      source: source,
      path: path,
      enabled: true,
    );

    test('a workspace skill shows the folder it was found in', () {
      expect(
        skillFolder(at('/work/garden/.claude/skills/x/SKILL.md')),
        '.claude/skills',
      );
      expect(
        skillFolder(at(r'C:\work\garden\.agents\skills\x\SKILL.md')),
        '.agents/skills',
      );
    });

    test('a user skill shows the user skills folder', () {
      expect(
        skillFolder(
          at('/home/maya/.config/bubblepaw/skills/x/SKILL.md', source: 'user'),
        ),
        '~/.config/bubblepaw/skills',
      );
    });
  });

  group('Skills page', () {
    testWidgets('lists the skills with their source and switch', (
      tester,
    ) async {
      await _openSkills(tester, sampleToolSettings());
      expect(find.text('release-notes'), findsOneWidget);
      expect(
        find.text('Draft release notes from the merged pull requests.'),
        findsOneWidget,
      );
      expect(find.text('.claude/skills'), findsOneWidget);
      expect(find.text('.agents/skills'), findsOneWidget);
      expect(find.text('~/.config/bubblepaw/skills'), findsOneWidget);
      expect(find.text('Project'), findsNWidgets(2));
      expect(find.text('User'), findsOneWidget);
      expect(find.text('On'), findsNWidgets(2));
      expect(find.text('Off'), findsOneWidget);
    });

    testWidgets('a switch sets skills.<name>.enabled and shows the result', (
      tester,
    ) async {
      final settings = sampleToolSettings();
      await _openSkills(tester, settings);
      await tester.tap(find.byKey(const ValueKey('toggle-skill-commit-style')));
      await settle(tester);
      expect(settings.writes, [('skills.commit-style.enabled', true)]);
      expect(find.text('On'), findsNWidgets(3));
      await tester.tap(
        find.byKey(const ValueKey('toggle-skill-release-notes')),
      );
      await settle(tester);
      expect(settings.writes.last, ('skills.release-notes.enabled', false));
      expect(find.text('Off'), findsOneWidget);
    });

    testWidgets('no skills names the folders it looks in', (tester) async {
      await _openSkills(tester, sampleToolSettings(skills: false));
      expect(find.byKey(const ValueKey('skills-empty')), findsOneWidget);
      expect(find.text('.agents/skills'), findsOneWidget);
      expect(find.text('.claude/skills'), findsOneWidget);
      expect(find.text('~/.config/bubblepaw/skills'), findsOneWidget);
    });

    testWidgets('a refused switch shows the host reason', (tester) async {
      final settings = sampleToolSettings();
      await _openSkills(tester, settings);
      settings.failWith = const HostSettingsException('Not allowed.');
      await tester.tap(find.byKey(const ValueKey('toggle-skill-commit-style')));
      await settle(tester);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('skills-error'))).data,
        'Could not turn commit-style on. Not allowed.',
      );
      expect(find.text('Off'), findsOneWidget);
    });

    testWidgets('without a host settings it says the host is not running', (
      tester,
    ) async {
      await pumpApp(tester, Played().controller());
      final show = find.byKey(const ValueKey('rail-show'));
      if (show.evaluate().isNotEmpty) {
        await tester.tap(show);
        await settle(tester);
      }
      await tester.tap(find.byKey(const ValueKey('rail-settings')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('settings-nav-skills')));
      await settle(tester);
      expect(find.byKey(const ValueKey('skills-no-host')), findsOneWidget);
    });
  });
}
