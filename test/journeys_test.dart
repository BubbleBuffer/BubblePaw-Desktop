@Tags(['journey'])
library;

import 'dart:io';

import 'package:bb_ui_testing/bb_ui_testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journeys/scenes.dart';

const _journeyDirectory = 'test/journeys';
const _budgetFile = 'budgets.json';
const _budgetPath = '$_journeyDirectory/$_budgetFile';
const _reportDirectory = 'build/journeys';

void main() {
  final extension = RegExp(r'\.(json|yaml)$');
  final files =
      Directory(_journeyDirectory)
          .listSync()
          .whereType<File>()
          .where((file) => file.uri.pathSegments.last != _budgetFile)
          .where((file) => extension.hasMatch(file.path))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    throw StateError('No journey files in $_journeyDirectory.');
  }

  final report = JourneyReport(
    path: '$_reportDirectory/report.json',
    screenshotDirectory: '$_reportDirectory/screenshots',
  );
  final updateBudgets = switch (Platform.environment['BB_UI_UPDATE_BUDGETS']) {
    '1' || 'true' => true,
    _ => false,
  };
  final goals = <String>{};
  var completed = 0;

  for (final file in files) {
    final journey = loadJourneyFile(file.path);
    final goal = journey['goal'] as String;
    if (!goals.add(goal)) {
      throw FormatException('Duplicate journey goal "$goal".', file.path);
    }
    final steps = journey['steps'] as List;
    if (steps.isEmpty || !(steps.last as Map).containsKey('expect')) {
      throw FormatException('A journey must end with an expect.', file.path);
    }
    final id = file.uri.pathSegments.last.replaceFirst(extension, '');
    final sceneId = id.split('--').first;

    testWidgets(goal, (tester) async {
      final scene = await pumpJourneyScene(tester, sceneId);
      final record = await runJourney(tester, journey, report: report);
      if (id == sceneId) {
        await scene.verify();
      }
      expect(tester.takeException(), isNull);
      if (!updateBudgets) {
        checkBudgets(JourneyReport()..records.add(record), _budgetPath);
      }
      completed++;
    });
  }

  tearDownAll(() {
    if (updateBudgets && completed == files.length) {
      checkBudgets(report, _budgetPath, update: true);
    }
  });
}
