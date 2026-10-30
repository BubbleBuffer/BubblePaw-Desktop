// About: updates for BubblePaw (channel, automatic check, Check now), the
// versions in use (Core is embedded in the app) and the way to the open source
// licences.

import 'dart:async';

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart'
    show BubblePawBackend;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../feedback/feedback_controller.dart';
import '../host_controller.dart';
import '../platform/releases.dart';
import '../preferences.dart';
import '../updates/update_controller.dart';
import '../versions.dart';
import 'action_widgets.dart';
import 'settings_widgets.dart';

/// `today, 09:14`, `yesterday, 21:02` or `2026-10-27 09:14`.
String formatChecked(DateTime when, DateTime now) {
  final local = when.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(local.hour)}:${two(local.minute)}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'today, $time';
  if (days == 1) return 'yesterday, $time';
  return '${local.year}-${two(local.month)}-${two(local.day)} $time';
}

class AboutPage extends StatefulWidget {
  const AboutPage({
    super.key,
    required this.controller,
    required this.services,
    required this.feedback,
    required this.onSendFeedback,
    required this.onViewFeedback,
    required this.onLicences,
    this.onBack,
    this.now,
  });

  final HostController controller;
  final PlatformServices services;
  final FeedbackController feedback;
  final VoidCallback onSendFeedback;
  final VoidCallback onViewFeedback;
  final VoidCallback onLicences;
  final VoidCallback? onBack;

  /// The clock "Last checked" is read against; the wall clock when null.
  final DateTime Function()? now;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  HostController get _host => widget.controller;
  UpdateController get _updates => _host.updates;

  @override
  void initState() {
    super.initState();
    _host.addListener(_changed);
  }

  @override
  void dispose() {
    _host.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final prefs = _host.prefs;
    final phase = _updates.phase;
    final checking = phase is UpdateChecking;
    final offered = _updates.offered;
    final available =
        phase is UpdateAvailable ||
        phase is UpdateDownloading ||
        phase is UpdateReady ||
        phase is UpdateFailed;
    final channelName = prefs.updateChannel == UpdateChannel.stable
        ? 'Stable'
        : 'Nightly';
    final last = prefs.lastUpdateCheck;
    final lastText = checking
        ? 'Checking now'
        : _updates.checkError != null
        ? 'Could not check. ${_updates.checkError}'
        : last == null
        ? 'Not checked yet'
        : formatChecked(last, widget.now?.call() ?? DateTime.now());
    return SettingsPage(
      title: 'About',
      onBack: widget.onBack,
      backKey: const ValueKey('settings-page-back'),
      children: [
        const SettingsHeading('Updates'),
        SettingsRow(
          label: 'BubblePaw',
          description: '$buildVersion · $channelName',
          trailing: checking
              ? const StatePill(
                  'Checking',
                  key: ValueKey('update-state'),
                  tone: PillTone.attention,
                )
              : available && offered != null
              ? StatePill(
                  '${offered.version} available',
                  key: const ValueKey('update-state'),
                  tone: PillTone.attention,
                )
              : _updates.upToDate
              ? const StatePill(
                  'Up to date',
                  key: ValueKey('update-state'),
                  tone: PillTone.good,
                )
              : null,
        ),
        SettingsRow(
          label: 'Channel',
          description: prefs.updateChannel == UpdateChannel.stable
              ? 'Stable releases.'
              : 'Prerelease builds from main.',
          trailing: SegmentedChoice<UpdateChannel>(
            idPrefix: 'channel',
            options: UpdateChannel.values,
            value: prefs.updateChannel,
            labelOf: (c) => c == UpdateChannel.stable ? 'Stable' : 'Nightly',
            onChanged: (c) => unawaited(_updates.setChannel(c)),
          ),
        ),
        if (prefs.updateChannel == UpdateChannel.nightly) ...[
          const SizedBox(height: 4),
          const NoticeBox(
            key: ValueKey('nightly-notice'),
            tone: NoticeTone.info,
            child: Text(
              'Nightly builds are prereleases built from main. You get '
              'changes sooner, and they can have bugs. Switching back to '
              'Stable installs the next stable release. It does not '
              'downgrade.',
            ),
          ),
          const SizedBox(height: 8),
        ],
        SwitchRow(
          id: 'auto-update',
          label: 'Check automatically',
          description: 'Checks when BubblePaw starts, at most once a day.',
          value: prefs.checkUpdates,
          onChanged: (v) => unawaited(_updates.setAutomatic(v)),
        ),
        SettingsRow(
          label: 'Last checked',
          description: lastText,
          trailing: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              if (available)
                ActionButton(
                  key: const ValueKey('update-review'),
                  label: 'Review update',
                  kind: ActionKind.primary,
                  onTap: _updates.review,
                ),
              ActionButton(
                key: const ValueKey('update-check'),
                label: checking ? 'Checking' : 'Check now',
                glyph: glyphRefresh,
                onTap: checking ? () {} : () => unawaited(_updates.check()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const SettingsHeading('Versions', top: 24),
        GroupCard(
          children: [
            _Version('BubblePaw', buildVersion),
            _Version('Agent kit', kitVersion),
            _Version('Core', _host.hostVersion ?? 'Not running'),
            _Version('Protocol', BubblePawBackend.protocolVersion),
          ],
        ),
        const SettingsHeading('Help', top: 24),
        SettingsRow(
          label: 'Send feedback',
          description:
              'Saves what you write, a screenshot and diagnostics on this '
              'computer. Nothing is sent. Shortcut: Ctrl+Shift+F',
          trailing: PrimaryButton(
            key: const ValueKey('about-feedback'),
            label: 'Send feedback',
            height: 36,
            onTap: widget.onSendFeedback,
          ),
        ),
        ListenableBuilder(
          listenable: widget.feedback,
          builder: (context, _) {
            final n = widget.feedback.reports.length;
            return SettingsRow(
              label: 'Saved feedback',
              description: n == 0
                  ? 'No reports saved.'
                  : n == 1
                  ? '1 report saved.'
                  : '$n reports saved.',
              trailing: OutlineButton(
                key: const ValueKey('about-feedback-view'),
                label: 'View',
                onTap: widget.onViewFeedback,
              ),
            );
          },
        ),
        const SettingsHeading('Licences', top: 24),
        SettingsRow(
          label: 'Open source licences',
          description: 'Packages, fonts and icons bundled with this app.',
          trailing: OutlineButton(
            key: const ValueKey('about-licences'),
            label: 'View',
            icon: Icon20(Ico.chevronRight, size: 16, color: theme.ink),
            onTap: widget.onLicences,
          ),
        ),
      ],
    );
  }
}

class _Version extends StatelessWidget {
  const _Version(this.name, this.value);

  final String name;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(name, style: ts(theme.typeScale.ui, theme.muted)),
          ),
          Expanded(
            child: Text(
              value,
              key: ValueKey('version-$name'),
              style: ts(theme.typeScale.ui, theme.ink, mono: true),
            ),
          ),
        ],
      ),
    );
  }
}
