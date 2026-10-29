// Parts for the Core page, About's Updates and the update dialog: a button
// with a Lucide glyph, a progress line, a notice and key/value rows.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
        borderRadius: BorderRadius.circular(6),
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
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          height: 36,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (glyph != null) ...[
                glyphIcon(glyph!, size: 16, color: ink),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: ts(
                  theme.typeScale.ui,
                  kind == ActionKind.quiet ? theme.muted : ink,
                  weight: primary ? 700 : 600,
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
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
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
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: glyphIcon(glyph, size: 16, color: ink),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DefaultTextStyle(
                style: ts(theme.typeScale.ui, ink),
                child: child,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

/// One line of a key/value table: a muted name and a value, mono by default.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            child: Text(name, style: ts(theme.typeScale.ui, theme.muted)),
          ),
          Expanded(
            child: Text(
              value,
              key: valueKey,
              style: ts(theme.typeScale.ui, theme.ink, mono: mono),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
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
        borderRadius: BorderRadius.circular(4),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: ts(theme.typeScale.ui, theme.accentInk, weight: 600),
            ),
            const SizedBox(width: 4),
            glyphIcon(glyphExternal, size: 13, color: theme.accentInk),
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
