// Rewind from here: the kit's per-message action reaches the backend, and the
// chat the host creates for the rewind is the one the app opens.

import 'dart:async';

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'scenes.dart';
import 'support.dart';

void main() {
  testWidgets('rewinding opens the new chat', (tester) async {
    final created = StreamController<ChatSummary>.broadcast();
    addTearDown(created.close);
    final played = Played(
      scripts: [finishedScript()],
      capabilities: stdioCapabilities,
      createdChats: created.stream,
    );
    await pumpApp(tester, played.controller());
    expect(find.text('Rename the quota label'), findsWidgets);

    await tester.tap(find.text('Rewind from here'));
    await settle(tester);
    final rewind = played.backend.commands.lastWhere((c) => c.name == 'rewind');
    expect(rewind.args, ['done-chat', 'u1']);

    // BubblePawBackend answers a rewind with a new chat and announces it.
    await tester.runAsync(() async {
      final chat = await played.backend.createChat(title: 'Before the rename');
      created.add(chat);
    });
    await settle(tester);

    // The new chat is open: its title is in the header, not only the rail.
    expect(find.text('Before the rename'), findsWidgets);
    expect(find.text('Rename the quota label'), findsWidgets);
    final header = find.text('Before the rename');
    expect(header, findsAtLeastNWidgets(2));
  });

  testWidgets('a backend without rewind has no action', (tester) async {
    final played = Played(
      scripts: [finishedScript()],
      capabilities: KitCapabilities([
        KitCapability.send,
        KitCapability.createChat,
      ]),
    );
    await pumpApp(tester, played.controller());
    expect(find.text('Rename the quota label'), findsWidgets);
    expect(find.text('Rewind from here'), findsNothing);
  });
}
