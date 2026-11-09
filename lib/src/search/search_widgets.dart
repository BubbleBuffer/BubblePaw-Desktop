// The pieces of a chat rail that the search shares: the box, the answer to a
// query (rows grouped by project, the typed text marked) and the rows and
// labels around them. A saved host's rail and this computer's both use them.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart' show ChatSummary;
import 'package:bb_ui/bb_ui.dart'
    show Hover, TypeSpec, noteSelectionControls, ts;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';

import '../feedback/glyphs.dart' show glyphClose;
import '../remote/project_groups.dart';
import '../settings/remote_glyphs.dart';
import '../settings/settings_widgets.dart' show glyphIcon;
import 'chat_search.dart';

/// The host's answer to the typed query: the matching chats of every
/// project, grouped by project, or why there are none.
class ChatSearchResults extends StatelessWidget {
  const ChatSearchResults({
    super.key,
    required this.search,
    required this.hostName,
    required this.selectedId,
    required this.onSelect,
    this.pathOf,
    this.now,
    this.labelOf,
  });

  final ChatSearchController search;

  /// Named in "Search looks at chat titles on ...".
  final String hostName;
  final String? selectedId;
  final ValueChanged<ChatSummary> onSelect;

  /// A chat's project path on the host, to group the results.
  final String? Function(String chatId)? pathOf;
  final DateTime? now;

  /// Replaces a row's status text ("Needs approval"); null keeps it.
  final String? Function(String chatId)? labelOf;

  @override
  Widget build(BuildContext context) {
    final clock = now ?? DateTime.now();
    final results = search.results;
    final groups = groupByProject(results, pathOf ?? (_) => null);
    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        if (search.phase == ChatSearchPhase.failed)
          SearchNote(
            key: const ValueKey('search-failed'),
            title: 'Search failed',
            body: search.error ?? '',
            action: 'Try again',
            onAction: search.retry,
          )
        else if (results.isEmpty && search.phase == ChatSearchPhase.searching)
          const SearchNote(
            key: ValueKey('search-searching'),
            title: 'Searching…',
          )
        else if (results.isEmpty)
          SearchNote(
            key: const ValueKey('search-empty'),
            title: 'No chats match "${search.query}"',
            body: 'Search looks at chat titles on $hostName.',
          )
        else ...[
          for (final group in groups) ...[
            RailLabel(group.name),
            for (final chat in group.chats)
              RailChatRow(
                key: ValueKey('search-row-${chat.id}'),
                chat: chat,
                detail: railDetail(chat, clock),
                label: labelOf?.call(chat.id),
                selected: chat.id == selectedId,
                bar: true,
                highlight: search.query,
                onTap: () => onSelect(chat),
              ),
          ],
          if (search.hasMore)
            RailMoreRow(
              key: const ValueKey('search-load-more'),
              loading: search.loadingMore,
              failed: search.moreFailed,
              onTap: search.loadMore,
              idle: 'Show more matches',
              busy: 'Loading more matches…',
              failure: 'Could not load more matches. Try again',
            ),
        ],
      ],
    );
  }
}

class RailLabel extends StatelessWidget {
  const RailLabel(this.text, {super.key, this.count});

  final String text;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Row(
        children: [
          Text(text, style: ts(const TypeSpec(12, 16, 700), theme.railMuted)),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text(
              '$count',
              style: ts(const TypeSpec(12, 16, 700), theme.attentionInk),
            ),
          ],
        ],
      ),
    );
  }
}

/// A chat row of a project rail: the title, the status and, on a "Needs you"
/// row, the project's name.
class RailChatRow extends StatelessWidget {
  const RailChatRow({
    super.key,
    required this.chat,
    required this.detail,
    required this.selected,
    required this.onTap,
    this.project,
    this.label,
    this.bar = false,
    this.highlight,
  });

  final ChatSummary chat;
  final String? detail;

  /// The project tag of a "Needs you" row; null inside a project's group.
  final String? project;

  /// Replaces the status text ("Needs approval", "Needs an answer").
  final String? label;

  /// The selection bar of a row inside a group.
  final bool bar;

  /// The typed search text, marked in the title; null outside a search.
  final String? highlight;
  final bool selected;
  final VoidCallback onTap;

