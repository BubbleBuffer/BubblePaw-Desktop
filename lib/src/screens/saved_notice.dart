// The confirmation after feedback is saved: where it went, with a way to open
// the folder. It stays until dismissed.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../feedback/glyphs.dart';
import '../settings/settings_widgets.dart';

class SavedNotice extends StatelessWidget {
  const SavedNotice({
    super.key,
    required this.id,
    required this.onOpen,
    required this.onDismiss,
  });

  /// The folder name of the saved report.
  final String id;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        key: const ValueKey('feedback-saved'),
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
              glyphIcon(
                glyphCircleCheck,
                size: 16,
                color: theme.constructiveInk,
              ),
              const SizedBox(width: 12),
              Text(
                'Saved to feedback/$id',
                style: ts(theme.typeScale.ui, theme.ink),
              ),
              const SizedBox(width: 12),
              TextBtn(
                'Open folder',
                key: const ValueKey('feedback-saved-open'),
                onTap: onOpen,
              ),
              TextBtn(
                'Dismiss',
                key: const ValueKey('feedback-saved-dismiss'),
                onTap: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
