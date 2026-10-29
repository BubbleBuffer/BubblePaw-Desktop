// About: the versions in use, whether a newer BubblePaw Core is published and
// the way to the open source licences.
//
// The app has no update row: its repository is private, so there is no
// release to look up.

import 'dart:async';

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart'
    show BubblePawBackend;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../config.dart';
import '../host_controller.dart';
import '../platform/releases.dart';
import '../versions.dart';
import 'settings_widgets.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({
    super.key,
    required this.controller,
    required this.services,
    required this.onLicences,
    this.onBack,
  });

  final HostController controller;
  final PlatformServices services;
  final VoidCallback onLicences;
  final VoidCallback? onBack;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

enum _Check { idle, checking, done, failed }

class _AboutPageState extends State<AboutPage> {
  _Check _check = _Check.idle;
  ReleaseInfo? _latest;
  String? _failure;

  Future<void> _run() async {
    setState(() => _check = _Check.checking);
    try {
      final latest = await widget.services.latestCoreRelease();
      if (!mounted) return;
      setState(() {
        _latest = latest;
        _check = _Check.done;
      });
    } on ReleaseCheckException catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = error.message;
        _check = _Check.failed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final host = widget.controller;
    final current = host.hostVersion;
    final latest = _latest;
    final newer =
        latest != null &&
        current != null &&
        isNewerVersion(latest.version, current);
    final bundled = host.config?.binarySource == BinarySource.bundled;
    final String status = switch (_check) {
      _Check.idle => 'Latest release not checked.',
      _Check.checking => 'Checking GitHub releases…',
      _Check.failed => 'Could not check. ${_failure ?? ''}'.trim(),
      _Check.done =>
        newer
            ? '${latest.version} is out.'
            : current == null
            ? 'Latest release is ${latest!.version}.'
            : '${latest!.version} is the latest release.',
    };
    return SettingsPage(
      title: 'About',
      onBack: widget.onBack,
      backKey: const ValueKey('settings-page-back'),
      children: [
        const SettingsHeading('Updates'),
        SettingsRow(
          label: current == null ? 'Core' : 'Core $current',
          description: '$status${bundled ? ' It updates with the app.' : ''}',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (newer) ...[
                const StatePill(
                  'Update available',
                  key: ValueKey('core-update'),
                  tone: PillTone.attention,
                ),
                const SizedBox(width: 8),
                OutlineButton(
                  key: const ValueKey('core-release-link'),
                  label: 'View release',
                  onTap: () => unawaited(widget.services.open(latest.page)),
                ),
              ] else if (_check == _Check.done && latest != null && current == null)
                OutlineButton(
                  key: const ValueKey('core-release-link'),
                  label: 'View release',
                  onTap: () => unawaited(widget.services.open(latest.page)),
                )
              else
                OutlineButton(
                  key: const ValueKey('core-check'),
                  label: _check == _Check.checking
                      ? 'Checking…'
                      : _check == _Check.idle
                      ? 'Check for updates'
                      : 'Check again',
                  onTap: _check == _Check.checking ? null : () => unawaited(_run()),
                ),
            ],
          ),
        ),
        const SettingsHeading('Versions', top: 24),
        GroupCard(
          children: [
            _Version('BubblePaw', appVersion),
            _Version('Agent kit', kitVersion),
            _Version('Core', current ?? 'Not running'),
            _Version('Protocol', BubblePawBackend.protocolVersion),
          ],
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
