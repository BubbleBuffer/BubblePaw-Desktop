// The update dialog: an offered version, its download, the step that
// installs it and what went wrong. It draws the state of an
// [UpdateController] over the app.

import 'dart:async';

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../platform/releases.dart';
import '../preferences.dart';
import '../settings/action_widgets.dart';
import '../settings/settings_widgets.dart';
import '../updates/update_controller.dart';
import '../versions.dart';

class UpdateDialog extends StatelessWidget {
  const UpdateDialog({
    super.key,
    required this.updates,
    required this.services,
  });

  final UpdateController updates;
  final PlatformServices services;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final phase = updates.phase;
    final manifest = updates.offered;
    if (manifest == null) return const SizedBox.shrink();
    final spec = switch (phase) {
      UpdateDownloading() => _downloading(context, phase),
      UpdateReady() => _ready(context, phase),
      UpdateFailed() => _failed(context, phase),
      _ => _available(context),
    };
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (phase is UpdateDownloading) return;
          updates.later();
        },
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: theme.colors.overlay)),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: Widths.sheet),
                  child: Semantics(
                    scopesRoute: true,
                    namesRoute: true,
                    explicitChildNodes: true,
                    label: spec.title,
                    child: DecoratedBox(
                      key: const ValueKey('update-dialog'),
                      decoration: BoxDecoration(
                        color: theme.surface,
                        borderRadius: BorderRadius.circular(Radii.sheet),
                        border: Border.all(color: theme.thread),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(Space.xl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Image.asset(
                                  'assets/icon/png/icon-128.png',
                                  width: Sizes.tile,
                                  height: Sizes.tile,
                                  excludeFromSemantics: true,
                                  errorBuilder: (_, _, _) =>
                                      const SizedBox.square(
                                        dimension: Sizes.tile,
                                      ),
                                ),
                                const Gap(Space.md),
                                Expanded(
                                  child: Semantics(
                                    header: true,
                                    child: Text(
                                      spec.title,
                                      key: const ValueKey('update-title'),
                                      style: ts(
                                        theme.typeScale.h2,
                                        theme.ink,
                                        weight: Weight.strong,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Gap(Space.lg),
                            ...spec.body,
                            const Gap(Space.xl),
                            Row(
                              children: [
                                if (spec.leading != null) spec.leading!,
                                const Spacer(),
                                for (
                                  var i = 0;
                                  i < spec.actions.length;
                                  i++
                                ) ...[
                                  if (i > 0) const Gap(Space.sm),
                                  spec.actions[i],
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _hint(BuildContext context) => ts(
    context.bb.typeScale.uiSmall,
    context.bb.muted,
    weight: Weight.regular,
  );

  _Spec _available(BuildContext context) {
    final theme = context.bb;
    final manifest = updates.offered!;
    final channel = manifest.channel == UpdateChannel.nightly
        ? 'Nightly'
        : 'Stable';
    final notes = manifest.notesUrl;
    return _Spec(
      title: 'BubblePaw ${manifest.version} is available',
      body: [
        Text(
          'You have $buildVersion. Channel: $channel.',
          style: ts(theme.typeScale.body, theme.ink),
        ),
        if (notes != null) ...[
          const Gap(Space.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: LinkButton(
              key: const ValueKey('update-notes'),
              label: 'Release notes',
              onTap: () => unawaited(services.open(notes)),
            ),
          ),
        ],
      ],
      leading: ActionButton(
        key: const ValueKey('update-skip'),
        label: 'Skip this version',
        kind: ActionKind.quiet,
        onTap: () => unawaited(updates.skip()),
      ),
      actions: [
        ActionButton(
          key: const ValueKey('update-later'),
          label: 'Later',
          onTap: updates.later,
        ),
        ActionButton(
          key: const ValueKey('update-download'),
          label: updates.canInstall ? 'Download and install' : 'Download',
          kind: ActionKind.primary,
          glyph: glyphDownload,
          onTap: () => unawaited(updates.download()),
        ),
      ],
    );
  }

  _Spec _downloading(BuildContext context, UpdateDownloading phase) {
    final theme = context.bb;
    final percent = '${(phase.fraction * 100).round()}%';
    return _Spec(
      title: 'Downloading BubblePaw ${phase.manifest.version}',
      body: [
        ProgressLine(value: phase.fraction, label: 'Download progress'),
        const Gap(Space.xs),
        Row(
          children: [
            Expanded(
              child: Text(
                megabytes(phase.received, phase.total),
                key: const ValueKey('update-progress'),
                style: ts(theme.typeScale.ui, theme.ink),
              ),
            ),
            Text(
              percent,
              style: ts(
                theme.typeScale.ui,
                theme.muted,
                weight: Weight.regular,
              ),
            ),
          ],
        ),
        const Gap(Space.md),
        Text(
          updates.canInstall
              ? 'The installer runs only after the download finishes and its '
                    'checksum matches.'
              : 'The file is kept only when its checksum matches.',
          style: _hint(context),
        ),
      ],
      actions: [
        ActionButton(
          key: const ValueKey('update-cancel'),
          label: 'Cancel',
          onTap: updates.cancel,
        ),
      ],
    );
  }

  _Spec _ready(BuildContext context, UpdateReady phase) {
    final theme = context.bb;
    final later = ActionButton(
      key: const ValueKey('update-later'),
      label: 'Later',
      onTap: updates.later,
    );
    if (!updates.canInstall) {
      return _Spec(
        title: 'BubblePaw ${phase.manifest.version} is downloaded',
        body: [
          const NoticeBox(
            tone: NoticeTone.good,
            child: Text('The file is downloaded and its checksum matches.'),
          ),
          const Gap(Space.md),
          Text('Saved to', style: _hint(context)),
          const Gap(Space.hair),
          Text(
            phase.file.path,
            key: const ValueKey('update-path'),
            style: ts(
              theme.typeScale.ui,
              theme.ink,
              mono: true,
              weight: Weight.regular,
            ),
          ),
          const Gap(Space.md),
          Text(
            'BubblePaw does not replace itself on Linux yet. Extract the '
            'archive over the current installation, then start BubblePaw '
            'again.',
            style: ts(theme.typeScale.body, theme.ink),
          ),
        ],
        actions: [
          ActionButton(
            key: const ValueKey('update-close'),
            label: 'Close',
            onTap: updates.later,
          ),
          ActionButton(
            key: const ValueKey('update-copy-path'),
            label: 'Copy path',
            kind: ActionKind.primary,
            onTap: () => unawaited(
              Clipboard.setData(ClipboardData(text: phase.file.path)),
            ),
          ),
        ],
      );
    }
    final error = updates.installError;
    return _Spec(
      title: 'BubblePaw ${phase.manifest.version} is ready to install',
      body: [
        if (error != null) ...[
          NoticeBox(
            key: const ValueKey('update-install-error'),
            tone: NoticeTone.danger,
            child: Text(error),
          ),
          const Gap(Space.md),
        ] else ...[
          const NoticeBox(
            tone: NoticeTone.good,
            child: Text(
              'The installer is downloaded and its checksum matches.',
            ),
          ),
          const Gap(Space.md),
        ],
        Text(
          'Install and restart runs the installer and quits BubblePaw. It '
          'opens again when the installer is done.',
          style: ts(theme.typeScale.body, theme.ink),
        ),
      ],
      actions: [
        later,
        ActionButton(
          key: const ValueKey('update-install'),
          label: error == null ? 'Install and restart' : 'Try again',
          kind: ActionKind.primary,
          glyph: glyphRefresh,
          onTap: () => unawaited(updates.installAndRestart()),
        ),
      ],
    );
  }

  _Spec _failed(BuildContext context, UpdateFailed phase) {
    final theme = context.bb;
    final error = phase.error;
    final version = phase.manifest.version;
    final actions = [
      ActionButton(
        key: const ValueKey('update-later'),
        label: 'Later',
        onTap: updates.later,
      ),
      ActionButton(
        key: const ValueKey('update-retry'),
        label: 'Retry',
        kind: ActionKind.primary,
        glyph: glyphRefresh,
        onTap: () => unawaited(updates.download()),
      ),
    ];
    if (phase.checksum) {
      String cut(String? hash) => hash == null
          ? ''
          : (hash.length > 24 ? '${hash.substring(0, 24)}…' : hash);
      return _Spec(
        title: 'The download does not match its checksum',
        body: [
          NoticeBox(
            key: const ValueKey('update-error'),
            tone: NoticeTone.danger,
            child: Text(
              'The file does not match the checksum published for $version, '
              'so it was deleted and not installed.',
            ),
          ),
          const Gap(Space.md),
          GroupCard(
            children: [
              SettingsKeyValueRow('Expected', cut(error.expected)),
              SettingsKeyValueRow('Got', cut(error.actual)),
            ],
          ),
          Text(
            'Retry downloads the file again. If it fails again, try later or '
            'download the installer from the releases page.',
            style: _hint(context),
          ),
        ],
        actions: actions,
      );
    }
    final stopped = error.received == null
        ? ''
        : 'The download stopped at ${megabytes(error.received!, error.total)}. ';
    return _Spec(
      title: 'The download failed',
      body: [
        NoticeBox(
          key: const ValueKey('update-error'),
          tone: NoticeTone.danger,
          child: Text('$stopped${error.message} Nothing was installed.'),
        ),
        const Gap(Space.md),
        Text(
          'Check the connection, then retry. Retry starts the download '
          'again.',
          style: ts(
            theme.typeScale.uiSmall,
            theme.muted,
            weight: Weight.regular,
          ),
        ),
      ],
      actions: actions,
    );
  }
}

class _Spec {
  const _Spec({
    required this.title,
    required this.body,
    required this.actions,
    this.leading,
  });

  final String title;
  final List<Widget> body;
  final List<Widget> actions;
  final Widget? leading;
}
