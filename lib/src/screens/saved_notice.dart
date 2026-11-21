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
              glyphIcon(
                glyphCircleCheck,
                size: IconSize.sm,
                color: theme.constructiveInk,
              ),
              const Gap(Space.md),
              Flexible(
                child: Text(
                  'Saved to feedback/$id',
                  style: ts(theme.typeScale.ui, theme.ink),
                ),
              ),
              const Gap(Space.md),
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
