// The workbench of a saved host: the kit's chat pane beside the app's own
// rail (project groups). AgentWorkbench builds its rail inside and takes no
// replacement, so this composes the same public pieces: RailLayout, the chat
// pane and the backend's list. It has no workspace column; the crew shows as
// the strip under the header.

import 'dart:async';

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bb_ui/bb_ui.dart' show SecondaryButton, ts;
import 'package:flutter/widgets.dart';

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
    this.now,
    this.onSettings,
    this.onSwitchHost,
    this.transcriptActions = const TranscriptActions(),
    this.onReviewApproval,
  });

  final AgentBackend backend;

  /// The host's rows, for each chat's project path.
  final RemoteChatRows rows;

  /// Which project groups are open.
  final ProjectRailState state;
  final String hostName;

  /// The chat to open; follows changes (a rewind makes a new chat).
  final String? initialChatId;
  final DateTime? now;
  final VoidCallback? onSettings;
  final VoidCallback? onSwitchHost;
  final TranscriptActions transcriptActions;
  final ValueChanged<Approval>? onReviewApproval;

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
  String? _selected;
  int _listing = 0;
  final Map<String, ChatStatus> _seen = {};

  @override
  void initState() {
    super.initState();
    _selected = widget.initialChatId;
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
    if (id == _selected) return;
    setState(() => _selected = id);
  }

  void _onSnapshot(ChatSnapshot snap) {
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

  /// Starts a chat. The host's `session.open` takes no project, so the chat
  /// begins in the host's own workspace; [project] only names where the
  /// person asked for it.
  Future<void> _newChat([ProjectGroup? project]) async {
    try {
      final chat = await widget.backend.createChat(
        workspace: project == null || project.key.isEmpty ? null : project.key,
      );
      if (!mounted) return;
      setState(() => _selected = chat.id);
      unawaited(_refresh());
    } catch (_) {
      // The rail stays as it was.
    }
  }

  String _projectOf(ChatSummary chat) => chat.workspace ?? noProjectName;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final clock = widget.now ?? DateTime.now();
    return ColoredBox(
      color: t.canvas,
      child: RailLayout(
        controller: _rail,
        rail: ListenableBuilder(
          listenable: widget.state,
          builder: (context, _) => RemoteRail(
            hostName: widget.hostName,
            groups: groupByProject(_chats, widget.rows.workspaceOf),
            needsYou: chatsNeedingYou(_chats),
            projectOf: _projectOf,
            state: widget.state,
            selectedId: _selected,
            now: clock,
            onSelect: (chat) => _select(chat.id),
            onNewChat: _newChat,
            onNewChatIn: _newChat,
            onSwitchHost: widget.onSwitchHost,
            onSettings: widget.onSettings,
            hasMore: _nextCursor != null,
            loadingMore: _loadingMore,
            loadMoreFailed: _loadMoreFailed,
            onLoadMore: _loadMore,
          ),
        ),
        child: Builder(
          builder: (context) {
            final whole =
                RailScope.maybeOf(context)?.sizeClass ?? SizeClass.expanded;
            return _sheet(context, t, whole);
          },
        ),
      ),
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
