// The workbench of a saved host: the kit's chat pane beside the app's own
// rail (project groups). AgentWorkbench builds its rail inside and takes no
// replacement, so this composes the same public pieces: RailLayout, the chat
// pane and the backend's list. The workspace column holds the Context pane
// only, as on this computer, and is left out on the phone. The crew shows as
// the strip under the header.

import 'dart:async';
import 'dart:math' as math;

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bb_ui/bb_ui.dart' show SecondaryButton, ts;
import 'package:flutter/widgets.dart';

import '../screens/host_open_notice.dart';
import 'project_groups.dart';
import 'remote_chats.dart';
import 'remote_rail.dart';

class RemoteWorkbench extends StatefulWidget {
  const RemoteWorkbench({
    super.key,
    required this.backend,
    required this.rows,
    required this.state,
    required this.hostName,
    this.initialChatId,
    this.startOnList = false,
    this.now,
    this.onSettings,
    this.onSwitchHost,
    this.transcriptActions = const TranscriptActions(),
    this.onReviewApproval,
    this.workspaceController,
  });

  final AgentBackend backend;

  /// The host's rows, for each chat's project path.
  final RemoteChatRows rows;

  /// Which project groups are open.
  final ProjectRailState state;
  final String hostName;

  /// The chat to open; follows changes (a rewind makes a new chat).
  final String? initialChatId;

  /// At compact width the chat list is shown first and a chat opens over it
  /// (the phone's home); otherwise the first chat is open at the start.
  final bool startOnList;
  final DateTime? now;
  final VoidCallback? onSettings;
  final VoidCallback? onSwitchHost;
  final TranscriptActions transcriptActions;
  final ValueChanged<Approval>? onReviewApproval;

  /// The layout of the workspace that holds the Context pane; null for none
  /// (the phone, or a host without the context capability).
  final WorkspaceController? workspaceController;

  @override
  State<RemoteWorkbench> createState() => _RemoteWorkbenchState();
}

class _RemoteWorkbenchState extends State<RemoteWorkbench> {
  final RailController _rail = RailController();
  final GlobalKey _sheetKey = GlobalKey(debugLabel: 'remote sheet');
  List<ChatSummary> _chats = const [];
  String? _nextCursor;
  bool _extended = false;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  bool _listed = false;
  String? _listError;
  String? _newChatError;
  bool _pickerOpen = false;

  /// The project the next New chat starts in (a path on the host); null is
  /// the host's default. The plus of a project and the picker both set it.
  String? _pickedPath;
  String? _selected;
  int _listing = 0;
  final Map<String, ChatStatus> _seen = {};
  final ContextPaneController _context = ContextPaneController();
  final GlobalKey _workspaceKey = GlobalKey(debugLabel: 'remote workspace');
  ContextView? _contextView;
  bool _workspaceShown = false;

  bool get _hasWorkspace =>
      widget.workspaceController != null &&
      widget.backend.capabilities.has(KitCapability.context);

