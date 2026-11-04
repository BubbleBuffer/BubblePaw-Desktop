// "Hosts you can open" in Remote access: the saved hosts with whether each
// answers, "Add a host" (the pairing link, the number to compare, done) and
// "Remove".

import 'dart:async';

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../remote/host_links.dart';
import '../remote/hosts_controller.dart';
import '../remote/link_scanner.dart';
import '../remote/remote_controller.dart' show lastSeenText;
import 'action_widgets.dart';
import 'remote_dialogs.dart';
import 'remote_glyphs.dart';
import 'settings_widgets.dart';
import 'text_box.dart';

/// "Relay" or "Cloudflare Tunnel": how a host is reached.
String viaName(HostVia via) =>
    via == HostVia.relay ? 'Relay' : 'Cloudflare Tunnel';

class HostsSection extends StatefulWidget {
  const HostsSection({
    super.key,
    required this.hosts,
    required this.deviceName,
    this.openAtStart = false,
    this.onOpened,
    this.now,
  });

  final HostsController hosts;

  /// What this device calls itself to a host it pairs with.
  final String deviceName;

  /// The add dialog opens as soon as the section shows.
  final bool openAtStart;

  /// Called once the dialog the section opened at the start is on screen.
  final VoidCallback? onOpened;

  /// The clock the last connection is measured against.
  final DateTime Function()? now;

  @override
  State<HostsSection> createState() => _HostsSectionState();
}

class _HostsSectionState extends State<HostsSection> {
  @override
  void initState() {
    super.initState();
    widget.hosts.addListener(_changed);
    if (widget.hosts.loaded) unawaited(widget.hosts.refreshPresence());
    if (widget.openAtStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onOpened?.call();
        unawaited(_add());
      });
    }
  }

  @override
  void didUpdateWidget(HostsSection old) {
    super.didUpdateWidget(old);
    if (old.hosts != widget.hosts) {
      old.hosts.removeListener(_changed);
      widget.hosts.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.hosts.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _add() => showAddHostDialog(
    context,
    hosts: widget.hosts,
    deviceName: widget.deviceName,
  );

  Future<void> _remove(SavedHostEntry host) async {
    final sure = await showConfirm(
      context,
      title: 'Remove ${host.label}?',
      message:
          'This device forgets ${host.label}. Its chats stay on that host. '
          'To open it again, add the host with a new code.',
      confirmLabel: 'Remove ${host.label}',
      danger: true,
    );
    if (sure) await widget.hosts.forget(host.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final hosts = widget.hosts;
    final now = (widget.now ?? DateTime.now)();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  'Hosts you can open',
                  style: ts(theme.typeScale.h2, theme.ink, weight: 600),
                ),
              ),
            ),
            ActionButton(
              key: const ValueKey('hosts-add'),
              label: 'Add a host',
              glyph: glyphPlus,
              onTap: () => unawaited(_add()),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (hosts.error != null)
          NoticeBox(
            key: const ValueKey('hosts-error'),
            tone: NoticeTone.danger,
            trailing: ActionButton(
              key: const ValueKey('hosts-retry'),
              label: 'Try again',
              glyph: glyphRefresh,
              onTap: () => unawaited(hosts.load()),
            ),
            child: Text(hosts.error!),
          )
        else if (!hosts.loaded)
          Text(
            'Loading hosts…',
            key: const ValueKey('hosts-loading'),
            style: ts(theme.typeScale.ui, theme.muted),
          )
        else if (hosts.hosts.isEmpty)
          Text(
            'No hosts yet. Add a host to open its chats from this device.',
            key: const ValueKey('hosts-empty'),
            style: ts(theme.typeScale.ui, theme.muted),
          )
        else
          for (final h in hosts.hosts)
            Padding(
              key: ValueKey('host-${h.id}'),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  glyphIcon(glyphMonitor, size: 18, color: theme.muted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(h.label, style: ts(theme.typeScale.ui, theme.ink)),
                        Text(
                          [
                            viaName(h.via),
                            if (h.lastConnected != null)
                              lastSeenText(
                                now,
                                h.lastConnected,
                              ).replaceFirst('Last seen', 'Opened'),
                          ].join(' · '),
                          style: ts(theme.typeScale.uiSmall, theme.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _presence(hosts.presenceOf(h.id)),
                  const SizedBox(width: 4),
                  ActionButton(
                    key: ValueKey('host-remove-${h.id}'),
                    label: 'Remove',
                    kind: ActionKind.quiet,
                    onTap: () => unawaited(_remove(h)),
                  ),
                ],
              ),
            ),
        const SizedBox(height: 12),
        Text(
          'Removing a host deletes its pairing from this device. The host '
          'keeps your device in its list until it is revoked there.',
          style: ts(theme.typeScale.uiSmall, theme.muted),
        ),
      ],
    );
  }

  Widget _presence(HostPresenceKind? kind) => switch (kind) {
    HostPresenceKind.online => const StatePill(
      'Online',
      key: ValueKey('host-presence'),
      tone: PillTone.good,
    ),
    HostPresenceKind.offline => const StatePill(
      'Offline',
      key: ValueKey('host-presence'),
    ),
    HostPresenceKind.unknown => const StatePill(
      'Not checked',
      key: ValueKey('host-presence'),
    ),
    null => const StatePill('Checking', key: ValueKey('host-presence')),
  };
}

