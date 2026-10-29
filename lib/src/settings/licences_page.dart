// Licences: the open source licences bundled with the app, from Flutter's
// LicenseRegistry plus the font licences main registers. Grouped, searchable,
// each expandable to its text.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/foundation.dart' show LicenseEntry, LicenseRegistry;
import 'package:flutter/widgets.dart';

import 'settings_widgets.dart';

/// One package (or font) and the licence text(s) that cover it.
class LicenceRecord {
  LicenceRecord(this.name, this.group);

  final String name;
  final String group;
  final List<String> texts = [];

  /// The licences the texts look like, such as `MIT`; empty when none is
  /// recognised.
  List<String> get kinds {
    final found = <String>{};
    for (final text in texts) {
      final kind = guessLicence(text);
      if (kind != null) found.add(kind);
    }
    return found.toList();
  }
}

/// The licence [text] looks like, by its well-known wording; null otherwise.
String? guessLicence(String text) {
  final lower = text.toLowerCase();
  if (lower.contains('sil open font license')) return 'OFL-1.1';
  if (lower.contains('apache license')) return 'Apache-2.0';
  if (lower.contains('mozilla public license')) return 'MPL-2.0';
  if (lower.contains('redistribution and use in source and binary forms')) {
    return lower.contains('neither the name') ? 'BSD-3-Clause' : 'BSD-2-Clause';
  }
  if (lower.contains('permission is hereby granted, free of charge')) {
    return 'MIT';
  }
  if (lower.contains('permission to use, copy, modify, and/or distribute')) {
    return 'ISC';
  }
  return null;
}

const _fontNames = ['Hyperlegible', 'Fragment Mono', 'Bricolage'];

/// The group a package belongs to in the list.
String licenceGroup(String name) {
  if (_fontNames.any(name.contains)) return 'Fonts';
  if (name.toLowerCase().contains('lucide')) return 'Icons';
  return 'App packages';
}

const _groupOrder = ['App packages', 'Fonts', 'Icons'];

/// Reads every entry of [source] into records, one per package.
Future<List<LicenceRecord>> loadLicences(Stream<LicenseEntry> source) async {
  final byName = <String, LicenceRecord>{};
  await for (final entry in source) {
    final text = entry.paragraphs.map((p) => p.text).join('\n');
    for (final name in entry.packages) {
      final record = byName.putIfAbsent(
        name,
        () => LicenceRecord(name, licenceGroup(name)),
      );
      if (!record.texts.contains(text)) record.texts.add(text);
    }
  }
  final records = byName.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return records;
}

class LicencesPage extends StatefulWidget {
  const LicencesPage({
    super.key,
    required this.onBack,
    this.source = defaultSource,
  });

  /// Back to About.
  final VoidCallback onBack;

  /// Where the entries come from; tests pass their own.
  final Stream<LicenseEntry> Function() source;

  static Stream<LicenseEntry> defaultSource() => LicenseRegistry.licenses;

  @override
  State<LicencesPage> createState() => _LicencesPageState();
}

class _LicencesPageState extends State<LicencesPage> {
  final _search = TextEditingController();
  final _open = <String>{};
  List<LicenceRecord>? _records;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final records = await loadLicences(widget.source());
      if (!mounted) return;
      setState(() => _records = records);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final query = _search.text.trim().toLowerCase();
    final records = _records;
    final shown = records == null
        ? const <LicenceRecord>[]
        : [
            for (final r in records)
              if (query.isEmpty ||
                  r.name.toLowerCase().contains(query) ||
                  r.kinds.any((k) => k.toLowerCase().contains(query)))
                r,
          ];
    return SettingsPage(
      title: 'Licences',
      onBack: widget.onBack,
      backKey: const ValueKey('settings-page-back'),
      children: [
        // The compact top bar has its own back button.
        if (!SizeClass.of(context).isCompact) ...[
          Row(
            children: [
              TextBtn(
                'About',
                key: const ValueKey('licences-back'),
                onTap: widget.onBack,
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        SettingsRow(
          label: 'Search',
          stack: true,
          trailing: SettingsField(
            controller: _search,
            placeholder: 'Package or licence',
            fieldKey: const ValueKey('licences-search'),
          ),
        ),
        if (_failed)
          Text(
            'The licences could not be read from this build.',
            key: const ValueKey('licences-error'),
            style: ts(theme.typeScale.ui, theme.dangerInk),
          )
        else if (records == null)
          Text('Loading licences…', style: ts(theme.typeScale.ui, theme.muted))
        else if (shown.isEmpty)
          Text(
            'Nothing matches “${_search.text.trim()}”.',
            key: const ValueKey('licences-empty'),
            style: ts(theme.typeScale.ui, theme.muted),
          ),
        for (final group in _groupOrder)
          ..._groupRows(context, group, [
            for (final r in shown)
              if (r.group == group) r,
          ]),
      ],
    );
  }

  List<Widget> _groupRows(
    BuildContext context,
    String group,
    List<LicenceRecord> rows,
  ) {
    if (rows.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Row(children: [Expanded(child: SettingsHeading(group))]),
      ),
      for (final r in rows)
        _LicenceRow(
          key: ValueKey('licence-${r.name}'),
          record: r,
          open: _open.contains(r.name),
          onToggle: () => setState(() {
            if (!_open.remove(r.name)) _open.add(r.name);
          }),
        ),
    ];
  }
}

class _LicenceRow extends StatelessWidget {
  const _LicenceRow({
    super.key,
    required this.record,
    required this.open,
    required this.onToggle,
  });

  final LicenceRecord record;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: open,
          label: '${record.name} licence',
          excludeSemantics: true,
          child: Hover(
            onTap: onToggle,
            lift: 0,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    record.name,
                    style: ts(theme.typeScale.ui, theme.ink),
                  ),
                ),
                for (final kind in record.kinds) ...[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.thread),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        kind,
                        style: ts(
                          theme.typeScale.uiSmall,
                          theme.muted,
                          weight: 600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                const SizedBox(width: 6),
                open
                    ? glyphIcon(glyphChevronUp, size: 16, color: theme.muted)
                    : Icon20(Ico.chevronDown, size: 16, color: theme.muted),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.surface2,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  record.texts.join('\n\n'),
                  key: ValueKey('licence-text-${record.name}'),
                  style: ts(theme.typeScale.uiSmall, theme.ink, mono: true),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
