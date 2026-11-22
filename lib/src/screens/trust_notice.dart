// The prompt in the chat while the host skips a workspace's project config
// for want of trust: the folder, Trust and Not now. Not now only closes it.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../core/workspace_trust.dart';
import '../settings/action_widgets.dart';
import '../settings/remote_glyphs.dart' show glyphShieldCheck;
import '../settings/settings_widgets.dart';

class TrustNotice extends StatelessWidget {
  const TrustNotice({
    super.key,
    required this.workspace,
    required this.onTrust,
    required this.onDismiss,
    this.busy = false,
    this.error,
  });

  final UntrustedWorkspace workspace;
  final VoidCallback onTrust;
  final VoidCallback onDismiss;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        key: const ValueKey('trust-notice'),
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
              glyphIcon(glyphShieldCheck, color: theme.muted),
              const Gap(Space.md),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trust ${workspace.name}?',
                      key: const ValueKey('trust-notice-name'),
                      style: ts(
                        theme.typeScale.ui,
                        theme.ink,
                        weight: Weight.strong,
                      ),
                    ),
                    Text(
                      workspace.path,
                      style: ts(
                        theme.typeScale.uiSmall,
                        theme.muted,
                        mono: true,
                        weight: Weight.regular,
                      ),
                    ),
                    if (error != null)
                      Text(
                        error!,
                        key: const ValueKey('trust-notice-error'),
                        style: ts(theme.typeScale.uiSmall, theme.dangerInk),
                      ),
                  ],
                ),
              ),
              const Gap(Space.md),
              Opacity(
                opacity: busy ? Alpha.muted : 1,
                child: ActionButton(
                  key: const ValueKey('trust-notice-trust'),
                  label: 'Trust',
                  kind: ActionKind.primary,
                  onTap: busy ? () {} : onTrust,
                ),
              ),
              TextBtn(
                'Not now',
                key: const ValueKey('trust-notice-dismiss'),
                onTap: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
