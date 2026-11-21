// "Review diff": the kit's diff view over the workbench, with a way back.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart' show FileDiff;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

class DiffReview extends StatelessWidget {
  const DiffReview({super.key, required this.diff, required this.onClose});

  final FileDiff diff;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return ColoredBox(
      color: theme.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.md,
              Space.lg,
              Space.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    diff.path,
                    key: const ValueKey('diff-path'),
                    overflow: TextOverflow.ellipsis,
                    style: ts(
                      theme.typeScale.ui,
                      theme.ink,
                      weight: Weight.strong,
                    ),
                  ),
                ),
                const Gap(Space.sm),
                Text(
                  '+${diff.added} −${diff.removed}',
                  style: ts(
                    theme.typeScale.uiSmall,
                    theme.muted,
                    mono: true,
                    weight: Weight.regular,
                  ),
                ),
                const Gap(Space.sm),
                TextBtn(
                  'Close',
                  key: const ValueKey('diff-close'),
                  onTap: onClose,
                ),
              ],
            ),
          ),
          HLine(color: theme.seam),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Space.lg),
              child: DiffView(diff),
            ),
          ),
        ],
      ),
    );
  }
}
