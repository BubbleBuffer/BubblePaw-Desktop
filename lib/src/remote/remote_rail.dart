// The rail of a saved host: "Needs you" first, then the host's projects, each
// a group that opens and closes, with a plus that starts a chat in it. The
// kit's SessionRail has fixed Today and Earlier groups, so this is the app's
// own rail, built from the kit's rows, status marks and layout scope.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart' show ChatSummary;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../app_tokens.dart';
import '../feedback/glyphs.dart' show glyphCheck, glyphChevronDown;
import '../search/chat_search.dart' show ChatSearchController;
import '../search/search_widgets.dart';
import '../settings/remote_glyphs.dart';
import '../settings/settings_widgets.dart' show glyphIcon;
import 'project_groups.dart';
import 'remote_chats.dart' show RemoteWait;

/// A project the new chat can start in: its path on the host and its name.
typedef PickableProject = ({String path, String name});

/// The picker's first entry: the host decides the project.
const hostDefaultName = 'Host default';

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
    this.waitingOf,
    this.search,
    this.pathOf,
    this.showKeyHint = false,
    this.projects = const [],
    this.pickedPath,
    this.pickerOpen = false,
    this.onTogglePicker,
    this.onPick,
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

  /// What a chat waits for; null (or a null answer) for a host that does
  /// not say, which reads "Waiting for you".
  final RemoteWait? Function(String chatId)? waitingOf;

  /// The search box above the list; null for a host that cannot search chat
  /// titles, which has no box. While a query is typed the list is the host's
  /// answer to it.
  final ChatSearchController? search;

  /// A chat's project path on the host, to group the search results.
  final String? Function(String chatId)? pathOf;

  /// The box names its shortcut (Ctrl K); the phone has none.
  final bool showKeyHint;

  /// The host's known projects, for the picker beside New chat.
  final List<PickableProject> projects;

  /// The project the next New chat starts in; null is the host's default.
  final String? pickedPath;
  final bool pickerOpen;
  final VoidCallback? onTogglePicker;

  /// Picks a project by path; null picks the host's default.
  final ValueChanged<String?>? onPick;
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
        child: Stack(
          children: [
            Positioned.fill(
              child: _column(context, theme, scope, clock, select),
            ),
            if (pickerOpen) ..._picker(theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _picker(BbTheme theme) => [
    Positioned.fill(
      child: GestureDetector(
        key: const ValueKey('project-picker-scrim'),
        behavior: HitTestBehavior.opaque,
        onTap: onTogglePicker,
      ),
    ),
    Positioned(
      top: RailSizes.pickerTop,
      right: Space.sm,
      width: RailSizes.pickerWidth,
      child: _PickerMenu(
        projects: projects,
        pickedPath: pickedPath,
        onPick: (path) => onPick?.call(path),
      ),
    ),
  ];

  Widget _column(
    BuildContext context,
    BbTheme theme,
    RailScope? scope,
    DateTime clock,
    void Function(ChatSummary) select,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.sm,
            Space.md,
            Space.sm,
            Space.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: _HostButton(name: hostName, onTap: onSwitchHost),
              ),
              const Gap(Space.xxs),
              _RailIconButton(
                key: const ValueKey('remote-rail-hide'),
                glyph: glyphPanelLeftClose,
                label: 'Hide the rail',
                onTap: scope == null
                    ? null
                    : () => scope.controller.hide(scope.sizeClass),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.sm, 0, Space.sm, Space.xs),
          // The chip gives way before the button does: 112 wide at most.
          child: LayoutBuilder(
            builder: (context, box) => Row(
              children: [
                Expanded(
                  child: KeyedSubtree(
                    key: const ValueKey('remote-new-chat'),
                    child: PrimaryButton(
                      label: 'New chat',
                      size: ControlSize.lg,
                      icon: Ico.compose,
                      onTap: onNewChat ?? () {},
                    ),
                  ),
                ),
                const Gap(Space.xs),
                _PickerChip(
                  name: _pickedName(),
                  open: pickerOpen,
                  width: (box.maxWidth - RailSizes.newChatMin - Space.xs).clamp(
                    RailSizes.chipMin,
                    RailSizes.chipMax,
                  ),
                  onTap: onTogglePicker,
                ),
              ],
            ),
          ),
        ),
        if (search != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.sm, 0, Space.sm, Space.xs),
            child: ChatSearchBox(search: search!, showKeyHint: showKeyHint),
          ),
        Expanded(
          child: search == null
              ? _list(clock, select)
              : ListenableBuilder(
                  listenable: search!,
                  builder: (context, _) => search!.active
                      ? ChatSearchResults(
                          search: search!,
                          hostName: hostName,
                          pathOf: pathOf,
                          selectedId: selectedId,
                          now: clock,
                          labelOf: (id) => waitingOf?.call(id)?.label,
                          onSelect: select,
                        )
                      : _list(clock, select),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.sm, 0, Space.sm, Space.md),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: theme.railLine)),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: _SettingsLink(onTap: onSettings),
            ),
          ),
        ),
      ],
    );
  }

  /// The chats of the open host: Needs you, then the projects.
  Widget _list(DateTime clock, void Function(ChatSummary) select) {
    return ListView(
      padding: const EdgeInsets.only(bottom: Space.sm),
      children: [
        if (needsYou.isNotEmpty) ...[
          RailLabel('Needs you', count: needsYou.length),
          for (final chat in needsYou)
            RailChatRow(
              key: ValueKey('needs-row-${chat.id}'),
              chat: chat,
              detail: railDetail(chat, clock),
              label: waitingOf?.call(chat.id)?.label,
              project: projectOf(chat),
              selected: chat.id == selectedId,
              onTap: () => select(chat),
            ),
        ],
        const RailLabel('Projects'),
        for (final group in groups) ...[
          _GroupHead(
            key: ValueKey('project-${group.key}'),
            group: group,
            open: state.isOpen(group.key),
            now: clock,
            onToggle: () => state.toggle(group.key),
            onNewChat: onNewChatIn == null ? null : () => onNewChatIn!(group),
          ),
          if (state.isOpen(group.key))
            for (final chat in group.chats)
              RailChatRow(
                key: ValueKey('rail-row-${chat.id}'),
                chat: chat,
                detail: railDetail(chat, clock),
                label: waitingOf?.call(chat.id)?.label,
                selected: chat.id == selectedId,
                bar: true,
                onTap: () => select(chat),
              ),
        ],
        if (hasMore)
          RailMoreRow(
            loading: loadingMore,
            failed: loadMoreFailed,
            onTap: onLoadMore,
          ),
      ],
    );
  }

  String _pickedName() {
    for (final project in projects) {
      if (project.path == pickedPath) return project.name;
    }
    return hostDefaultName;
  }
}

