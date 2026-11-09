// How the chat list of a saved host is grouped: the chats that need the
// person, then one group per project, busiest first.

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:flutter/foundation.dart';

import '../config.dart' show workspaceFolderName;

/// The chats of one project on the host.
class ProjectGroup {
  const ProjectGroup({
    required this.key,
    required this.name,
    required this.chats,
    required this.running,
    required this.waiting,
    required this.latest,
  });

  /// The project's path on the host; empty for chats without one.
  final String key;

  /// The folder name; "No project" for chats without a path.
  final String name;

  final List<ChatSummary> chats;

  /// Chats with a running turn.
  final int running;

  /// Chats waiting for an approval or an answer.
  final int waiting;

  /// The latest change of any chat in the group.
  final DateTime? latest;

  bool get active => running + waiting > 0;
}

/// The name of the group of chats that have no project path.
const noProjectName = 'No project';

/// The chats waiting for the person, in list order.
List<ChatSummary> chatsNeedingYou(List<ChatSummary> chats) => [
  for (final chat in chats)
    if (chat.status == ChatStatus.needsYou) chat,
];

/// One group per project path ([pathOf] gives a chat's path, or null).
/// Groups with a running or waiting chat come first, then the rest by their
/// latest change, newest first; ties by name. Chats keep the given order.
List<ProjectGroup> groupByProject(
  List<ChatSummary> chats,
  String? Function(String chatId) pathOf,
) {
  final byKey = <String, List<ChatSummary>>{};
  for (final chat in chats) {
    byKey.putIfAbsent(pathOf(chat.id) ?? '', () => []).add(chat);
  }
  final groups = [
    for (final entry in byKey.entries)
      ProjectGroup(
        key: entry.key,
        name: entry.key.isEmpty
            ? noProjectName
            : workspaceFolderName(entry.key),
        chats: entry.value,
        running: entry.value
            .where((c) => c.status == ChatStatus.running)
            .length,
        waiting: entry.value
            .where((c) => c.status == ChatStatus.needsYou)
            .length,
        latest: entry.value
            .map((c) => c.updatedAt)
            .whereType<DateTime>()
            .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a),
      ),
  ];
  groups.sort((a, b) {
    if (a.active != b.active) return a.active ? -1 : 1;
    final at = a.latest, bt = b.latest;
    if (at != null && bt != null && at != bt) return bt.compareTo(at);
    if ((at == null) != (bt == null)) return at == null ? 1 : -1;
    return a.name.compareTo(b.name);
  });
  return groups;
}

/// Which project groups are open. All start closed. The host controller owns
/// one for each saved host it opens.
class ProjectRailState extends ChangeNotifier {
  final Set<String> _open = {};

  bool isOpen(String key) => _open.contains(key);

  void toggle(String key) {
    if (!_open.remove(key)) _open.add(key);
    notifyListeners();
  }

  void open(String key) {
    if (_open.add(key)) notifyListeners();
  }
}
