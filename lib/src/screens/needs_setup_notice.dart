// The notice after a send is refused because no model provider is set up:
// what is missing, and a way to the page where it is set. It stays until
// dismissed.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../settings/settings_widgets.dart';

class NeedsSetupNotice extends StatelessWidget {
  const NeedsSetupNotice({
    super.key,
    required this.onOpenModels,
    required this.onDismiss,
  });

  final VoidCallback onOpenModels;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        key: const ValueKey('needs-setup-notice'),
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
              Flexible(
                child: Text(
                  'No model provider is set up. Add one in Settings > Models.',
                  style: ts(theme.typeScale.ui, theme.ink),
                ),
              ),
              const SizedBox(width: 12),
              TextBtn(
                'Open Models',
                key: const ValueKey('needs-setup-open'),
                onTap: onOpenModels,
              ),
              TextBtn(
                'Dismiss',
                key: const ValueKey('needs-setup-dismiss'),
                onTap: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
