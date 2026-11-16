// Parts shared by the settings pages: a page frame, a labelled switch, a
// segmented choice, a radio card and a state pill. Built from the kit's tokens
// and bb_ui's primitives; nothing here draws an icon of its own.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app_tokens.dart';

// Lucide glyphs that bb_ui's Ico enum lacks. The kit names its own the same
// way; they move to Ico when bb_ui gains them.
const LucideGlyph glyphSliders = (
  LucideIcons.slidersHorizontal300,
  LucideIcons.slidersHorizontal,
  LucideIcons.slidersHorizontal500,
);
const LucideGlyph glyphCpu = (
  LucideIcons.cpu300,
  LucideIcons.cpu,
  LucideIcons.cpu500,
);
const LucideGlyph glyphLayers = (
  LucideIcons.layers300,
  LucideIcons.layers,
  LucideIcons.layers500,
);
const LucideGlyph glyphInfo = (
  LucideIcons.info300,
  LucideIcons.info,
  LucideIcons.info500,
);
const LucideGlyph glyphChevronUp = (
  LucideIcons.chevronUp300,
  LucideIcons.chevronUp,
  LucideIcons.chevronUp500,
);

/// [glyph] at [size] in [color], hidden from semantics.
Widget glyphIcon(
  LucideGlyph glyph, {
  IconSize size = IconSize.md,
  required Color color,
}) => ExcludeSemantics(
  child: LucideIcon(
    lucideWeight(glyph, size.px, Stroke.regular),
    size: size.px,
    color: color,
  ),
);

/// One settings page: a title (a top bar with a back button at compact
/// width) over [children], scrolling, no wider than 640.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.title,
    required this.children,
    this.onBack,
    this.backKey,
  });

  final String title;
  final List<Widget> children;

  /// The compact top bar's back button. The expanded layout has the nav.
  final VoidCallback? onBack;
  final Key? backKey;

  @override
  Widget build(BuildContext context) {
    final compact = sizeClassOf(context).isCompact;
    final body = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        compact ? Space.lg : Space.xxl,
        compact ? Space.lg : Space.xxl,
        compact ? Space.lg : Space.xxl,
        Space.xxl,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: SettingsSizes.column),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!compact) SettingsHeading(title, primary: true),
              ...children,
            ],
          ),
        ),
      ),
    );
    if (!compact) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CompactBar(title: title, onBack: onBack, backKey: backKey),
        Expanded(child: body),
      ],
    );
  }
}

class _CompactBar extends StatelessWidget {
  const _CompactBar({required this.title, this.onBack, this.backKey});

