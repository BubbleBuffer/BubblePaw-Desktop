// Models: the host's default model and its providers, each with whether the
// host found the key and its models. The default model is the host setting
// `model.main`, read with config.get and changed with config.set. The host
// reports only whether a key is present; nothing here reads, shows or stores
// one.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../core/host_settings.dart';
import 'settings_widgets.dart';

class ModelsPage extends StatefulWidget {
  const ModelsPage({
    super.key,
    required this.backend,
    required this.settings,
    this.onBack,
  });

  /// The running backend; null while the host is not running.
  final AgentBackend? backend;

  /// The host's settings; null when the host has none to read or change.
  final HostSettings? settings;
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

  bool get _supported =>
      widget.backend?.capabilities.has(KitCapability.providers) ?? false;

  @override
  void initState() {
    super.initState();
    if (_supported) _load();
  }

  @override
  void didUpdateWidget(ModelsPage old) {
    super.didUpdateWidget(old);
    if (old.backend != widget.backend || old.settings != widget.settings) {
      _setup = null;
      _default = null;
      _restartModel = null;
      _loadError = null;
      _makeError = null;
      _making = null;
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
    });
  }

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

class _Providers extends StatelessWidget {
  const _Providers({
    required this.current,
    required this.restartModel,
    required this.setup,
    required this.onMakeDefault,
    required this.making,
    required this.error,
  });

  final ProviderSetup setup;
  final String? current;

  /// A model saved as the default that the host applies after a restart.
  final String? restartModel;
  final ValueChanged<String>? onMakeDefault;
  final String? making;
  final String? error;

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
  });

  final ProviderInfo provider;
  final String? current;
  final String? making;
  final ValueChanged<String>? onMakeDefault;

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
      ],
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
