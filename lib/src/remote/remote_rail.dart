// The rail of a saved host: "Needs you" first, then the host's projects, each
// a group that opens and closes, with a plus that starts a chat in it. The
// kit's SessionRail has fixed Today and Earlier groups, so this is the app's
// own rail, built from the kit's rows, status marks and layout scope.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart' show ChatSummary;
import 'package:bb_ui/bb_ui.dart'
    show Hover, Ico, LucideGlyph, PrimaryButton, TypeSpec, ts;
import 'package:flutter/widgets.dart';

import '../feedback/glyphs.dart' show glyphChevronDown;
import '../settings/remote_glyphs.dart';
import '../settings/settings_widgets.dart' show glyphIcon;
import 'project_groups.dart';

/// The rail's contents. [groups] and [needsYou] come from the chat list the
/// workbench holds; [state] says which groups are open.
class RemoteRail extends StatelessWidget {
  const RemoteRail({
    super.key,
    required this.hostName,
    required this.groups,
    required this.needsYou,
    required this.projectOf,
    required this.state,
    this.selectedId,
    this.now,
    this.onSelect,
    this.onNewChat,
    this.onNewChatIn,
    this.onSwitchHost,
    this.onSettings,
    this.hasMore = false,
    this.loadingMore = false,
    this.loadMoreFailed = false,
    this.onLoadMore,
  });

  final String hostName;
  final List<ProjectGroup> groups;
  final List<ChatSummary> needsYou;

  /// The project name shown on a "Needs you" row.
  final String Function(ChatSummary chat) projectOf;
  final ProjectRailState state;
  final String? selectedId;
  final DateTime? now;
  final ValueChanged<ChatSummary>? onSelect;
  final VoidCallback? onNewChat;

  /// Starts a chat in the project with this path (empty for "No project").
  final ValueChanged<ProjectGroup>? onNewChatIn;
  final VoidCallback? onSwitchHost;
  final VoidCallback? onSettings;
  final bool hasMore;
  final bool loadingMore;
  final bool loadMoreFailed;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final scope = RailScope.maybeOf(context);
    final clock = now ?? DateTime.now();
    void select(ChatSummary chat) {
      onSelect?.call(chat);
      if (scope != null && scope.sizeClass.isCompact) {
        scope.controller.open = false;
      }
    }