/// "Add a host". Resolves when the dialog closes.
Future<void> showAddHostDialog(
  BuildContext context, {
  required HostsController hosts,
  required String deviceName,
}) async {
  final flow = AddHostFlow(
    links: hosts.links,
    deviceName: deviceName,
    onAdded: hosts.added,
  );
  try {
    await showModalPanel<void>(
      context,
      (_) => SizeClassBuilder(builder: (_, _) => AddHostDialog(flow: flow)),
      width: 480,
      height: 560,
      shrink: true,
    );
  } finally {
    await flow.cancel();
    flow.dispose();
  }
}

class AddHostDialog extends StatefulWidget {
  const AddHostDialog({super.key, required this.flow});

  final AddHostFlow flow;

  @override
  State<AddHostDialog> createState() => _AddHostDialogState();
}

class _AddHostDialogState extends State<AddHostDialog> {
  final _link = TextEditingController();

  AddHostFlow get _flow => widget.flow;

  @override
  void initState() {
    super.initState();
    _link.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final scan = linkScanner;
    if (scan == null) return;
    final text = await scan(context);
    if (!mounted || text == null || text.trim().isEmpty) return;
    _link.text = text.trim();
    await _flow.connect(text);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _flow,
    builder: (context, _) => switch (_flow.step) {
      AddHostStep.enter => _enter(context),
      AddHostStep.compare => _compare(context),
      AddHostStep.added => _added(context),
    },
  );

  Widget _enter(BuildContext context) {
    final theme = context.bb;
    final ready = _link.text.trim().isNotEmpty && !_flow.busy;
    return DialogFrame(
      title: 'Add a host',
      step: 'Step 1 of 2',
      body: [
        if (linkScanner != null) ...[
          ActionButton(
            key: const ValueKey('add-host-scan'),
            label: 'Scan QR code',
            kind: ActionKind.primary,
            glyph: glyphScanLine,
            onTap: _flow.busy ? () {} : () => unawaited(_scan()),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                'or paste the pairing link',
                style: ts(theme.typeScale.uiSmall, theme.muted),
              ),
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Paste the pairing link shown by the host.',
              style: ts(theme.typeScale.ui, theme.ink),
            ),
          ),
        LabeledField(
          label: 'Pairing link from the host',
          hint:
              'On the host: Settings, Remote access, Share this host, Pair a '
              'device, Copy pairing link.',
          error: _flow.error ?? '',
          bottom: 0,
          child: TextBox(
            controller: _link,
            fieldKey: const ValueKey('add-host-link'),
            label: 'Pairing link from the host',
            placeholder: 'Pairing link',
            mono: true,
            invalid: _flow.error != null,
            onSubmitted: (v) => unawaited(_flow.connect(v)),
          ),
        ),
      ],
      footer: dialogFooter(
        leading: _flow.busy
            ? Row(
                children: [
                  glyphIcon(glyphLoader, size: 15, color: theme.muted),
                  const SizedBox(width: 6),
                  Text(
                    'Connecting to the host',
                    style: ts(theme.typeScale.uiSmall, theme.muted),
                  ),
                ],
              )
            : null,
        [
          ActionButton(
            key: const ValueKey('add-host-cancel'),
            label: 'Cancel',
            onTap: () => Navigator.of(context).maybePop(),
          ),
          ActionButton(
            key: const ValueKey('add-host-connect'),
            label: 'Connect',
            kind: ActionKind.primary,
            onTap: ready ? () => unawaited(_flow.connect(_link.text)) : () {},
          ),
        ],
      ),
    );
  }

  Widget _compare(BuildContext context) {
    final theme = context.bb;
    return DialogFrame(
      title: 'Confirm the number',
      step: 'Step 2 of 2',
      body: [
        Text(
          'Check that this number is the same on the host. Its owner will be '
          'asked to confirm.',
          style: ts(theme.typeScale.ui, theme.ink),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Semantics(
              label: 'Number to compare',
              child: Text(
                _spaced(_flow.comparison),
                key: const ValueKey('add-host-number'),
                style: ts(
                  theme.typeScale.h2,
                  theme.ink,
                  weight: 600,
                  mono: true,
                ).copyWith(fontSize: 32, letterSpacing: 2),
              ),
            ),
          ),
        ),
        Row(
          children: [
            glyphIcon(glyphLoader, size: 15, color: theme.muted),
            const SizedBox(width: 8),
            Text(
              'Waiting for the host to confirm.',
              style: ts(theme.typeScale.uiSmall, theme.muted),
            ),
          ],
        ),
      ],
      footer: dialogFooter([
        ActionButton(
          key: const ValueKey('add-host-back'),
          label: 'Cancel',
          onTap: () => unawaited(_flow.cancel()),
        ),
      ]),
    );
  }

  Widget _added(BuildContext context) {
    final host = _flow.added!;
    return DialogFrame(
      title: 'Add a host',
      body: [
        NoticeBox(
          key: const ValueKey('add-host-added'),
          tone: NoticeTone.good,
          child: Text(
            '${host.label} was added. You can open its chats from the menu.',
          ),
        ),
        const SizedBox(height: 12),
        GroupCard(
          children: [
            SettingsKeyValueRow('Host', host.label, mono: false),
            SettingsKeyValueRow('Address type', viaName(host.via), mono: false),
            if (host.profile.isNotEmpty)
              SettingsKeyValueRow(
                'Your permissions',
                profileName(host.profile),
                mono: false,
              ),
          ],
        ),
      ],
      footer: dialogFooter([
        ActionButton(
          key: const ValueKey('add-host-done'),
          label: 'Done',
          kind: ActionKind.primary,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ]),
    );
  }
}

String _spaced(String digits) => digits.length == 6
    ? '${digits.substring(0, 3)} ${digits.substring(3)}'
    : digits;
