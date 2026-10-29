// The rail's workspace menu: recent workspaces and "Open folder…". Drawn as a
// popup under the rail header.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart' show ts;
import 'package:flutter/widgets.dart';

import '../config.dart';

/// Opens the menu over [context]'s navigator. Picking a workspace calls
/// [onPick] with its path; "Open folder…" calls [onOpenFolder]. The menu closes
/// first in both cases.
Future<void> showWorkspaceMenu(
  BuildContext context, {
  required String current,
  required List<String> workspaces,
  required ValueChanged<String> onPick,
  required VoidCallback onOpenFolder,
}) => Navigator.of(context).push<void>(
  RawDialogRoute<void>(
    barrierDismissible: true,
    barrierLabel: 'Close the workspace menu',
    barrierColor: const Color(0x00000000),
    pageBuilder: (context, animation, secondary) => WorkspaceMenu(
      current: current,
      workspaces: workspaces,
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
  });

  final String current;
  final List<String> workspaces;
  final ValueChanged<String> onPick;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 52, 8, 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 224, maxWidth: 320),
          child: Semantics(
            container: true,
            label: 'Workspaces',
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.surface,
                border: Border.all(color: theme.seam),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < workspaces.length; i++)
                      _Row(
                        key: ValueKey('workspace-menu-item-$i'),
                        title: workspaceFolderName(workspaces[i]),
                        detail: workspaces[i],
                        selected: workspaces[i] == current,
                        onTap: () => onPick(workspaces[i]),
                      ),
                    if (workspaces.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: ColoredBox(
                          color: theme.seam,
                          child: const SizedBox(height: 1),
                        ),
                      ),
                    _Row(
                      key: const ValueKey('workspace-menu-open-folder'),
                      title: 'Open folder…',
                      onTap: onOpenFolder,
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

class _Row extends StatefulWidget {
  const _Row({
    super.key,
    required this.title,
    required this.onTap,
    this.detail,
    this.selected = false,
  });

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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
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
    );
  }
}
