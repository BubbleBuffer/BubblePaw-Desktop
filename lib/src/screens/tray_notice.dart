// The one-time notice after the window first closes to the tray. It waits
// here until the window is shown again.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../settings/settings_widgets.dart';

class TrayNotice extends StatelessWidget {
  const TrayNotice({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        key: const ValueKey('tray-notice'),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.thread),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              glyphIcon(glyphInfo, color: theme.muted),
              const SizedBox(width: 12),
              Text(
                'BubblePaw is still running in the tray',
                style: ts(theme.typeScale.ui, theme.ink),
              ),
              const SizedBox(width: 12),
              TextBtn(
                'Dismiss',
                key: const ValueKey('tray-notice-dismiss'),
                onTap: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
