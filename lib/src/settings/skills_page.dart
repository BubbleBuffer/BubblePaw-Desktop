// Skills: the skills the host discovered, each with where it came from and an
// on/off switch. The list is `skills.list`; a switch is the host setting
// `skills.<name>.enabled`, which applies at the next turn. A skill the host
// skipped or that is not valid is not listed.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../core/host_settings.dart';
import 'settings_widgets.dart';

class SkillsPage extends StatefulWidget {
  const SkillsPage({super.key, required this.settings, this.onBack});

  /// The host's settings; null while the host is not running.
  final HostSettings? settings;
  final VoidCallback? onBack;

  @override
  State<SkillsPage> createState() => _SkillsPageState();
}

class _SkillsPageState extends State<SkillsPage> {
  HostSkills? _skills;
  String? _loadError;
  String? _error;
  bool _restart = false;
  final _saving = <String>{};
  int _ticket = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SkillsPage old) {
    super.didUpdateWidget(old);
    if (old.settings != widget.settings) {
      _skills = null;
      _load();
    }
  }

  static String _describe(Object error) => switch (error) {
    HostSettingsException() => error.message,
    _ => 'Something went wrong.',
  };

  Future<void> _load() async {
    final settings = widget.settings;
    if (settings == null) return;
    final ticket = ++_ticket;
    try {
      final skills = await settings.skills();
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _skills = skills;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted || ticket != _ticket) return;
      setState(() => _loadError = _describe(error));
    }
  }

  Future<void> _toggle(HostSkill skill, bool on) async {
    final settings = widget.settings;
    if (settings == null || !_saving.add(skill.name)) return;
    setState(() => _error = null);
    try {
      final change = await settings.set('skills.${skill.name}.enabled', on);
      if (change.applied == SettingApplied.restartRequired) _restart = true;
    } catch (error) {
      _error =
          'Could not turn ${skill.name} ${on ? 'on' : 'off'}. '
          '${_describe(error)}';
    }
    await _load();
    if (mounted) setState(() => _saving.remove(skill.name));
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final skills = _skills;
    final Widget body;
    if (widget.settings == null) {
      body = Text(
        'The host is not running. Start it in Core to see its skills.',
        key: const ValueKey('skills-no-host'),
        style: ts(theme.typeScale.ui, theme.muted),
      );
    } else if (skills == null) {
      body = _loadError == null
          ? Text('Loading skills…', style: ts(theme.typeScale.ui, theme.muted))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Could not load the skills. $_loadError',
                  key: const ValueKey('skills-load-error'),
                  style: ts(theme.typeScale.ui, theme.dangerInk),
                ),
                const SizedBox(height: 8),
                SecondaryButton(
                  key: const ValueKey('skills-retry'),
                  label: 'Try again',
                  height: 32,
                  onTap: _load,
                ),
              ],
            );
    } else if (skills.skills.isEmpty) {
      body = const _EmptySkills();
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final skill in skills.skills)
            _SkillRow(
              key: ValueKey('skill-${skill.name}'),
              skill: skill,
              onChanged: _saving.contains(skill.name)
                  ? null
                  : (on) => _toggle(skill, on),
            ),
        ],
      );
    }
    return SettingsPage(
      title: 'Skills',
      onBack: widget.onBack,
      backKey: const ValueKey('settings-page-back'),
      children: [
        const SettingsHeading('Discovered skills'),
        body,
        if (_restart)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Applies after restart.',
              key: const ValueKey('skills-restart'),
              style: ts(theme.typeScale.uiSmall, theme.muted),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                key: const ValueKey('skills-error'),
                style: ts(theme.typeScale.ui, theme.dangerInk),
              ),
            ),
          ),
      ],
    );
  }
}

/// The folder a skill was found in, as it is shown: the part of its
/// `SKILL.md` path above the skill's own folder. A skill under the user's
/// `.config/bubblepaw/skills` shows as `~/.config/bubblepaw/skills`; one in
/// the workspace shows the last two folders, such as `.claude/skills`.
String skillFolder(HostSkill skill) {
  final parts = skill.path.replaceAll('\\', '/').split('/')
    ..removeWhere((p) => p.isEmpty);
  if (parts.length < 3) return skill.path;
  // Drop SKILL.md and the skill's folder.
  final dirs = parts.sublist(0, parts.length - 2);
  final user =
      dirs.length >= 3 &&
      dirs[dirs.length - 3] == '.config' &&
      dirs[dirs.length - 2] == 'bubblepaw' &&
      dirs.last == 'skills';
  if (user) return '~/.config/bubblepaw/skills';
  final tail = dirs.length >= 2 ? dirs.sublist(dirs.length - 2) : dirs;
  return tail.join('/');
}

class _SkillRow extends StatelessWidget {
  const _SkillRow({super.key, required this.skill, required this.onChanged});

  final HostSkill skill;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final where = skill.source == 'user' ? 'User' : 'Project';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  skill.name,
                  style: ts(
                    theme.typeScale.ui,
                    theme.ink,
                    weight: 600,
                    mono: true,
                  ),
                ),
                if (skill.description.isNotEmpty)
                  Text(
                    skill.description,
                    style: ts(theme.typeScale.uiSmall, theme.muted),
                  ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      where,
                      style: ts(theme.typeScale.uiSmall, theme.faint),
                    ),
                    Text(
                      skillFolder(skill),
                      style: ts(
                        theme.typeScale.uiSmall,
                        theme.muted,
                        mono: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _SkillSwitch(
            name: skill.name,
            value: skill.enabled,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SkillSwitch extends StatelessWidget {
  const _SkillSwitch({
    required this.name,
    required this.value,
    required this.onChanged,
  });

  final String name;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      label: 'Skill $name',
      toggled: value,
      enabled: onChanged != null,
      child: Opacity(
        opacity: onChanged == null ? .5 : 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Toggle(
              key: ValueKey('toggle-skill-$name'),
              value: value,
              onChanged: onChanged,
            ),
            SizedBox(
              width: 28,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  value ? 'On' : 'Off',
                  style: ts(theme.typeScale.uiSmall, theme.muted, weight: 600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySkills extends StatelessWidget {
  const _EmptySkills();

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Column(
      key: const ValueKey('skills-empty'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'No skills found. BubblePaw looks in these folders:',
          style: ts(theme.typeScale.uiSmall, theme.muted),
        ),
        const SizedBox(height: 8),
        for (final dir in const [
          '.agents/skills',
          '.claude/skills',
          '~/.config/bubblepaw/skills',
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              dir,
              style: ts(theme.typeScale.ui, theme.ink, mono: true),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'A skill you add to one of them appears here.',
          style: ts(theme.typeScale.uiSmall, theme.muted),
        ),
      ],
    );
  }
}