  final String title;
  final VoidCallback? onBack;
  final Key? backKey;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.seam)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: SettingsSizes.compactBar),
        child: Row(
          children: [
            const Gap(Space.sm),
            if (onBack != null)
              IconBtn(
                Ico.chevronLeft,
                key: backKey,
                size: ControlSize.xl,
                semanticLabel: 'Back',
                onTap: onBack,
              )
            else
              const Gap(Space.xxxl),
            const Gap(Space.sm),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: ts(
                    theme.typeScale.h2,
                    theme.ink,
                    weight: Weight.semibold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A switch with its state spelled out beside it. A disabled one is dimmed
/// and does not respond.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.id,
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
    this.enabled = true,
  });

  /// Names the switch for tests: the toggle's key is `toggle-<id>`.
  final String id;
  final String label;
  final String? description;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return SettingsRow(
      label: label,
      description: description,
      trailing: Semantics(
        label: label,
        toggled: value,
        enabled: enabled,
        child: Opacity(
          opacity: enabled ? 1 : Alpha.muted,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Toggle(
                key: ValueKey('toggle-$id'),
                value: value,
                onChanged: enabled ? onChanged : null,
              ),
              SizedBox(
                width: SettingsSizes.switchState,
                child: Padding(
                  padding: const EdgeInsets.only(left: Space.sm),
                  child: Text(
                    value ? 'On' : 'Off',
                    style: ts(
                      theme.typeScale.uiSmall,
                      theme.muted,
                      weight: Weight.semibold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A few exclusive options in one row. The chosen one sits on the surface.
class SegmentedChoice<T> extends StatelessWidget {
  const SegmentedChoice({
    super.key,
    required this.options,
    required this.value,
    required this.labelOf,
    required this.onChanged,
    required this.idPrefix,
  });

  final List<T> options;
  final T value;
  final String Function(T option) labelOf;
  final ValueChanged<T> onChanged;

  /// Option keys are `<idPrefix>-<label in lower case>`.
  final String idPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface2,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: theme.seam),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.hair),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in options)
              Semantics(
                button: true,
                selected: option == value,
                inMutuallyExclusiveGroup: true,
                label: labelOf(option),
                excludeSemantics: true,
                child: Hover(
                  key: ValueKey('$idPrefix-${labelOf(option).toLowerCase()}'),
                  onTap: () => onChanged(option),
                  background: option == value ? theme.surface : null,
                  border: option == value
                      ? Border.all(color: theme.thread)
                      : null,
                  borderRadius: BorderRadius.circular(Radii.md),
                  padding: const EdgeInsets.symmetric(horizontal: Space.md),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: ControlSize.sm.height,
                    ),
                    child: Center(
                      child: Text(
                        labelOf(option),
                        style: ts(
                          theme.typeScale.uiSmall,
                          option == value ? theme.ink : theme.muted,
                          weight: option == value ? Weight.bold : Weight.medium,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A radio option drawn as a card, with a title and one line under it. A
/// card that is not [available] is dimmed and cannot be chosen; its
/// description says why.
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({
    super.key,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
    this.available = true,
  });

  final String title;
  final String description;
  final bool selected;
  final bool available;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        enabled: available,
        label: '$title. $description',
        excludeSemantics: true,
        child: Opacity(
          opacity: available ? 1 : Alpha.muted,
          child: Hover(
            onTap: available ? onTap : null,
            background: selected ? theme.surface : theme.surface2,
            border: Border.all(
              color: selected ? theme.threadStrong : theme.seam,
            ),
            borderRadius: BorderRadius.circular(Radii.lg),
            lift: 0,
            padding: const EdgeInsets.all(Space.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RadioMark(selected: selected),
                const Gap(Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: ts(
                          theme.typeScale.ui,
                          theme.ink,
                          weight: Weight.semibold,
                        ),
                      ),
                      const Gap(Space.hair),
                      Text(
                        description,
                        style: ts(theme.typeScale.uiSmall, theme.muted),
                      ),
                    ],
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

class _RadioMark extends StatelessWidget {
  const _RadioMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Container(
      width: SettingsSizes.radioMark,
      height: SettingsSizes.radioMark,
      margin: const EdgeInsets.only(top: Space.hair),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? theme.ink : theme.threadStrong,
          width: Stroke.regular,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: Sizes.dot,
                height: Sizes.dot,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.ink,
                ),
              ),
            )
          : null,
    );
  }
}

enum PillTone { good, attention, bad, plain }

/// A status in a few words, with a dot. The words carry the meaning; the
/// colour only adds to them.
class StatePill extends StatelessWidget {
  const StatePill(this.label, {super.key, this.tone = PillTone.plain});

  final String label;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final (Color fill, Color ink) = switch (tone) {
      PillTone.good => (theme.constructive, theme.constructiveInk),
      PillTone.attention => (theme.attention, theme.attentionInk),
      PillTone.bad => (theme.danger, theme.dangerInk),
      PillTone.plain => (theme.surface2, theme.muted),
    };
    return DecoratedBox(
      decoration: BoxDecoration(color: fill, borderRadius: Radii.pill),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.sm,
          vertical: Space.xxs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: SettingsSizes.pillDot,
              height: SettingsSizes.pillDot,
              decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
            ),
            const Gap(Space.xs),
            Text(
              label,
              style: ts(theme.typeScale.uiSmall, ink, weight: Weight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

/// A bordered group of rows on the surface, for the versions table and the
/// provider cards.
class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.children, this.header});

  /// The first row, on the lighter surface.
  final Widget? header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.seam),
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (header != null)
                ColoredBox(
                  color: theme.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(Space.md),
                    child: header,
                  ),
                ),
              for (var i = 0; i < children.length; i++)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.surface2,
                    border: i == 0 && header == null
                        ? null
                        : Border(top: BorderSide(color: theme.seam)),
                  ),
                  child: children[i],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Glyphs for the Tools and Skills pages.
const LucideGlyph glyphWrench = (
  LucideIcons.wrench300,
  LucideIcons.wrench,
  LucideIcons.wrench500,
);
const LucideGlyph glyphBookOpen = (
  LucideIcons.bookOpen300,
  LucideIcons.bookOpen,
  LucideIcons.bookOpen500,
);
const LucideGlyph glyphPlug = (
  LucideIcons.plug300,
  LucideIcons.plug,
  LucideIcons.plug500,
);
const LucideGlyph glyphMinus = (
  LucideIcons.minus300,
  LucideIcons.minus,
  LucideIcons.minus500,
);