/// The chip beside New chat: the project the next chat starts in.
class _PickerChip extends StatelessWidget {
  const _PickerChip({
    required this.name,
    required this.open,
    required this.width,
    required this.onTap,
  });

  final double width;
  final String name;
  final bool open;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      button: true,
      expanded: open,
      label: 'Project for the new chat: $name',
      excludeSemantics: true,
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: ControlSize.lg.height,
        child: Hover(
          key: const ValueKey('project-picker'),
          onTap: onTap,
          borderRadius: theme.radii.ctl,
          hoverBackground: theme.railHover,
          pressedBackground: theme.railSelected,
          lift: 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: theme.railLine),
              borderRadius: theme.radii.ctl,
              color: open ? theme.railSelected : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      // "Host default" does not fit the chip.
                      name == hostDefaultName ? 'Default' : name,
                      style: ts(
                        theme.typeScale.uiSmall,
                        theme.railInk,
                        mono: true,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Gap(Space.xxs),
                  glyphIcon(
                    glyphChevronDown,
                    size: IconSize.xs,
                    color: theme.railMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Project for the new chat": the host default, then the host's known
/// projects by name, the picked one checked.
class _PickerMenu extends StatelessWidget {
  const _PickerMenu({
    required this.projects,
    required this.pickedPath,
    required this.onPick,
  });

  final List<PickableProject> projects;
  final String? pickedPath;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      container: true,
      label: 'Project for the new chat',
      child: DecoratedBox(
        key: const ValueKey('project-picker-menu'),
        decoration: BoxDecoration(
          color: theme.surface,
          border: Border.all(color: theme.seam),
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: RailSizes.pickerMaxHeight,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: Space.xxs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PickerItem(
                  key: const ValueKey('project-pick-default'),
                  name: hostDefaultName,
                  checked: pickedPath == null,
                  onTap: () => onPick(null),
                ),
                for (final project in projects)
                  _PickerItem(
                    key: ValueKey('project-pick-${project.path}'),
                    name: project.name,
                    checked: project.path == pickedPath,
                    onTap: () => onPick(project.path),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerItem extends StatelessWidget {
  const _PickerItem({
    super.key,
    required this.name,
    required this.checked,
    required this.onTap,
  });

  final String name;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: checked,
      label: name,
      excludeSemantics: true,
      onTap: onTap,
      child: Hover(
        onTap: onTap,
        borderRadius: BorderRadius.zero,
        hoverBackground: theme.railHover,
        pressedBackground: theme.railSelected,
        lift: 0,
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.md, 0),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: ControlSize.lg.height),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: ts(theme.typeScale.uiSmall, theme.railInk, mono: true),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (checked)
                glyphIcon(glyphCheck, size: IconSize.sm, color: theme.railInk),
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
      padding: const EdgeInsets.fromLTRB(Space.sm, 0, Space.xxs, 0),
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
                padding: const EdgeInsets.fromLTRB(
                  Space.sm,
                  Space.xxs,
                  Space.xs,
                  Space.xxs,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: ControlSize.md.height),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          glyphIcon(
                            open ? glyphChevronDown : glyphChevronRight,
                            size: IconSize.xs,
                            color: theme.railMuted,
                          ),
                          const Gap(Space.xs),
                          Expanded(
                            child: Text(
                              group.name,
                              style: ts(
                                theme.typeScale.ui,
                                theme.railInk,
                                weight: Weight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (meta.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: Space.xl),
                          child: Text(
                            meta,
                            style: ts(
                              theme.typeScale.uiSmall,
                              group.active
                                  ? theme.constructiveInk
                                  : theme.railMuted,
                              weight: Weight.semibold,
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
        child: SizedBox.square(
          dimension: ControlSize.md.height,
          child: Center(
            child: glyphIcon(glyph, size: IconSize.sm, color: theme.railInk),
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
        padding: const EdgeInsets.symmetric(horizontal: Space.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: RailSizes.hostRow),
          child: Row(
            children: [
              glyphIcon(glyphMonitor, size: IconSize.sm, color: theme.railInk),
              const Gap(Space.sm),
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
                          child: const SizedBox.square(
                            dimension: RailSizes.onlineDot,
                          ),
                        ),
                        const Gap(Space.xs),
                        Text(
                          'Online',
                          style: ts(
                            theme.typeScale.uiSmall,
                            theme.constructiveInk,
                            weight: Weight.semibold,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      name,
                      style: ts(
                        theme.typeScale.ui,
                        theme.railInk,
                        weight: Weight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Gap(Space.sm),
              glyphIcon(
                glyphChevronDown,
                size: IconSize.xs,
                color: theme.railMuted,
              ),
            ],
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
        padding: const EdgeInsets.symmetric(horizontal: Space.sm),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: ControlSize.sm.height),
          child: Row(
            children: [
              glyphIcon(
                glyphSettings,
                size: IconSize.sm,
                color: theme.railMuted,
              ),
              const Gap(Space.md),
              Text(
                'Settings',
                style: ts(
                  theme.typeScale.ui,
                  theme.railMuted,
                  weight: Weight.medium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
