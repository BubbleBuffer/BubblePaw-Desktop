// This computer's host for the search tests and goldens: it lists the sample
// chats of four projects (as a saved host does) and answers title searches.

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bubblepaw_desktop/src/config.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/remote/remote_chats.dart';

import 'remote_chats_fakes.dart';
import 'support.dart';

/// A backend that remembers which chats were opened.
class LocalBackend extends ListedBackend {
  LocalBackend() : super(sampleRemoteChats);

  final loaded = <String>[];

  @override
  Future<ChatSnapshot> loadChat(String chatId) {
    loaded.add(chatId);
    return super.loadChat(chatId);
  }
}

/// This computer's host, started in [workspace], that lists the sample chats
/// of four projects and answers title searches.
class LocalFixture {
  LocalFixture({this.titleSearch = true, this.workspace = gardenApi});

  final bool titleSearch;
  final String workspace;
  final backend = LocalBackend();
  final rows = RemoteChatRows();
  final starts = <AppConfig>[];

  /// The params of each title search the app sent.
  final searches = <Map<String, Object?>>[];

  /// Answers a title search; null answers from [sampleRemoteChats].
  Future<Object?> Function(Map<String, Object?> params)? onSearch;

  Future<Object?> raw(String method, Map<String, Object?> params) async {
    searches.add(params);
    final answer = onSearch;
    return answer == null ? sampleSearchAnswer(params) : answer(params);
  }

  Future<StartedBackend> start(AppConfig config) async {
    starts.add(config);
    final searcher = RemoteBackend(
      backend,
      rows,
      rawRequest: raw,
      titleSearch: titleSearch,
    );
    return StartedBackend(
      backend,
      () async {},
      now: remoteClock,
      searchChats: searcher.canSearchTitles ? searcher.searchChats : null,
      chatWorkspace: rows.workspaceOf,
    );
  }

  HostController controller() => HostController(
    store: MemoryConfigStore(
      AppConfig(workspaceDirectory: workspace, dataDirectory: '/data'),
    ),
    starter: start,
  );
}
