// Parts for the Core page, About's Updates and the update dialog: a button
// with a Lucide glyph, a progress line, a notice and key/value rows.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app_tokens.dart';
import 'settings_widgets.dart';

const LucideGlyph glyphDownload = (
  LucideIcons.download300,
  LucideIcons.download,
  LucideIcons.download500,
);
const LucideGlyph glyphRefresh = (
  LucideIcons.refreshCw300,
  LucideIcons.refreshCw,
  LucideIcons.refreshCw500,
);
const LucideGlyph glyphAlert = (
  LucideIcons.circleAlert300,
  LucideIcons.circleAlert,
  LucideIcons.circleAlert500,
);
const LucideGlyph glyphCheckCircle = (
  LucideIcons.circleCheck300,
  LucideIcons.circleCheck,
  LucideIcons.circleCheck500,
);
const LucideGlyph glyphTrash = (
  LucideIcons.trash2300,
  LucideIcons.trash2,
  LucideIcons.trash2500,
);
const LucideGlyph glyphExternal = (
  LucideIcons.externalLink300,
  LucideIcons.externalLink,
  LucideIcons.externalLink500,
);

enum ActionKind { primary, outline, quiet }

/// A 36 px button: [ActionKind.primary] is the one action of a view,
/// [ActionKind.outline] a plain one and [ActionKind.quiet] text only.
class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.kind = ActionKind.outline,
    this.glyph,
  });

  final String label;
  final VoidCallback onTap;
  final ActionKind kind;
  final LucideGlyph? glyph;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final primary = kind == ActionKind.primary;
    final ink = primary ? theme.onAccent : theme.ink;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Hover(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        background: switch (kind) {
          ActionKind.primary => theme.accent,
          ActionKind.outline => theme.surface,
          ActionKind.quiet => null,
        },
        hoverBackground: primary ? theme.accentHover : null,
        pressedBackground: primary ? theme.accentHover : null,
        border: kind == ActionKind.outline
            ? Border.all(color: theme.thread)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: ControlSize.lg.height),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (glyph != null) ...[
                glyphIcon(glyph!, size: IconSize.sm, color: ink),
                const Gap(Space.xs),
              ],
              Text(
                label,
                style: ts(
                  theme.typeScale.ui,
                  kind == ActionKind.quiet ? theme.muted : ink,
                  weight: Weight.strong,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A determinate bar. [value] is 0 to 1; null shows an empty track.
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.value, required this.label});

  final double? value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final fraction = (value ?? 0).clamp(0.0, 1.0);
    return Semantics(
      label: label,
      value: '${(fraction * 100).round()}%',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.sm),
          child: SizedBox(
            height: SettingsSizes.progressBar,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: theme.surface2)),
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: fraction,
                    child: ColoredBox(color: theme.accent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum NoticeTone { danger, attention, good, info }

/// A short block of words with a glyph, for something that went wrong, needs
/// care, or worked.
class NoticeBox extends StatelessWidget {
  const NoticeBox({
    super.key,
    required this.tone,
    required this.child,
    this.trailing,
  });

  final NoticeTone tone;
  final Widget child;

  /// An action at the end of the notice.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final (Color fill, Color ink, LucideGlyph glyph) = switch (tone) {
      NoticeTone.danger => (theme.danger, theme.dangerInk, glyphAlert),
      NoticeTone.attention => (theme.attention, theme.attentionInk, glyphAlert),
      NoticeTone.good => (
        theme.constructive,
        theme.constructiveInk,
        glyphCheckCircle,
      ),
      NoticeTone.info => (theme.information, theme.informationInk, glyphInfo),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: Space.hair),
              child: glyphIcon(glyph, size: IconSize.sm, color: ink),
            ),
            const Gap(Space.sm),
            Expanded(
              child: DefaultTextStyle(
                style: ts(theme.typeScale.ui, ink),
                child: child,
              ),
            ),
            if (trailing != null) ...[const Gap(Space.md), trailing!],
          ],
        ),
      ),
    );
  }
}

/// One line of a key/value table: a muted name and a value, mono by default.
class SettingsKeyValueRow extends StatelessWidget {
  const SettingsKeyValueRow(
    this.name,
    this.value, {
    super.key,
    this.valueKey,
    this.mono = true,
    this.trailing,
  });

  final String name;
  final String value;
  final Key? valueKey;
  final bool mono;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      child: Row(
        children: [
          SizedBox(
            width: SettingsSizes.factLabel,
            child: Text(
              name,
              style: ts(
                theme.typeScale.ui,
                theme.muted,
                weight: Weight.regular,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              key: valueKey,
              style: ts(
                theme.typeScale.ui,
                theme.ink,
                mono: mono,
                weight: mono ? Weight.regular : null,
              ),
            ),
          ),
          if (trailing != null) ...[const Gap(Space.sm), trailing!],
        ],
      ),
    );
  }
}

/// A text link that opens in the browser.
class LinkButton extends StatelessWidget {
  const LinkButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      link: true,
      label: label,
      excludeSemantics: true,
      child: Hover(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        padding: const EdgeInsets.symmetric(vertical: Space.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: ts(
                theme.typeScale.ui,
                theme.accentInk,
                weight: Weight.strong,
              ),
            ),
            const Gap(Space.xxs),
            glyphIcon(glyphExternal, size: IconSize.xs, color: theme.accentInk),
          ],
        ),
      ),
    );
  }
}

/// `12.3 of 42.1 MB`
String megabytes(int received, int? total) {
  String mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
  return total == null
      ? '${mb(received)} MB'
      : '${mb(received)} of ${mb(total)} MB';
}
