// Models: the host's default model and its providers, each with whether the
// host found the key and its models. The default model is the host setting
// `model.main`, read with config.get and changed with config.set. The host
// reports only whether a key is present; nothing here reads, shows or stores
// one. A provider's `via` (`providers.<name>.via`, Core v0.11.0) names a saved
// host that carries the provider's model traffic; the picker offers Direct
// and the saved hosts that granted this device that.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../core/host_settings.dart';
import '../remote/hosts_controller.dart';
import 'settings_widgets.dart';

class ModelsPage extends StatefulWidget {
  const ModelsPage({
    super.key,
    required this.backend,
    required this.settings,
    this.hosts,
    this.onBack,
  });

  /// The running backend; null while the host is not running.
  final AgentBackend? backend;

  /// The host's settings; null when the host has none to read or change.
  final HostSettings? settings;

  /// The hosts saved on this device, for "Send model traffic through…". Null
  /// when the settings are not this computer's host's (a saved host is open,
  /// whose own saved hosts are not listed here): the picker is not shown.
  final HostsController? hosts;
  final VoidCallback? onBack;

  @override
  State<ModelsPage> createState() => _ModelsPageState();
}

class _ModelsPageState extends State<ModelsPage> {
  ProviderSetup? _setup;

  /// The host's default model, qualified, from `model.main`; null until read
  /// and when no host settings are available.
  String? _default;

  /// A model saved as the default that applies after the host restarts.
  String? _restartModel;
  String? _loadError;
  String? _makeError;
  String? _making;
  int _ticket = 0;

  /// `providers.<name>.via` for each provider that sets it.
  Map<String, String> _via = const {};
  String? _viaSaving;
  String? _viaErrorFor;
  String? _viaError;

  bool get _supported =>
      widget.backend?.capabilities.has(KitCapability.providers) ?? false;

  @override
  void initState() {
    super.initState();
    widget.hosts?.addListener(_hostsChanged);
    if (_supported) _load();
  }

  @override
  void dispose() {
    widget.hosts?.removeListener(_hostsChanged);
    super.dispose();
  }

  void _hostsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(ModelsPage old) {
    super.didUpdateWidget(old);
    if (old.hosts != widget.hosts) {
      old.hosts?.removeListener(_hostsChanged);
      widget.hosts?.addListener(_hostsChanged);
    }
    if (old.backend != widget.backend || old.settings != widget.settings) {
      _setup = null;
      _default = null;
      _restartModel = null;
      _loadError = null;
      _makeError = null;
      _making = null;
      _via = const {};
      _viaSaving = null;
      _viaError = null;
      _viaErrorFor = null;
      if (_supported) _load();
    }
  }

  static String _describe(Object error) => switch (error) {
    KitError() => error.message,
    HostSettingsException() => error.message,
    _ => 'Something went wrong.',
  };

  /// The providers, and the default model read from the host's settings.
  Future<void> _read(AgentBackend backend) async {
    final setup = await backend.listProviders();
    final settings = widget.settings;
    if (settings == null) {
      if (!mounted) return;
      setState(() {
        _setup = setup;
        _default = setup.defaultModel;
        _restartModel = null;
      });
      return;
    }
    final entries = {for (final s in await settings.get('model')) s.key: s};
    final via = _readVia(await settings.get('providers'));
    final main = entries['model.main'];
    final provider = entries['model.provider']?.value;
    final value = main?.value;
    final qualified = value is String
        ? _qualify(setup, value, provider is String ? provider : null)
        : null;
    if (!mounted) return;
    setState(() {
      _setup = setup;
      _default = qualified;
      _restartModel = main?.pendingRestart == true ? setup.main : null;
      _via = via;
    });
  }

  /// The `via` of each provider, from the `providers.<name>.via` settings.
  static Map<String, String> _readVia(List<HostSetting> settings) => {
    for (final s in settings)
      if (s.key.startsWith('providers.') &&
          s.key.endsWith('.via') &&
          s.value is String &&
          (s.value! as String).isNotEmpty)
        s.key.substring(10, s.key.length - 4): s.value! as String,
  };

