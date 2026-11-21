// The notice that says a saved host could not be opened, or stopped
// answering, and that this computer is the one open.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../settings/settings_widgets.dart';

class HostOpenNotice extends StatelessWidget {
  const HostOpenNotice({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      liveRegion: true,
      container: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Widths.sheet),
        child: DecoratedBox(
          key: const ValueKey('host-open-notice'),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: theme.thread),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.sm,
              Space.sm,
              Space.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                glyphIcon(glyphInfo, color: theme.muted),
                const Gap(Space.md),
                Flexible(
                  child: Text(
                    message,
                    style: ts(theme.typeScale.ui, theme.ink),
                  ),
                ),
                const Gap(Space.md),
                TextBtn(
                  'Dismiss',
                  key: const ValueKey('host-open-dismiss'),
                  onTap: onDismiss,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
