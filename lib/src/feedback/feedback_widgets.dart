// Small parts the feedback sheet, the Feedback page and the saved
// confirmation share: buttons, an icon button, a disclosure row and a block
// of monospace text with its redactions marked.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../settings/settings_widgets.dart' show glyphChevronUp, glyphIcon;
import 'glyphs.dart';
import 'redact.dart';

enum FbButtonKind { primary, normal, quiet, danger }

/// A labelled button, 36 px high, with an optional glyph before the label.
/// A null [onTap] dims it and makes it inert.
class FbButton extends StatelessWidget {
  const FbButton({
    super.key,
    required this.label,
    required this.onTap,
    this.glyph,
    this.kind = FbButtonKind.normal,
  });

  final String label;
  final VoidCallback? onTap;
  final LucideGlyph? glyph;
  final FbButtonKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final enabled = onTap != null;
    final primary = kind == FbButtonKind.primary;
    final Color ink = !enabled
        ? theme.faint
        : primary
        ? theme.onAccent
        : kind == FbButtonKind.danger
        ? theme.dangerInk
        : theme.ink;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Hover(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        background: primary
            ? (enabled ? theme.accent : theme.surface2)
            : kind == FbButtonKind.quiet
            ? null
            : theme.canvas,
        hoverBackground: primary && enabled ? theme.accentHover : null,
        border: kind == FbButtonKind.quiet || (primary && enabled)
            ? null
            : Border.all(
                color: kind == FbButtonKind.danger && enabled
                    ? theme.danger
                    : theme.thread,
              ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          height: 36,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (glyph != null) ...[
                glyphIcon(glyph!, size: 16, color: ink),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: ts(theme.typeScale.ui, ink, weight: primary ? 700 : 600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A square icon button with a tooltip-style label for assistive tools.
class FbIconButton extends StatelessWidget {
  const FbIconButton({
    super.key,
    required this.glyph,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final LucideGlyph glyph;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Hover(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: glyphIcon(
              glyph,
              size: 18,
              color: danger ? theme.dangerInk : theme.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// A row that opens and closes a block: chevron, [title], and [summary] at
/// the right.
class DisclosureRow extends StatelessWidget {
  const DisclosureRow({
    super.key,
    required this.title,
    required this.summary,
    required this.expanded,
    required this.onTap,
  });

  final String title;
  final String summary;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      button: true,
      expanded: expanded,
      label: '$title. $summary',
      excludeSemantics: true,
      child: Hover(
        onTap: onTap,
        lift: 0,
        borderRadius: BorderRadius.circular(6),
        background: theme.surface2,
        border: Border.all(color: theme.seam),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              glyphIcon(
                expanded ? glyphChevronUp : glyphChevronDown,
                size: 16,
                color: theme.muted,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: ts(theme.typeScale.ui, theme.ink, weight: 600),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  summary,
                  overflow: TextOverflow.ellipsis,
                  style: ts(theme.typeScale.uiSmall, theme.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Monospace [text] in a scrolling box, each [redacted] marked.
class FbCodeBlock extends StatelessWidget {
  const FbCodeBlock({
    super.key,
    required this.text,
    required this.label,
    this.height = 220,
  });

  final String text;
  final String label;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final base = ts(theme.typeScale.uiSmall, theme.codeInk, mono: true);
    final mark = base.copyWith(
      backgroundColor: theme.attention,
      color: theme.attentionInk,
    );
    final spans = <InlineSpan>[];
    var from = 0;
    for (final m in redacted.allMatches(text)) {
      if (m.start > from) {
        spans.add(TextSpan(text: text.substring(from, m.start)));
      }
      spans.add(TextSpan(text: redacted, style: mark));
      from = m.end;
    }
    if (from < text.length) spans.add(TextSpan(text: text.substring(from)));
    return Semantics(
      container: true,
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.codeBackground,
          border: Border.all(color: theme.seam),
          borderRadius: BorderRadius.circular(6),
        ),
        child: SizedBox(
          height: height,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: Text.rich(TextSpan(style: base, children: spans)),
          ),
        ),
      ),
    );
  }
}