  /// `model.main` may omit the provider that `model.provider` supplies.
  static String _qualify(ProviderSetup setup, String main, String? provider) {
    final known = {
      for (final p in setup.providers)
        for (final m in p.models) p.qualify(m),
    };
    if (known.contains(main) || provider == null) return main;
    final routed = '$provider/$main';
    return known.contains(routed) ? routed : main;
  }

  Future<void> _load() async {
    final backend = widget.backend;
    if (backend == null) return;
    final ticket = ++_ticket;
    setState(() => _loadError = null);
    try {
      await _read(backend);
      if (ticket != _ticket) return;
    } catch (error) {
      if (!mounted || ticket != _ticket) return;
      setState(() => _loadError = _describe(error));
    }
  }

  Future<void> _makeDefault(String id) async {
    final backend = widget.backend;
    final settings = widget.settings;
    if (backend == null || settings == null) return;
    final ticket = ++_ticket;
    setState(() {
      _making = id;
      _makeError = null;
    });
    try {
      final change = await settings.set('model.main', id);
      await _read(backend);
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _making = null;
        if (change.applied == SettingApplied.restartRequired) {
          _restartModel = id;
        }
      });
    } catch (error) {
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _making = null;
        _makeError = 'Could not make $id the default. ${_describe(error)}';
      });
    }
  }

  /// Sends [provider]'s model traffic through the saved host [id], or
  /// directly when [id] is null.
  Future<void> _setVia(String provider, String? id) async {
    final backend = widget.backend;
    final settings = widget.settings;
    if (backend == null || settings == null || _viaSaving != null) return;
    if (_via[provider] == id) return;
    final ticket = ++_ticket;
    setState(() {
      _viaSaving = provider;
      _viaError = null;
      _viaErrorFor = null;
    });
    try {
      await settings.set('providers.$provider.via', id);
      await _read(backend);
      if (!mounted || ticket != _ticket) return;
      setState(() => _viaSaving = null);
    } catch (error) {
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _viaSaving = null;
        _viaErrorFor = provider;
        _viaError = _describe(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final backend = widget.backend;
    final setup = _setup;
    final Widget body;
    if (backend == null) {
      body = const _Note(
        'The host is not running. Start it in Core to see its providers.',
        key: ValueKey('models-no-host'),
      );
    } else if (!_supported) {
      body = const _Note(
        'This host does not report its providers. Update BubblePaw Core to '
        'see them here.',
        key: ValueKey('models-unsupported'),
      );
    } else if (setup == null) {
      body = _loadError == null
          ? const _Note('Loading providers…')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Could not load the providers. $_loadError',
                  key: const ValueKey('provider-load-error'),
                  style: ts(theme.typeScale.ui, theme.dangerInk),
                ),
                const SizedBox(height: 8),
                SecondaryButton(
                  key: const ValueKey('provider-retry'),
                  label: 'Try again',
                  height: 32,
                  onTap: _load,
                ),
              ],
            );
    } else {
      body = _Providers(
        setup: setup,
        current: _default,
        restartModel: _restartModel,
        onMakeDefault: widget.settings == null ? null : _makeDefault,
        making: _making,
        error: _makeError,
        via: widget.settings == null ? null : _via,
        hosts: widget.hosts,
        viaSaving: _viaSaving,
        viaErrorFor: _viaErrorFor,
        viaError: _viaError,
        onVia: _setVia,
      );
    }
    return SettingsPage(
      title: 'Models',
      onBack: widget.onBack,
      backKey: const ValueKey('settings-page-back'),
      children: [body],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Text(text, style: ts(theme.typeScale.ui, theme.muted));
  }
}

/// The provider kinds whose `via` the host accepts (Core v0.11.0).
const _viaKinds = {
  'codex',
  'responses',
  'chat-completions',
  'anthropic-messages',
};

class _Providers extends StatelessWidget {
  const _Providers({
    required this.current,
    required this.restartModel,
    required this.setup,
    required this.onMakeDefault,
    required this.making,
    required this.error,
    required this.via,
    required this.hosts,
    required this.viaSaving,
    required this.viaErrorFor,
    required this.viaError,
    required this.onVia,
  });

  final ProviderSetup setup;
  final String? current;