  /// The title; with [highlight], the typed text marked.
  Widget _title(BbTheme theme) {
    final style = ts(
      theme.typeScale.ui,
      theme.railInk.withValues(alpha: selected ? 1 : .86),
      weight: selected ? 700 : 500,
    );
    final typed = highlight;
    if (typed == null) {
      return Text(
        chat.title,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          for (final piece in highlightTitle(chat.title, typed))
            TextSpan(
              text: piece.text,
              style: piece.match
                  ? TextStyle(backgroundColor: theme.attention)
                  : null,
            ),
        ],
      ),
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final tag = project;
    return Semantics(
      selected: selected,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Hover(
              onTap: onTap,
              borderRadius: theme.radii.ctl,
              selected: selected,
              selectedColor: theme.railSelected,
              hoverBackground: theme.railHover,
              pressedBackground: theme.railSelected,
              lift: 0,
              padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _title(theme),
                  const SizedBox(height: 2),
                  // The project tag goes under the status when both do not fit.
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusMark(chat.status, label: label, detail: detail),
                      if (tag != null)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.railLine),
                            borderRadius: BorderRadius.circular(theme.radii.sm),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              tag,
                              style: ts(
                                const TypeSpec(11, 16, 400),
                                theme.railMuted,
                                mono: true,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (bar && selected)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.railInk,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class RailMoreRow extends StatelessWidget {
  const RailMoreRow({
    super.key,
    required this.loading,
    required this.failed,
    required this.onTap,
    this.idle = 'Show older chats',
    this.busy = 'Loading older chats…',
    this.failure = 'Could not load older chats. Try again',
  });

  final bool loading;
  final bool failed;
  final VoidCallback? onTap;

  /// The row's text when it can be pressed, while it loads and after a
  /// failed load.
  final String idle;
  final String busy;
  final String failure;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final label = loading
        ? busy
        : failed
        ? failure
        : idle;
    final enabled = !loading && onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
        child: Hover(
          key: const ValueKey('rail-load-more'),
          onTap: enabled ? onTap : null,
          borderRadius: theme.radii.ctl,
          hoverBackground: theme.railHover,
          pressedBackground: theme.railSelected,
          lift: 0,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            label,
            style: ts(
              theme.typeScale.ui,
              failed ? theme.dangerInk : theme.railMuted,
              weight: 500,
            ),
          ),
        ),
      ),
    );
  }
}

/// The box above the list: a magnifier, the text and, once something is
/// typed, a clear button.
class ChatSearchBox extends StatelessWidget {
  const ChatSearchBox({
    super.key,
    required this.search,
    required this.showKeyHint,
  });

  final ChatSearchController search;
  final bool showKeyHint;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final style = ts(theme.typeScale.ui, theme.railInk, weight: 500);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (search.text.text.isNotEmpty) search.clear();
          search.focus.unfocus();
        },
      },
      child: ListenableBuilder(
        listenable: Listenable.merge([search.text, search.focus]),
        builder: (context, _) {
          final filled = search.text.text.isNotEmpty;
          final on = filled || search.focus.hasFocus;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: search.focus.requestFocus,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: on ? theme.railHover : null,
                borderRadius: theme.radii.ctl,
                border: on ? Border.all(color: theme.railLine) : null,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 32),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      glyphIcon(glyphSearch, size: 16, color: theme.railMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Semantics(
                          label: searchPlaceholder,
                          textField: true,
                          child: Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              if (!filled)
                                IgnorePointer(
                                  child: Text(
                                    searchPlaceholder,
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    style: style.copyWith(
                                      color: theme.railMuted,
                                    ),
                                  ),
                                ),
                              EditableText(
                                key: const ValueKey('chat-search-field'),
                                controller: search.text,
                                focusNode: search.focus,
                                style: style,
                                cursorColor: theme.railInk,
                                backgroundCursorColor: theme.railMuted,
                                selectionColor: theme.accent.withValues(
                                  alpha: .3,
                                ),
                                selectionControls: noteSelectionControls,
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (filled)
                        _ClearButton(onTap: search.clear)
                      else if (showKeyHint)
                        Text(
                          'Ctrl K',
                          style: ts(
                            const TypeSpec(12, 16, 400),
                            theme.railMuted,
                            mono: true,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      button: true,
      label: 'Clear search',
      excludeSemantics: true,
      onTap: onTap,
      child: Hover(
        key: const ValueKey('chat-search-clear'),
        onTap: onTap,
        borderRadius: theme.radii.ctl,
        hoverBackground: theme.railSelected,
        pressedBackground: theme.railSelected,
        lift: 0,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: glyphIcon(glyphClose, size: 14, color: theme.railMuted),
          ),
        ),
      ),
    );
  }
}

/// What the search list says instead of rows: that it is looking, that
/// nothing matches, or why the search failed.
class SearchNote extends StatelessWidget {
  const SearchNote({
    super.key,
    required this.title,
    this.body = '',
    this.action,
    this.onAction,
  });

  final String title;
  final String body;

  /// A button under the text, such as "Try again".
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final label = action;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: ts(theme.typeScale.ui, theme.railInk, weight: 700),
            ),
            if (body.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  body,
                  style: ts(theme.typeScale.ui, theme.railMuted),
                ),
              ),
            if (label != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(
                  button: true,
                  label: label,
                  excludeSemantics: true,
                  onTap: onAction,
                  child: Hover(
                    key: const ValueKey('search-retry'),
                    onTap: onAction,
                    borderRadius: theme.radii.ctl,
                    hoverBackground: theme.railHover,
                    pressedBackground: theme.railSelected,
                    lift: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      label,
                      style: ts(theme.typeScale.ui, theme.railInk, weight: 600),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