    return Semantics(
      container: true,
      label: 'Chats of $hostName',
      child: ColoredBox(
        color: theme.rail,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: _HostButton(name: hostName, onTap: onSwitchHost),
                  ),
                  const SizedBox(width: 4),
                  _RailIconButton(
                    key: const ValueKey('remote-rail-hide'),
                    glyph: glyphPanelLeftClose,
                    label: 'Hide sidebar',
                    onTap: scope == null
                        ? null
                        : () => scope.controller.hide(scope.sizeClass),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: KeyedSubtree(
                key: const ValueKey('remote-new-chat'),
                child: PrimaryButton(
                  label: 'New chat',
                  height: 36,
                  icon: Ico.compose,
                  onTap: onNewChat ?? () {},
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  if (needsYou.isNotEmpty) ...[
                    _Label('Needs you', count: needsYou.length),
                    for (final chat in needsYou)
                      _ChatRow(
                        key: ValueKey('needs-row-${chat.id}'),
                        chat: chat,
                        detail: railDetail(chat, clock),
                        project: projectOf(chat),
                        selected: chat.id == selectedId,
                        onTap: () => select(chat),
                      ),
                  ],
                  const _Label('Projects'),
                  for (final group in groups) ...[
                    _GroupHead(
                      key: ValueKey('project-${group.key}'),
                      group: group,
                      open: state.isOpen(group.key),
                      now: clock,
                      onToggle: () => state.toggle(group.key),
                      onNewChat: onNewChatIn == null
                          ? null
                          : () => onNewChatIn!(group),
                    ),
                    if (state.isOpen(group.key))
                      for (final chat in group.chats)
                        SessionRow(
                          key: ValueKey('rail-row-${chat.id}'),
                          chat: chat,
                          detail: railDetail(chat, clock),
                          selected: chat.id == selectedId,
                          onTap: () => select(chat),
                        ),
                  ],
                  if (hasMore)
                    _MoreRow(
                      loading: loadingMore,
                      failed: loadMoreFailed,
                      onTap: onLoadMore,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: theme.railLine)),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _SettingsLink(onTap: onSettings),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.count});

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

/// A chat of the "Needs you" list: the title, the status and the project's
/// name.
class _ChatRow extends StatelessWidget {
  const _ChatRow({
    super.key,
    required this.chat,
    required this.detail,
    required this.project,
    required this.selected,
    required this.onTap,
  });

  final ChatSummary chat;
  final String? detail;
  final String project;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      selected: selected,
      child: Padding(
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
              Text(
                chat.title,
                style: ts(
                  theme.typeScale.ui,
                  theme.railInk.withValues(alpha: selected ? 1 : .86),
                  weight: selected ? 700 : 500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Flexible(child: StatusMark(chat.status, detail: detail)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.railLine),
                        borderRadius: BorderRadius.circular(theme.radii.sm),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          project,
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
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A project: the toggle row (chevron, name, "N running · N waiting" or the
/// last activity) and the plus that starts a chat in it.
class _GroupHead extends StatelessWidget {
  const _GroupHead({
    super.key,
    required this.group,
    required this.open,
    required this.now,
    required this.onToggle,
    required this.onNewChat,
  });

  final ProjectGroup group;
  final bool open;
  final DateTime now;
  final VoidCallback onToggle;
  final VoidCallback? onNewChat;

  String _meta() {
    if (!group.active) return chatAge(group.latest, now);
    return [
      if (group.running > 0) '${group.running} running',
      if (group.waiting > 0) '${group.waiting} waiting',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final meta = _meta();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              expanded: open,
              label: group.name,
              excludeSemantics: true,
              onTap: onToggle,
              child: Hover(
                key: ValueKey('project-toggle-${group.key}'),
                onTap: onToggle,
                borderRadius: theme.radii.ctl,
                hoverBackground: theme.railHover,
                pressedBackground: theme.railSelected,
                lift: 0,
                padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          glyphIcon(
                            open ? glyphChevronDown : glyphChevronRight,
                            size: 14,
                            color: theme.railMuted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              group.name,
                              style: ts(
                                theme.typeScale.ui,
                                theme.railInk,
                                weight: 700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (meta.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 20),
                          child: Text(
                            meta,
                            style: ts(
                              const TypeSpec(11.5, 16, 600),
                              group.active
                                  ? theme.constructiveInk
                                  : theme.railMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _RailIconButton(
            key: ValueKey('project-new-chat-${group.key}'),
            glyph: glyphPlus,
            label: 'New chat in ${group.name}',
            onTap: onNewChat,
          ),
        ],
      ),
    );
  }
}

class _RailIconButton extends StatelessWidget {
  const _RailIconButton({
    super.key,
    required this.glyph,
    required this.label,
    required this.onTap,
  });

  final LucideGlyph glyph;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Hover(
        onTap: onTap,
        borderRadius: theme.radii.ctl,
        hoverBackground: theme.railHover,
        pressedBackground: theme.railSelected,
        lift: 0,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: glyphIcon(glyph, size: 16, color: theme.railInk),
          ),
        ),
      ),
    );
  }
}

class _HostButton extends StatelessWidget {
  const _HostButton({required this.name, required this.onTap});

  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      button: true,
      label: 'Switch host, $name',
      excludeSemantics: true,
      onTap: onTap,
      child: Hover(
        key: const ValueKey('rail-workspace'),
        onTap: onTap,
        borderRadius: theme.radii.ctl,
        hoverBackground: theme.railHover,
        pressedBackground: theme.railSelected,
        lift: 0,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              glyphIcon(glyphMonitor, size: 16, color: theme.railInk),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: theme.constructiveInk,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox(width: 7, height: 7),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Online',
                          style: ts(
                            const TypeSpec(11.5, 14, 600),
                            theme.constructiveInk,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      name,
                      style: ts(theme.typeScale.ui, theme.railInk, weight: 700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              glyphIcon(glyphChevronDown, size: 14, color: theme.railMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({
    required this.loading,
    required this.failed,
    required this.onTap,
  });

  final bool loading;
  final bool failed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final label = loading
        ? 'Loading older chats…'
        : failed
        ? 'Could not load older chats. Try again'
        : 'Show older chats';
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

class _SettingsLink extends StatelessWidget {
  const _SettingsLink({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      button: true,
      label: 'Settings',
      excludeSemantics: true,
      onTap: onTap,
      child: Hover(
        key: const ValueKey('rail-settings'),
        onTap: onTap,
        borderRadius: theme.radii.ctl,
        hoverBackground: theme.railHover,
        pressedBackground: theme.railSelected,
        lift: 0,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          height: 28,
          child: Row(
            children: [
              glyphIcon(glyphSettings, size: 16, color: theme.railMuted),
              const SizedBox(width: 10),
              Text(
                'Settings',
                style: ts(theme.typeScale.ui, theme.railMuted, weight: 500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