  /// A model saved as the default that the host applies after a restart.
  final String? restartModel;
  final ValueChanged<String>? onMakeDefault;
  final String? making;
  final String? error;

  /// Each provider's `via`; null when the host has no settings to read.
  final Map<String, String>? via;
  final HostsController? hosts;
  final String? viaSaving;
  final String? viaErrorFor;
  final String? viaError;
  final void Function(String provider, String? id) onVia;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final pending =
        restartModel == null &&
        setup.reloadNeeded &&
        setup.main != setup.activeMain;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsHeading('Default model'),
        Text(
          setup.reloadNeeded
              ? 'The configuration changed and the host has not applied it. '
                    'New runs keep using this model until the host reloads.'
              : 'New runs in every chat use this model. A run in progress '
                    'keeps its own.',
          style: ts(theme.typeScale.uiSmall, theme.muted),
        ),
        const SizedBox(height: 6),
        Text(
          current ?? 'None set',
          key: const ValueKey('provider-default'),
          style: ts(
            theme.typeScale.body,
            current == null ? theme.faint : theme.ink,
            mono: current != null,
          ),
        ),
        if (restartModel != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Saved as $restartModel. Applies after restart.',
              key: const ValueKey('provider-restart'),
              style: ts(theme.typeScale.uiSmall, theme.muted),
            ),
          ),
        if (pending)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Saved as ${setup.main}.',
              key: const ValueKey('provider-saved'),
              style: ts(theme.typeScale.uiSmall, theme.muted),
            ),
          ),
        const SettingsHeading('Providers', top: 24),
        if (setup.providers.isEmpty)
          Text(
            'No providers are configured on this host. Add one to the host '
            'configuration, then reload it.',
            key: const ValueKey('provider-empty'),
            style: ts(theme.typeScale.ui, theme.muted),
          ),
        for (final provider in setup.providers)
          _ProviderCard(
            key: ValueKey('provider-${provider.name}'),
            provider: provider,
            current: current,
            making: making,
            onMakeDefault: onMakeDefault,
            via:
                via == null ||
                    hosts == null ||
                    !_viaKinds.contains(provider.kind)
                ? null
                : _ViaPicker(
                    provider: provider.name,
                    current: via![provider.name],
                    hosts: hosts!,
                    saving: viaSaving,
                    error: viaErrorFor == provider.name ? viaError : null,
                    onChanged: (id) => onVia(provider.name, id),
                  ),
          ),
        if (error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              error!,
              key: const ValueKey('provider-error'),
              style: ts(theme.typeScale.ui, theme.dangerInk),
            ),
          ),
      ],
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    super.key,
    required this.provider,
    required this.current,
    required this.making,
    required this.onMakeDefault,
    this.via,
  });

  final ProviderInfo provider;
  final String? current;
  final String? making;
  final ValueChanged<String>? onMakeDefault;

  /// "Send model traffic through…"; null hides it.
  final Widget? via;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final needsKey = provider.keyEnv != null;
    final usable = provider.keyPresent || !needsKey;
    return GroupCard(
      header: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      provider.name,
                      style: ts(theme.typeScale.ui, theme.ink, weight: 700),
                    ),
                    Text(
                      provider.kind,
                      style: ts(
                        theme.typeScale.uiSmall,
                        theme.faint,
                        mono: true,
                      ),
                    ),
                  ],
                ),
                if (provider.baseUrl != null)
                  Text(
                    provider.baseUrl!,
                    style: ts(theme.typeScale.uiSmall, theme.faint, mono: true),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (!usable)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'The host did not find ${provider.keyEnv}. Set it for '
                      'the host and restart it to use this provider.',
                      key: ValueKey('provider-key-${provider.name}'),
                      style: ts(theme.typeScale.uiSmall, theme.muted),
                    ),
                  ),
                if (provider.models.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'This provider lists no models.',
                      style: ts(theme.typeScale.uiSmall, theme.muted),
                    ),
                  ),
              ],
            ),
          ),
          if (needsKey) ...[
            const SizedBox(width: 12),
            StatePill(
              provider.keyPresent ? 'Key set' : 'No key',
              tone: provider.keyPresent ? PillTone.good : PillTone.attention,
            ),
          ],
        ],
      ),
      children: [
        for (final model in provider.models)
          _ModelRow(
            key: ValueKey('model-${provider.qualify(model)}'),
            id: provider.qualify(model),
            label: model.id,
            isDefault: provider.qualify(model) == current,
            usable: usable,
            making: making == provider.qualify(model),
            busy: making != null,
            onMakeDefault: onMakeDefault,
          ),
        ?via,
      ],
    );
  }
}

