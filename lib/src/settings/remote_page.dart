// Settings > Remote access: this device, sharing this host (how devices reach
// it, status, cloudflared), and the devices paired with it. The device key has
// its own sub-page.

import 'dart:async';

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../platform/releases.dart';
import '../remote/hosts_controller.dart';
import '../remote/remote_access.dart';
import '../remote/remote_controller.dart';
import 'action_widgets.dart';
import 'device_key_page.dart';
import 'hosts_section.dart';
import 'remote_dialogs.dart';
import 'remote_glyphs.dart';
import 'settings_widgets.dart';
import 'text_box.dart';

class RemotePage extends StatefulWidget {
  const RemotePage({
    super.key,
    required this.remote,
    required this.services,
    this.onBack,
    this.hosts,
    this.deviceName = '',
    this.addHostPending = false,
    this.onAddHostHandled,
    this.phone = false,
  });

  /// The hosts this device can open; null when there is no such side.
  final HostsController? hosts;

  /// What this device calls itself to a host it pairs with.
  final String deviceName;

  /// "Add a host" was chosen in the host switcher: the page opens on the
  /// hosts and the add dialog.
  final bool addHostPending;
  final VoidCallback? onAddHostHandled;

  /// The phone has no host to share: the page is the device and the hosts.
  final bool phone;

