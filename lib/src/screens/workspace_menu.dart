// The rail's workspace menu: recent workspaces and "Open folder…". Drawn as a
// popup under the rail header.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart' show Ico, IconBtn, LucideGlyph, ts;
import 'package:flutter/widgets.dart';

import '../config.dart';
import '../settings/remote_glyphs.dart';
import '../settings/settings_widgets.dart' show glyphIcon;

/// One host in the switcher: this computer (id null) or a saved host.
class HostChoice {
  const HostChoice({
    required this.id,
    required this.name,
    required this.state,
    required this.dot,
    required this.selected,
  });

  /// Null for this computer.
  final String? id;
  final String name;

  /// "Running", "Online · Relay", "Offline".
  final String state;

  /// Whether the dot is lit.
  final bool dot;
  final bool selected;
}

/// What the switcher lists besides workspaces: the hosts, listened to so
/// the answers that arrive after it opened show.
class HostMenu {
  const HostMenu({
    required this.listenable,
    required this.choices,
    required this.onPick,
    required this.onAdd,
  });

  final Listenable listenable;
  final List<HostChoice> Function() choices;

  /// Opens a host; null opens this computer.
  final void Function(String? id) onPick;
  final VoidCallback onAdd;
}

/// Opens the menu over [context]'s navigator. Picking a workspace calls
/// [onPick] with its path; "Open folder…" calls [onOpenFolder]. The menu closes
/// first in both cases.
Future<void> showWorkspaceMenu(
  BuildContext context, {
  required String current,
  required List<String> workspaces,
  required ValueChanged<String> onPick,
  required VoidCallback onOpenFolder,
  HostMenu? hosts,
}) => Navigator.of(context).push<void>(
  RawDialogRoute<void>(
    barrierDismissible: true,
    barrierLabel: 'Close the workspace menu',
    barrierColor: const Color(0x00000000),
    pageBuilder: (context, animation, secondary) => WorkspaceMenu(
      current: current,
      workspaces: workspaces,
      hosts: hosts == null
          ? null
          : HostMenu(
              listenable: hosts.listenable,
              choices: hosts.choices,
              onPick: (id) {
                Navigator.of(context).pop();
                hosts.onPick(id);
              },
              onAdd: () {
                Navigator.of(context).pop();
                hosts.onAdd();
              },
            ),
      onPick: (path) {
        Navigator.of(context).pop();
        onPick(path);
      },
      onOpenFolder: () {
        Navigator.of(context).pop();
        onOpenFolder();
      },
    ),
  ),
);

class WorkspaceMenu extends StatelessWidget {
  const WorkspaceMenu({
    super.key,
    required this.current,
    required this.workspaces,
    required this.onPick,
    required this.onOpenFolder,
    this.hosts,
  });

