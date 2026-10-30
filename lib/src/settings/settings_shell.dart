// Settings: General, Models, Feedback and About. At expanded and medium width a
// section list sits on the left and the page beside it; at compact width the
// list is the first screen and a section is pushed over it.
// Remote access joins the list with the remote work.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/foundation.dart' show LicenseEntry;
import 'package:flutter/widgets.dart';

import '../feedback/feedback_controller.dart';
import '../feedback/glyphs.dart';
import '../host_controller.dart';
import '../platform/releases.dart';
import '../versions.dart';
import 'about_page.dart';
import 'feedback_page.dart';
import 'general_page.dart';
import 'licences_page.dart';
import 'models_page.dart';
import 'settings_section.dart';
import 'settings_widgets.dart';

class SettingsShell extends StatefulWidget {
  const SettingsShell({
    super.key,
    required this.controller,
    required this.feedback,
    required this.onSendFeedback,
    this.services = const PlatformServices(),
    this.onClose,
    this.licenceSource = LicencesPage.defaultSource,
  });

  final HostController controller;

  final PlatformServices services;

  /// The saved feedback, for the Feedback page and About.
  final FeedbackController feedback;

  /// Opens the feedback sheet.
  final VoidCallback onSendFeedback;

  /// Leave settings for the chat. Null when there is no chat to go back to.
  final VoidCallback? onClose;

  final Stream<LicenseEntry> Function() licenceSource;

  @override
  State<SettingsShell> createState() => _SettingsShellState();
}

class _SettingsShellState extends State<SettingsShell> {
  // Null at compact width is the list of sections; at wider widths, General.
  late SettingsSection? _section = widget.controller.settingsSection;
  bool _licences = false;

  @override
  void initState() {
    super.initState();
    widget.feedback.addListener(_feedbackChanged);
  }

  void _feedbackChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.feedback.removeListener(_feedbackChanged);
    super.dispose();
  }

  void _select(SettingsSection? section) => setState(() {
    _section = section;
    _licences = false;
  });

  String _summary(SettingsSection section) => switch (section) {
    SettingsSection.general => themeSummary(widget.controller.prefs.theme),
    SettingsSection.models => 'Default model and providers',
    SettingsSection.feedback => switch (widget.feedback.reports.length) {
      0 => 'No reports saved',
      1 => '1 report saved',
      final n => '$n reports saved',
    },
    SettingsSection.about => 'BubblePaw $appVersion',
  };

  LucideGlyph _glyph(SettingsSection section) => switch (section) {
    SettingsSection.general => glyphSliders,
    SettingsSection.models => glyphLayers,
    SettingsSection.feedback => glyphMessageSquareText,
    SettingsSection.about => glyphInfo,
  };

  Widget _page(SettingsSection section, {VoidCallback? onBack}) {
    final host = widget.controller;
    return switch (section) {
      SettingsSection.general => GeneralPage(
        key: const ValueKey('page-general'),
        controller: host,
        onBack: onBack,
      ),
      SettingsSection.models => ModelsPage(
        key: const ValueKey('page-models'),
        backend: host.phase == HostPhase.running ? host.backend : null,
        onBack: onBack,
      ),
      SettingsSection.feedback => FeedbackPage(
        key: const ValueKey('page-feedback'),
        feedback: widget.feedback,
        onSend: widget.onSendFeedback,
        onBack: onBack,
      ),
      SettingsSection.about =>
        _licences
            ? LicencesPage(
                key: const ValueKey('page-licences'),
                source: widget.licenceSource,
                onBack: () => setState(() => _licences = false),
              )
            : AboutPage(
                key: const ValueKey('page-about'),
                controller: host,
                feedback: widget.feedback,
                services: widget.services,
                onSendFeedback: widget.onSendFeedback,
                onViewFeedback: () => _select(SettingsSection.feedback),
                onLicences: () => setState(() => _licences = true),
                onBack: onBack,
              ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return ColoredBox(
      color: theme.canvas,
      child: SizeClassBuilder(
        builder: (context, size) {
          if (size.isCompact) {
            final section = _section;
            if (section != null) {
              return _page(section, onBack: () => _select(null));
            }
            return SettingsPage(
              title: 'Settings',
              onBack: widget.onClose,
              backKey: const ValueKey('settings-back'),
              children: [
                for (final s in SettingsSection.values)
                  _ListRow(
                    key: ValueKey('settings-nav-${s.name}'),
                    title: s.title,
                    summary: _summary(s),
                    glyph: _glyph(s),
                    onTap: () => _select(s),
                  ),
              ],
            );
          }
          final section = _section ?? SettingsSection.general;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Nav(
                selected: section,
                glyphOf: _glyph,
                onSelect: _select,
                onClose: widget.onClose,
              ),
              Expanded(child: _page(section)),
            ],
          );
        },
      ),
    );
  }
}

class _Nav extends StatelessWidget {
  const _Nav({
    required this.selected,
    required this.glyphOf,
    required this.onSelect,
    required this.onClose,
  });

  final SettingsSection selected;
  final LucideGlyph Function(SettingsSection) glyphOf;
  final ValueChanged<SettingsSection> onSelect;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return SizedBox(
      width: 240,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: theme.seam)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (onClose != null)
                Hover(
                  key: const ValueKey('settings-back'),
                  onTap: onClose,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon20(Ico.chevronLeft, size: 16, color: theme.muted),
                      const SizedBox(width: 12),
                      Text(
                        'Back to chat',
                        style: ts(theme.typeScale.ui, theme.muted),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 16, 10, 12),
                child: Semantics(
                  header: true,
                  child: Text(
                    'Settings',
                    style: ts(theme.typeScale.h2, theme.ink, weight: 600),
                  ),
                ),
              ),
              for (final s in SettingsSection.values)
                _NavItem(
                  key: ValueKey('settings-nav-${s.name}'),
                  title: s.title,
                  glyph: glyphOf(s),
                  selected: s == selected,
                  onTap: () => onSelect(s),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.title,
    required this.glyph,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final LucideGlyph glyph;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      excludeSemantics: true,
      child: Hover(
        onTap: onTap,
        selected: selected,
        selectedColor: theme.pressed,
        lift: 0,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            glyphIcon(glyph, color: selected ? theme.ink : theme.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: ts(
                  theme.typeScale.ui,
                  theme.ink,
                  weight: selected ? 600 : 400,
                ),
              ),
            ),
            if (selected)
              Container(
                width: 3,
                height: 18,
                decoration: BoxDecoration(
                  color: theme.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    super.key,
    required this.title,
    required this.summary,
    required this.glyph,
    required this.onTap,
  });

  final String title;
  final String summary;
  final LucideGlyph glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      button: true,
      label: '$title. $summary',
      excludeSemantics: true,
      child: Hover(
        onTap: onTap,
        lift: 0,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            glyphIcon(glyph, size: 20, color: theme.muted),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: ts(theme.typeScale.body, theme.ink, weight: 600),
                  ),
                  Text(
                    summary,
                    style: ts(theme.typeScale.uiSmall, theme.muted),
                  ),
                ],
              ),
            ),
            Icon20(Ico.chevronRight, size: 18, color: theme.muted),
          ],
        ),
      ),
    );
  }
}