/// "Send model traffic through…": Direct, and each saved host that granted
/// this device model traffic. A `via` that names a host that is no longer
/// saved, or no longer grants it, stays selected under its ID, unavailable.
class _ViaPicker extends StatelessWidget {
  const _ViaPicker({
    required this.provider,
    required this.current,
    required this.hosts,
    required this.saving,
    required this.error,
    required this.onChanged,
  });

  final String provider;
  final String? current;
  final HostsController hosts;

  /// The provider being saved; every option waits while one is.
  final String? saving;
  final String? error;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final key = 'via-$provider';
    final Widget body;
    if (!hosts.loaded) {
      body = Text(
        'Loading hosts…',
        style: ts(theme.typeScale.uiSmall, theme.muted),
      );
    } else if (hosts.error != null) {
      body = Text(
        hosts.error!,
        key: ValueKey('$key-hosts-error'),
        style: ts(theme.typeScale.uiSmall, theme.dangerInk),
      );
    } else {
      final granting = [
        for (final h in hosts.hosts)
          if (h.egress) h,
      ];
      final unavailable =
          current != null && !granting.any((h) => h.id == current);
      final busy = saving != null;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChoiceCard(
            key: ValueKey('$key-direct'),
            title: 'Direct',
            description: 'This computer connects to the provider itself.',
            selected: current == null,
            available: !busy,
            onTap: () => onChanged(null),
          ),
          for (final host in granting)
            ChoiceCard(
              key: ValueKey('$key-${host.id}'),
              title: host.label,
              description: 'Model requests pass through this host.',
              selected: current == host.id,
              available: !busy,
              onTap: () => onChanged(host.id),
            ),
          if (unavailable)
            ChoiceCard(
              key: ValueKey('$key-unavailable'),
              title: current!,
              description:
                  'Unavailable. This host is not saved here or does not '
                  'allow model traffic.',
              selected: true,
              available: false,
              onTap: () {},
            ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Send model traffic through…',
              style: ts(theme.typeScale.uiSmall, theme.muted, weight: 600),
            ),
          ),
          body,
          if (error != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  error!,
                  key: ValueKey('$key-error'),
                  style: ts(theme.typeScale.ui, theme.dangerInk),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A model: its name, and the Default mark or Make default. Make default
/// shows while the row is hovered or has focus at desktop widths, and always
/// at compact width, where there is no hover.
class _ModelRow extends StatefulWidget {
  const _ModelRow({
    super.key,
    required this.id,
    required this.label,
    required this.isDefault,
    required this.usable,
    required this.making,
    required this.busy,
    required this.onMakeDefault,
  });

  final String id;
  final String label;
  final bool isDefault;
  final bool usable;
  final bool making;
  final bool busy;
  final ValueChanged<String>? onMakeDefault;

  @override
  State<_ModelRow> createState() => _ModelRowState();
}

class _ModelRowState extends State<_ModelRow> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final compact = SizeClass.of(context).isCompact;
    final make = widget.onMakeDefault;
    final shown = compact || _hover || _focus || widget.making;
    final Widget? trailing = widget.isDefault
        ? const StatePill('Default', tone: PillTone.good)
        : make == null
        ? null
        : Opacity(
            opacity: shown ? 1 : 0,
            child: Semantics(
              button: true,
              label: 'Make ${widget.id} the default model',
              excludeSemantics: true,
              child: SecondaryButton(
                key: ValueKey('make-default-${widget.id}'),
                label: widget.making ? 'Making default…' : 'Make default',
                height: 28,
                onTap: !widget.usable || widget.busy
                    ? null
                    : () => make(widget.id),
              ),
            ),
          );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (value) => setState(() => _focus = value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: ts(theme.typeScale.ui, theme.ink, mono: true),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing],
            ],
          ),
        ),
      ),
    );
  }
}