  /// The hosts group; null for none.
  final HostMenu? hosts;
  final String current;
  final List<String> workspaces;
  final ValueChanged<String> onPick;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final menu = hosts;
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 52, 8, 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 224, maxWidth: 320),
          child: Semantics(
            container: true,
            label: menu == null ? 'Workspaces' : 'Hosts and workspaces',
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.surface,
                border: Border.all(color: theme.seam),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: menu == null
                    ? _body(theme, const [])
                    : ListenableBuilder(
                        listenable: menu.listenable,
                        builder: (context, _) =>
                            _body(theme, menu.choices(), menu: menu),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider(BbTheme theme) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: ColoredBox(color: theme.seam, child: const SizedBox(height: 1)),
  );

  Widget _body(BbTheme theme, List<HostChoice> choices, {HostMenu? menu}) {
    // A saved host shows all of its projects; the workspaces are this
    // computer's.
    final remoteOpen = choices.any((c) => c.id != null && c.selected);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (menu != null) ...[
          for (var i = 0; i < choices.length; i++)
            _Row(
              key: ValueKey('host-menu-item-${choices[i].id ?? 'local'}'),
              title: choices[i].name,
              detail: choices[i].state,
              dot: choices[i].dot,
              selected: choices[i].selected,
              onTap: () => menu.onPick(choices[i].id),
            ),
          _Row(
            key: const ValueKey('host-menu-add'),
            title: 'Add a host',
            glyph: glyphPlus,
            onTap: menu.onAdd,
          ),
          if (!remoteOpen) _divider(theme),
        ],
        if (!remoteOpen) ...[
          for (var i = 0; i < workspaces.length; i++)
            _Row(
              key: ValueKey('workspace-menu-item-$i'),
              title: workspaceFolderName(workspaces[i]),
              detail: workspaces[i],
              selected: workspaces[i] == current,
              onTap: () => onPick(workspaces[i]),
            ),
          if (workspaces.isNotEmpty) _divider(theme),
          _Row(
            key: const ValueKey('workspace-menu-open-folder'),
            title: 'Open folder…',
            onTap: onOpenFolder,
          ),
        ],
      ],
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    super.key,
    required this.title,
    required this.onTap,
    this.detail,
    this.selected = false,
    this.dot,
    this.glyph,
    this.tall = false,
  });

  /// A touch-sized row (the phone's sheet).
  final bool tall;

  /// A status dot before the title: lit or not; null for none.
  final bool? dot;
  final LucideGlyph? glyph;
  final String title;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.detail == null
          ? widget.title
          : '${widget.title}, ${widget.detail}',
      excludeSemantics: true,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: ColoredBox(
            color: _hover ? theme.railHover : const Color(0x00000000),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.tall ? 16 : 12,
                vertical: widget.tall ? 10 : 6,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: widget.tall ? 28 : 0),
                child: Row(
                children: [
                  if (widget.glyph != null) ...[
                    glyphIcon(widget.glyph!, size: 15, color: theme.muted),
                    const SizedBox(width: 8),
                  ],
                  if (widget.dot != null) ...[
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: widget.dot!
                            ? theme.constructiveInk
                            : theme.faint,
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox(width: 8, height: 8),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ts(
                            theme.typeScale.ui,
                            theme.ink,
                            weight: widget.selected ? 700 : 500,
                          ),
                        ),
                        if (widget.detail != null)
                          Text(
                            widget.detail!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ts(theme.typeScale.uiSmall, theme.faint),
                          ),
                      ],
                    ),
                  ),
                  if (widget.selected)
                    Text(
                      'Open',
                      style: ts(theme.typeScale.uiSmall, theme.muted),
                    ),
                ],
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The phone's host switcher: a sheet from the bottom with the saved hosts
/// and "Add a host". Picking a host or adding one closes it first.
Future<void> showHostSheet(BuildContext context, {required HostMenu hosts}) =>
    Navigator.of(context).push<void>(
      RawDialogRoute<void>(
        barrierDismissible: true,
        barrierLabel: 'Close the host menu',
        barrierColor: const Color(0x66000000),
        pageBuilder: (context, animation, secondary) => HostSheet(
          hosts: HostMenu(
            listenable: hosts.listenable,
            choices: hosts.choices,
            onPick: (id) {
              Navigator.of(context).pop();
              hosts.onPick(id);
            },
            onAdd: () {
              Navigator.of(context).pop();
              hosts.onAdd();
            },
          ),
        ),
      ),
    );

class HostSheet extends StatelessWidget {
  const HostSheet({super.key, required this.hosts});

  final HostMenu hosts;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final radius = BorderRadius.vertical(top: Radius.circular(theme.radii.sheet));
    return Align(
      alignment: Alignment.bottomCenter,
      child: Semantics(
        container: true,
        scopesRoute: true,
        namesRoute: true,
        label: 'Hosts',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: radius,
            border: Border(top: BorderSide(color: theme.seam)),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 8,
            ),
            child: ListenableBuilder(
              listenable: hosts.listenable,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(
                              'Hosts',
                              style: ts(
                                theme.typeScale.h2,
                                theme.ink,
                                weight: 600,
                              ),
                            ),
                          ),
                        ),
                        IconBtn(
                          Ico.close,
                          key: const ValueKey('host-sheet-close'),
                          size: 40,
                          semanticLabel: 'Close',
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                      ],
                    ),
                  ),
                  for (final choice in hosts.choices())
                    _Row(
                      key: ValueKey('host-menu-item-${choice.id ?? 'local'}'),
                      title: choice.name,
                      detail: choice.state,
                      dot: choice.dot,
                      selected: choice.selected,
                      tall: true,
                      onTap: () => hosts.onPick(choice.id),
                    ),
                  _Row(
                    key: const ValueKey('host-menu-add'),
                    title: 'Add a host',
                    glyph: glyphPlus,
                    tall: true,
                    onTap: hosts.onAdd,
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
