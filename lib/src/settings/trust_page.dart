// Settings > Workspace trust: the workspaces the user trusts, each with Revoke
// (`workspace_trust.list` and `.revoke`). The list follows the host's
// `workspace_trust` state event through the controller.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../core/workspace_trust.dart';
import 'action_widgets.dart';
import 'settings_widgets.dart';

class TrustPage extends StatelessWidget {
  const TrustPage({super.key, required this.trust, this.onBack});

  /// Null while the host is not running.
  final WorkspaceTrustController? trust;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final controller = trust;
    return SettingsPage(
      title: 'Workspace trust',
      onBack: onBack,
      backKey: const ValueKey('settings-page-back'),
      children: [
        const SettingsHeading('Trusted workspaces'),
        if (controller == null)
          const _Status('Host not running', key: ValueKey('trust-no-host'))
        else
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => _List(controller),
          ),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Text(
      text,
      style: ts(theme.typeScale.ui, theme.muted, weight: Weight.regular),
    );
  }
}

class _List extends StatelessWidget {
  const _List(this.controller);

  final WorkspaceTrustController controller;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final rows = controller.trusted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.listError != null)
          NoticeBox(
            key: const ValueKey('trust-list-error'),
            tone: NoticeTone.danger,
            trailing: ActionButton(
              key: const ValueKey('trust-retry'),
              label: 'Try again',
              onTap: controller.refresh,
            ),
            child: Text(controller.listError!),
          )
        else if (rows == null)
          const _Status('Loading', key: ValueKey('trust-loading'))
        else if (rows.isEmpty)
          const _Status('None trusted', key: ValueKey('trust-empty'))
        else
          for (final row in rows)
            Padding(
              key: ValueKey('trust-row-${row.path}'),
              padding: const EdgeInsets.symmetric(vertical: Space.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.path,
                          style: ts(
                            theme.typeScale.ui,
                            theme.ink,
                            mono: true,
                            weight: Weight.regular,
                          ),
                        ),
                        if (row.day.isNotEmpty)
                          Text(
                            row.day,
                            style: ts(
                              theme.typeScale.uiSmall,
                              theme.faint,
                              weight: Weight.regular,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Gap(Space.lg),
                  Opacity(
                    opacity: controller.busy(row.path) ? Alpha.muted : 1,
                    child: ActionButton(
                      key: ValueKey('trust-revoke-${row.path}'),
                      label: 'Revoke',
                      onTap: () {
                        if (!controller.busy(row.path)) {
                          controller.revoke(row.path);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
        if (controller.error != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.md),
            child: Semantics(
              liveRegion: true,
              child: Text(
                controller.error!,
                key: const ValueKey('trust-error'),
                style: ts(theme.typeScale.ui, theme.dangerInk),
              ),
            ),
          ),
      ],
    );
  }
}