  @override
  void initState() {
    super.initState();
    _selected = widget.initialChatId;
    if (widget.startOnList && widget.initialChatId == null) _rail.open = true;
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(RemoteWorkbench old) {
    super.didUpdateWidget(old);
    if (old.initialChatId != widget.initialChatId &&
        widget.initialChatId != null) {
      _selected = widget.initialChatId;
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _rail.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final ticket = ++_listing;
    try {
      final page = await widget.backend.listChats();
      if (!mounted || ticket != _listing) return;
      setState(() {
        if (_extended) {
          final first = {for (final c in page.chats) c.id};
          _chats = [
            ...page.chats,
            for (final c in _chats)
              if (!first.contains(c.id)) c,
          ];
        } else {
          _chats = page.chats;
          _nextCursor = page.nextCursor;
        }
        _listed = true;
        _listError = null;
        _selected ??= page.chats.isEmpty ? null : page.chats.first.id;
      });
    } catch (error) {
      if (!mounted || ticket != _listing) return;
      setState(() {
        _listed = true;
        _listError = error is KitError
            ? error.message
            : 'The chat list could not be loaded.';
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    try {
      final page = await widget.backend.listChats(cursor: cursor);
      if (!mounted) return;
      setState(() {
        final known = {for (final c in _chats) c.id};
        _chats = [
          ..._chats,
          for (final c in page.chats)
            if (!known.contains(c.id)) c,
        ];
        _nextCursor = page.nextCursor;
        _extended = true;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _loadMoreFailed = true;
      });
    }
  }

  void _select(String id) {
    // On the phone a tapped chat opens full screen, over the list.
    if (widget.startOnList) _rail.open = false;
    if (id == _selected) return;
    setState(() {
      _selected = id;
      _contextView = null;
    });
  }

  void _onSnapshot(ChatSnapshot snap) {
    if (snap.chatId == _selected && snap.context != _contextView) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && snap.chatId == _selected) {
          setState(() => _contextView = snap.context);
        }
      });
    }
    final before = _seen[snap.chatId];
    final now = ChatSummary.of(snap);
    _seen[snap.chatId] = now.status;
    final row = _chats.where((c) => c.id == snap.chatId).firstOrNull;
    if (row == null || row.title != now.title || before != now.status) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refresh());
      });
    }
  }

  /// The header's context meter: add the Context pane when the chat has none,
  /// show the workspace and bring the pane to the Now tab.
  void _openContext() {
    final controller = widget.workspaceController;
    if (!_hasWorkspace || controller == null) return;
    final existing = controller.layout.tabs
        .where((t) => t.kind == WorkspaceKind.context.id)
        .firstOrNull;
    if (existing == null) {
      controller.addPane(WorkspaceKind.context.id);
    } else {
      controller.activate(existing.id);
    }
    setState(() => _workspaceShown = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _context.showNow());
  }

  void _toggleWorkspace() =>
      setState(() => _workspaceShown = !_workspaceShown);

  Widget _paneBuilder(BuildContext context, WorkspaceTab tab) {
    final chat = _selected;
    if (tab.kind != WorkspaceKind.context.id || chat == null) {
      return const SizedBox.shrink();
    }
    return AgentContextPane(
      backend: widget.backend,
      chatId: chat,
      view: _contextView,
      controller: _context,
      now: widget.now,
    );
  }

  /// Starts a chat in [path] on the host, or in the host's own workspace
  /// without one. A host that refuses the project says so; the chat is not
  /// started anywhere else.
  Future<void> _startChat(String? path) async {
    setState(() {
      _pickerOpen = false;
      _newChatError = null;
    });
    try {
      final chat = await widget.backend.createChat(workspace: path);
      if (!mounted) return;
      if (widget.startOnList) _rail.open = false;
      setState(() => _selected = chat.id);
      unawaited(_refresh());
    } on KitError catch (error) {
      if (!mounted) return;
      setState(() => _newChatError = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _newChatError = 'The chat could not be started.');
    }
  }

  /// The plus of a project: the next New chat follows it too.
  Future<void> _newChatIn(ProjectGroup project) {
    final path = project.key.isEmpty ? null : project.key;
    setState(() => _pickedPath = path);
    return _startChat(path);
  }

  /// The host's known projects, from the loaded rows, by name.
  List<PickableProject> _projects(List<ProjectGroup> groups) {
    final list = [
      for (final group in groups)
        if (group.key.isNotEmpty) (path: group.key, name: group.name),
    ];
    list.sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.path.compareTo(b.path);
    });
    return list;
  }

  String _projectOf(ChatSummary chat) => chat.workspace ?? noProjectName;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final clock = widget.now ?? DateTime.now();
    final error = _newChatError;
    return ColoredBox(
      color: t.canvas,
      child: Stack(
        children: [
          Positioned.fill(
            child: RailLayout(
              controller: _rail,
              rail: ListenableBuilder(
                listenable: widget.state,
                builder: (context, _) {
                  final groups = groupByProject(
                    _chats,
                    widget.rows.workspaceOf,
                  );
                  final projects = _projects(groups);
                  // A project that is no longer listed is not the pick.
                  final picked = projects.any((p) => p.path == _pickedPath)
                      ? _pickedPath
                      : null;
                  return RemoteRail(
                    hostName: widget.hostName,
                    groups: groups,
                    needsYou: chatsNeedingYou(_chats),
                    projectOf: _projectOf,
                    waitingOf: widget.rows.waitingOf,
                    state: widget.state,
                    selectedId: _selected,
                    now: clock,
                    onSelect: (chat) => _select(chat.id),
                    onNewChat: () => unawaited(_startChat(picked)),
                    onNewChatIn: (group) => unawaited(_newChatIn(group)),
                    projects: projects,
                    pickedPath: picked,
                    pickerOpen: _pickerOpen,
                    onTogglePicker: () =>
                        setState(() => _pickerOpen = !_pickerOpen),
                    onPick: (path) => setState(() {
                      _pickedPath = path;
                      _pickerOpen = false;
                    }),
                    onSwitchHost: widget.onSwitchHost,
                    onSettings: widget.onSettings,
                    hasMore: _nextCursor != null,
                    loadingMore: _loadingMore,
                    loadMoreFailed: _loadMoreFailed,
                    onLoadMore: _loadMore,
                  );
                },
              ),
              child: Builder(
                builder: (context) {
                  final whole =
                      RailScope.maybeOf(context)?.sizeClass ??
                      SizeClass.expanded;
                  if (!_hasWorkspace) return _sheet(context, t, whole);
                  return SizeClassBuilder(
                    builder: (context, area) => LayoutBuilder(
                      builder: (context, box) =>
                          _area(context, t, whole, area, box.maxWidth),
                    ),
                  );
                },
              ),
            ),
          ),
          if (error != null)
            Positioned(
              right: 16,
              bottom: 16,
              child: KeyedSubtree(
                key: const ValueKey('new-chat-error'),
                child: HostOpenNotice(
                  message: error,
                  onDismiss: () => setState(() => _newChatError = null),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The chat with the workspace beside it, laid out as the kit's workbench
  /// does on this computer.
  Widget _area(
    BuildContext context,
    BbTheme t,
    SizeClass whole,
    SizeClass area,
    double width,
  ) {
    final sheet = _sheet(context, t, whole);
    final shown = _workspaceShown;
    final workspace = KeyedSubtree(
      key: _workspaceKey,
      child: AgentWorkspace(
        controller: widget.workspaceController!,
        kinds: const [WorkspaceKind.context],
        paneBuilder: _paneBuilder,
        open: shown,
        onClose: _toggleWorkspace,
        sizeClass: area,
      ),
    );
    if (area.isCompact) {
      return Stack(
        fit: StackFit.expand,
        children: [
          sheet,
          Positioned.fill(child: workspace),
        ],
      );
    }
    if (!shown) return sheet;
    final padded = Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
      child: workspace,
    );
    if (area.isMedium) {
      final w = math.min(420.0, math.max(240.0, width * .4));
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: sheet),
          SizedBox(width: w, child: padded),
        ],
      );
    }
    final w = math.min(584.0, math.max(444.0, width * .44));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: w, child: sheet),
        Expanded(child: padded),
      ],
    );
  }

  Widget _sheet(BuildContext context, BbTheme t, SizeClass whole) {
    final selected = _selected;
    final Widget content = selected == null
        ? _empty(t)
        : AgentChatPane(
            backend: widget.backend,
            chatId: selected,
            now: widget.now,
            onSnapshot: _onSnapshot,
            onOpenChat: (id) {
              _select(id);
              unawaited(_refresh());
            },
            onChatsChanged: () => unawaited(_refresh()),
            transcriptActions: widget.transcriptActions,
            onReviewApproval: widget.onReviewApproval,
            workspaceShown: _hasWorkspace && _workspaceShown,
            onToggleWorkspace: _hasWorkspace ? _toggleWorkspace : null,
            onOpenContext: _hasWorkspace ? _openContext : null,
          );
    if (whole.isCompact) {
      return KeyedSubtree(
        key: _sheetKey,
        child: ColoredBox(color: t.surface, child: content),
      );
    }
    final radius = BorderRadius.vertical(top: Radius.circular(t.radii.sheet));
    return KeyedSubtree(
      key: _sheetKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: radius,
            boxShadow: t.colors.stack,
          ),
          child: ClipRRect(borderRadius: radius, child: content),
        ),
      ),
    );
  }

  Widget _empty(BbTheme t) {
    if (!_listed) {
      return Center(
        child: Text('Loading…', style: ts(t.typeScale.ui, t.faint)),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _listError ?? 'No chats yet',
            style: ts(t.typeScale.ui, t.muted),
          ),
          if (_listError != null) ...[
            const SizedBox(height: 12),
            SecondaryButton(
              label: 'Retry',
              height: 36,
              onTap: () => unawaited(_refresh()),
            ),
          ],
        ],
      ),
    );
  }
}
