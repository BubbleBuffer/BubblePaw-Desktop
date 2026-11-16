// A plain full-pane notice: a state, its cause, and what the person can do.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

class Notice extends StatelessWidget {
  const Notice({
    super.key,
    required this.title,
    required this.message,
    this.actions = const [],
  });

  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return ColoredBox(
      color: theme.canvas,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Widths.sheet),
            child: Semantics(
              liveRegion: true,
              container: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: ts(
                      theme.typeScale.h2,
                      theme.ink,
                      weight: Weight.semibold,
                    ),
                  ),
                  const Gap(Space.sm),
                  Text(message, style: ts(theme.typeScale.body, theme.muted)),
                  if (actions.isNotEmpty) ...[
                    const Gap(Space.lg),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < actions.length; i++) ...[
                          if (i > 0) const Gap(Space.sm),
                          actions[i],
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