  /// Null while there is no host to share (not started, or stopped).
  final RemoteController? remote;
  final PlatformServices services;
  final VoidCallback? onBack;

  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> {
  final _name = TextEditingController();
  final _relay = TextEditingController();
  final _hostname = TextEditingController();
  final _token = TextEditingController();
  String? _zone;
  bool _key = false;
  bool _synced = false;
  late bool _hostsTab = widget.addHostPending;

  RemoteController? get _r => widget.remote;

  @override
  void initState() {
    super.initState();
    _r?.addListener(_changed);
    _token.addListener(() => setState(() {}));
    _sync();
  }

  @override
  void didUpdateWidget(RemotePage old) {
    super.didUpdateWidget(old);
    if (old.remote != widget.remote) {
      old.remote?.removeListener(_changed);
      widget.remote?.addListener(_changed);
      _synced = false;
      _sync();
    }
  }

  @override
  void dispose() {
    _r?.removeListener(_changed);
    _name.dispose();
    _relay.dispose();
    _hostname.dispose();
    _token.dispose();
    super.dispose();
  }

  void _changed() {
    _sync();
    if (mounted) setState(() {});
  }

  /// Fills the fields from the loaded settings once.
  void _sync() {
    final r = _r;
    final config = r?.config;
    if (r == null || config == null || _synced) return;
    _synced = true;
    _name.text = r.deviceName;
    _relay.text = config.relay;
    final zones = r.cloudflare?.zones ?? const <String>[];
    final full = config.hostname;
    _zone =
        zones.where((z) => full.endsWith('.$z')).firstOrNull ??
        (zones.isEmpty ? null : zones.first);
    final zone = _zone;
    _hostname.text = zone != null && full.endsWith('.$zone')
        ? full.substring(0, full.length - zone.length - 1)
        : full;
  }

  String get _reachLabel =>
      _r?.mode == ShareMode.relay ? 'Relay' : 'Cloudflare Tunnel';

  @override
  Widget build(BuildContext context) {
    final r = _r;
    if (r == null) {
      return _frame([
        const _NoHost(),
        if (widget.hosts != null) _hostsSection(),
      ]);
    }
    if (_key) {
      return DeviceKeyPage(
        remote: r,
        services: widget.services,
        hostCount: widget.hosts?.hosts.length ?? 0,
        onBack: () {
          // A new key clears the pairings: read the saved hosts again.
          unawaited(widget.hosts?.reload());
          setState(() => _key = false);
        },
      );
    }
    if (r.loadError != null) {
      return _frame([
        NoticeBox(
          key: const ValueKey('remote-load-error'),
          tone: NoticeTone.danger,
          trailing: ActionButton(
            key: const ValueKey('remote-retry'),
            label: 'Try again',
            glyph: glyphRefresh,
            onTap: () => unawaited(r.load()),
          ),
          child: const Text('Could not load the remote access settings.'),
        ),
      ]);
    }
    if (!r.loaded) {
      return _frame([
        Row(
          key: const ValueKey('remote-loading'),
          children: [
            glyphIcon(glyphLoader, size: 15, color: context.bb.muted),
            const SizedBox(width: 8),
            Text(
              'Loading remote access…',
              style: ts(context.bb.typeScale.ui, context.bb.muted),
            ),
          ],
        ),
      ]);
    }
    return _frame([
      if (r.error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: NoticeBox(
            key: const ValueKey('remote-error'),
            tone: NoticeTone.danger,
            child: Text(r.error!),
          ),
        ),
      _deviceSection(r),
      if (widget.hosts != null && !widget.phone)
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedChoice<bool>(
              idPrefix: 'remote-tab',
              options: const [false, true],
              value: _hostsTab,
              labelOf: (hosts) =>
                  hosts ? 'Hosts you can open' : 'Share this host',
              onChanged: (hosts) => setState(() => _hostsTab = hosts),
            ),
          ),
        ),
      if ((_hostsTab || widget.phone) && widget.hosts != null)
        _hostsSection()
      else ...[
        _sharingSection(r),
        _reachSection(r),
        _pairedSection(r),
      ],
    ]);
  }

  Widget _hostsSection() => HostsSection(
    hosts: widget.hosts!,
    deviceName: widget.deviceName,
    openAtStart: widget.addHostPending,
    onOpened: widget.onAddHostHandled,
  );

  Widget _frame(List<Widget> children) => SettingsPage(
    title: 'Remote access',
    onBack: widget.onBack,
    backKey: const ValueKey('settings-page-back'),
    children: children,
  );

  // This device.
  Widget _deviceSection(RemoteController r) {
    final key = r.key;
    return _Section(
      title: 'This device',
      action: ActionButton(
        key: const ValueKey('remote-manage-key'),
        label: 'Manage key…',
        glyph: glyphKeyRound,
        onTap: () => setState(() => _key = true),
      ),
      child: GroupCard(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: LabeledField(
              label: 'Name',
              hint: 'Shown to devices you pair.',
              bottom: 12,
              child: TextBox(
                controller: _name,
                fieldKey: const ValueKey('remote-name'),
                label: 'Device name',
                onSubmitted: (v) => unawaited(r.rename(v)),
                onBlur: (v) => unawaited(r.rename(v)),
              ),
            ),
          ),
          SettingsKeyValueRow(
            'Device ID',
            key?.id ?? '',
            valueKey: const ValueKey('remote-device-id'),
            trailing: ActionButton(
              key: const ValueKey('remote-copy-id'),
              label: 'Copy',
              kind: ActionKind.quiet,
              glyph: glyphCopy,
              onTap: () => unawaited(widget.services.copy(key?.id ?? '')),
            ),
          ),
          SettingsKeyValueRow(
            'Fingerprint',
            key?.fingerprint ?? '',
            valueKey: const ValueKey('remote-fingerprint'),
          ),
        ],
      ),
    );
  }

  // Share this host.
  Widget _sharingSection(RemoteController r) {
    final on = r.wantOn;
    return _Section(
      title: 'Sharing',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchRow(
            id: 'share',
            label: 'Share this host',
            description: on
                ? 'Paired devices can open chats on this computer while '
                      'BubblePaw is running.'
                : 'Nobody can reach this computer. Paired devices stay paired.',
            value: on,
            enabled: !r.busy,
            onChanged: (v) => unawaited(r.setEnabled(v)),
          ),
          if (r.sharedElsewhere) ...[
            const SizedBox(height: 8),
            NoticeBox(
              key: const ValueKey('remote-other'),
              tone: NoticeTone.info,
              child: Text(_otherText(r.other!)),
            ),
          ],
        ],
      ),
    );
  }

  String _otherText(OtherShare other) {
    final id = other.hostId == null ? '' : ': device ID ${other.hostId}';
    final dir = other.dataDir == null
        ? ''
        : ', data directory ${other.dataDir}';
    return 'Another BubblePaw host on this computer is already shared$id$dir. '
        "Devices paired with it can't open this app's chats.";
  }

  // How devices reach this computer, the status and cloudflared.
  Widget _reachSection(RemoteController r) {
    final theme = context.bb;
    final mode = r.mode;
    final quick = mode == ShareMode.quick;
    return _Section(
      title: 'How devices reach this computer',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChoiceCard(
            key: const ValueKey('reach-quick'),
            title: 'Cloudflare Tunnel, temporary address',
            description:
                'No account. The address changes each time the host starts, '
                'so paired devices need a new code after a restart.',
            selected: quick,
            onTap: () => unawaited(r.setMode(ShareMode.quick)),
          ),
          ChoiceCard(
            key: const ValueKey('reach-domain'),
            title: 'Cloudflare Tunnel, your domain',
            description:
                'A stable address such as bubblepaw-desk.example.com. Needs a '
                'Cloudflare account with a domain.',
            selected: mode == ShareMode.domain,
            onTap: () => unawaited(r.setMode(ShareMode.domain)),
          ),
          if (mode == ShareMode.domain) _domainPanel(r),
          ChoiceCard(
            key: const ValueKey('reach-relay'),
            title: 'Relay server',
            description: 'Devices meet through a relay server you run.',
            selected: mode == ShareMode.relay,
            onTap: () => unawaited(r.setMode(ShareMode.relay)),
          ),
          if (mode == ShareMode.relay)
            _SubPanel(
              child: LabeledField(
                label: 'Relay address',
                bottom: 0,
                child: TextBox(
                  controller: _relay,
                  fieldKey: const ValueKey('remote-relay'),
                  label: 'Relay address',
                  mono: true,
                  onSubmitted: (v) => unawaited(r.setRelay(v)),
                  onBlur: (v) => unawaited(r.setRelay(v)),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                glyphIcon(glyphShieldCheck, size: 16, color: theme.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    mode == ShareMode.relay
                        ? 'Traffic is end-to-end encrypted between paired '
                              'devices. The relay sees only encrypted data.'
                        : 'Traffic is end-to-end encrypted between paired '
                              'devices. Cloudflare sees only encrypted data.',
                    key: const ValueKey('remote-consequence'),
                    style: ts(theme.typeScale.uiSmall, theme.muted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SwitchRow(
            id: 'share-at-start',
            label: 'Share automatically when the host starts',
            description: quick
                ? 'Needs a relay server or your own domain. A temporary '
                      'address changes on every start.'
                : 'The host starts sharing as soon as it runs, for example at '
                      'login.',
            value: !quick && r.shareAtStart(),
            enabled: !quick,
            onChanged: (v) => unawaited(r.setShareAtStart(v)),
          ),
          const SizedBox(height: 12),
          _status(r),
        ],
      ),
    );
  }

  // The domain's sign-in, zone and hostname.
  Widget _domainPanel(RemoteController r) {
    final theme = context.bb;
    final cf = r.cloudflare;
    if (r.signingIn) {
      return _SubPanel(
        child: Row(
          key: const ValueKey('cf-waiting'),
          children: [
            glyphIcon(glyphLoader, size: 15, color: theme.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Waiting for you to finish signing in in the browser.',
                style: ts(theme.typeScale.uiSmall, theme.muted),
              ),
            ),
            ActionButton(
              key: const ValueKey('cf-cancel'),
              label: 'Cancel',
              kind: ActionKind.quiet,
              onTap: () => unawaited(r.cancelSignIn()),
            ),
          ],
        ),
      );
    }
    if (cf != null && cf.signedIn) {
      final zones = cf.zones;
      return _SubPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    cf.account == null
                        ? 'Signed in to Cloudflare'
                        : 'Signed in to Cloudflare as ${cf.account}',
                    key: const ValueKey('cf-signed-in'),
                    style: ts(theme.typeScale.ui, theme.ink),
                  ),
                ),
                if (cf.via == CloudflareVia.tokenFile)
                  ActionButton(
                    key: const ValueKey('cf-sign-out'),
                    label: 'Sign out',
                    glyph: glyphLogOut,
                    onTap: () => unawaited(r.signOut()),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (zones.isNotEmpty)
              LabeledField(
                label: 'Zone',
                bottom: 12,
                child: SegmentedChoice<String>(
                  idPrefix: 'zone',
                  options: zones,
                  value: _zone ?? zones.first,
                  labelOf: (z) => z,
                  onChanged: (z) {
                    setState(() => _zone = z);
                    unawaited(r.setHostname(_hostname.text, z));
                  },
                ),
              ),
            LabeledField(
              label: 'Hostname',
              bottom: 0,
              hint: _hostname.text.trim().isEmpty || _zone == null
                  ? null
                  : 'Creates a DNS record for '
                        '${_hostname.text.trim()}.$_zone that points at the '
                        'tunnel.',
              error: r.hostnameError ?? '',
              child: TextBox(
                controller: _hostname,
                fieldKey: const ValueKey('remote-hostname'),
                label: 'Hostname',
                mono: true,
                suffix: _zone == null ? null : '.$_zone',
                invalid: r.hostnameError != null,
                onSubmitted: (v) => unawaited(r.setHostname(v, _zone ?? '')),
                onBlur: (v) => unawaited(r.setHostname(v, _zone ?? '')),
              ),
            ),
          ],
        ),
      );
    }
    if (r.tokenOpen) {
      final ready = _token.text.trim().isNotEmpty && !r.tokenBusy;
      return _SubPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LabeledField(
              label: 'API token',
              hint: 'Needs Cloudflare Tunnel edit and DNS edit for the zone.',
              child: TextBox(
                controller: _token,
                fieldKey: const ValueKey('cf-token'),
                label: 'API token',
                placeholder: 'Cloudflare API token',
                obscure: true,
              ),
            ),
            Row(
              children: [
                Opacity(
                  opacity: ready ? 1 : .5,
                  child: ActionButton(
                    key: const ValueKey('cf-token-save'),
                    label: 'Save token',
                    kind: ActionKind.primary,
                    onTap: ready
                        ? () async {
                            await r.saveToken(_token.text);
                            if (!r.tokenOpen) _token.clear();
                          }
                        : () {},
                  ),
                ),
                const SizedBox(width: 8),
                ActionButton(
                  key: const ValueKey('cf-token-cancel'),
                  label: 'Cancel',
                  onTap: () {
                    _token.clear();
                    r.openToken(false);
                  },
                ),
              ],
            ),
          ],
        ),
      );
    }
    return _SubPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Not signed in to Cloudflare. The tunnel cannot start until you '
            'sign in.',
            key: const ValueKey('cf-signed-out'),
            style: ts(theme.typeScale.uiSmall, theme.muted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionButton(
                key: const ValueKey('cf-sign-in'),
                label: 'Sign in with Cloudflare',
                kind: ActionKind.primary,
                glyph: glyphCloud,
                onTap: () =>
                    unawaited(r.signInWithBrowser(widget.services.open)),
              ),
              ActionButton(
                key: const ValueKey('cf-use-token'),
                label: 'Use an API token',
                glyph: glyphKeyRound,
                onTap: () => r.openToken(true),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Sign in opens your browser.',
            style: ts(theme.typeScale.uiSmall, theme.muted),
          ),
        ],
      ),
    );
  }

  String _blockWords(RemoteController r) => switch (r.block) {
    ShareBlock.cloudflaredMissing => 'cloudflared is not installed.',
    ShareBlock.notSignedIn => 'Not signed in to Cloudflare.',
    ShareBlock.noHostname => r.hostnameError ?? 'Enter a hostname.',
    ShareBlock.none => r.failure ?? '',
  };

  Widget _status(RemoteController r) {
    final theme = context.bb;
    final relay = r.mode == ShareMode.relay;
    final state = r.share;
    final (String label, PillTone tone) = switch (state.status) {
      ShareStatus.online => ('Connected', PillTone.good),
      ShareStatus.connecting => ('Starting', PillTone.attention),
      ShareStatus.offline => ('Stopped', PillTone.bad),
      ShareStatus.off =>
        r.wantOn || r.block != ShareBlock.none
            ? ('Stopped', PillTone.bad)
            : ('Stopped', PillTone.plain),
    };
    final why = _blockWords(r);
    final canRetry =
        r.wantOn &&
        !r.busy &&
        r.block == ShareBlock.none &&
        state.status != ShareStatus.online &&
        state.status != ShareStatus.connecting;
    final config = r.config;
    final address = state.address;
    final idleAddress = switch (r.mode) {
      ShareMode.quick => 'None. A new address is assigned at the next start.',
      ShareMode.domain =>
        (config?.hostname ?? '').isEmpty
            ? 'None until a hostname is set.'
            : '${config!.hostname} (not reachable)',
      ShareMode.relay => '${config?.relay ?? ''} (not reachable)',
    };
    return GroupCard(
      key: const ValueKey('remote-status'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 112,
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    relay ? 'Relay' : 'Tunnel',
                    style: ts(theme.typeScale.ui, theme.muted),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatePill(
                      label,
                      key: const ValueKey('remote-pill'),
                      tone: tone,
                    ),
                    if (why.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          why,
                          key: const ValueKey('remote-why'),
                          style: ts(theme.typeScale.uiSmall, theme.muted),
                        ),
                      ),
                  ],
                ),
              ),
              if (canRetry) ...[
                const SizedBox(width: 8),
                ActionButton(
                  key: const ValueKey('remote-start-again'),
                  label: 'Start again',
                  glyph: glyphRefresh,
                  onTap: () => unawaited(r.startAgain()),
                ),
              ],
            ],
          ),
        ),
        if (state.status == ShareStatus.online && address != null)
          SettingsKeyValueRow(
            'Public address',
            address,
            valueKey: const ValueKey('remote-address'),
            trailing: ActionButton(
              key: const ValueKey('remote-copy-address'),
              label: 'Copy',
              kind: ActionKind.quiet,
              glyph: glyphCopy,
              onTap: () => unawaited(widget.services.copy(address)),
            ),
          )
        else if (state.status == ShareStatus.connecting)
          SettingsKeyValueRow(
            'Public address',
            r.mode == ShareMode.quick
                ? 'Waiting for Cloudflare to assign an address.'
                : 'Waiting for the address to answer.',
            valueKey: const ValueKey('remote-address'),
            mono: false,
          )
        else
          SettingsKeyValueRow(
            'Public address',
            idleAddress,
            valueKey: const ValueKey('remote-address'),
            mono: false,
          ),
        if (!relay) ..._cloudflaredRows(r),
      ],
    );
  }

  List<Widget> _cloudflaredRows(RemoteController r) {
    final theme = context.bb;
    final info = r.cloudflared;
    if (info == null || !info.installed) {
      return [
        SettingsKeyValueRow(
          'cloudflared',
          r.installing ? 'Downloading…' : 'Not installed.',
          valueKey: const ValueKey('cloudflared-state'),
          mono: false,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(124, 0, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Download comes from Cloudflare's GitHub releases and is "
                'checked against its published checksum.',
                style: ts(theme.typeScale.uiSmall, theme.muted),
              ),
              const SizedBox(height: 8),
              Opacity(
                opacity: r.installing ? .5 : 1,
                child: ActionButton(
                  key: const ValueKey('cloudflared-download'),
                  label: 'Download cloudflared',
                  kind: ActionKind.primary,
                  glyph: glyphDownload,
                  onTap: r.installing
                      ? () {}
                      : () => unawaited(r.installCloudflared()),
                ),
              ),
            ],
          ),
        ),
      ];
    }
    final version = info.version == null ? '' : ' ${info.version}';
    return [
      SettingsKeyValueRow(
        'cloudflared',
        info.managed
            ? 'cloudflared$version, managed by BubblePaw'
            : 'cloudflared$version at ${info.path ?? ''}',
        valueKey: const ValueKey('cloudflared-state'),
        mono: false,
        trailing: info.managed
            ? Opacity(
                opacity: r.updating || !info.updateAvailable ? .5 : 1,
                child: ActionButton(
                  key: const ValueKey('cloudflared-update'),
                  label: r.updating
                      ? 'Updating…'
                      : info.updateAvailable
                      ? 'Update'
                      : 'Up to date',
                  onTap: info.updateAvailable && !r.updating
                      ? () => unawaited(r.updateCloudflared())
                      : () {},
                ),
              )
            : null,
      ),
    ];
  }

  // Paired devices.
  Widget _pairedSection(RemoteController r) {
    final theme = context.bb;
    final devices = r.devices;
    final now = r.now();
    return _Section(
      title: 'Paired devices',
      action: Opacity(
        opacity: r.wantOn ? 1 : .5,
        child: ActionButton(
          key: const ValueKey('remote-pair'),
          label: 'Pair a device',
          kind: r.share.status == ShareStatus.online
              ? ActionKind.primary
              : ActionKind.outline,
          glyph: glyphPlus,
          onTap: r.wantOn
              ? () => unawaited(
                  showPairDialog(
                    context,
                    remote: r,
                    reachLabel: _reachLabel,
                    onCopy: widget.services.copy,
                  ),
                )
              : () {},
        ),
      ),
      child: devices.isEmpty
          ? Text(
              'No paired devices. Pair a device to open this computer from a '
              'phone or laptop.',
              key: const ValueKey('remote-no-devices'),
              style: ts(theme.typeScale.ui, theme.muted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final d in devices)
                  Padding(
                    key: ValueKey('device-${d.id}'),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        glyphIcon(
                          _kindGlyph(d.kind),
                          size: 18,
                          color: theme.muted,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.label,
                                style: ts(theme.typeScale.ui, theme.ink),
                              ),
                              Text(
                                lastSeenText(now, d.lastSeen),
                                style: ts(theme.typeScale.uiSmall, theme.muted),
                              ),
                              if (d.egress)
                                Text(
                                  'Model traffic allowed',
                                  key: ValueKey('device-egress-${d.id}'),
                                  style: ts(
                                    theme.typeScale.uiSmall,
                                    theme.muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _Tag(profileName(d.profile)),
                        const SizedBox(width: 4),
                        ActionButton(
                          key: ValueKey('revoke-${d.id}'),
                          label: 'Revoke',
                          kind: ActionKind.quiet,
                          onTap: () => unawaited(_revoke(r, d)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _revoke(RemoteController r, DeviceEntry device) async {
    final sure = await confirmRevoke(context, device);
    if (sure) await r.revoke(device.id);
  }
}

LucideGlyph _kindGlyph(String kind) {
  final k = kind.toLowerCase();
  if (k.contains('phone')) return glyphSmartphone;
  if (k.contains('tablet')) return glyphTablet;
  if (k.contains('laptop')) return glyphLaptop;
  return glyphMonitor;
}

/// A heading with an optional action at its end, over [child].
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.action});

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: ts(theme.typeScale.h2, theme.ink, weight: 600),
                  ),
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SubPanel extends StatelessWidget {
  const _SubPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.surface2,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(padding: const EdgeInsets.all(12), child: child),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface2,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(text, style: ts(theme.typeScale.uiSmall, theme.muted)),
      ),
    );
  }
}

class _NoHost extends StatelessWidget {
  const _NoHost();

  @override
  Widget build(BuildContext context) => const NoticeBox(
    key: ValueKey('remote-no-host'),
    tone: NoticeTone.info,
    child: Text(
      'This computer has no host to share. Start the host in BubblePaw first.',
    ),
  );
}
