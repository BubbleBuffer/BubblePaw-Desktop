// Feedback: the reports saved on this computer, with a way to write a new one.
// Reports are plain files; nothing is uploaded.

import 'dart:async';

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../feedback/feedback_controller.dart';
import '../feedback/feedback_store.dart';
import '../feedback/feedback_widgets.dart';
import '../feedback/glyphs.dart';
import '../feedback/report.dart';
import 'settings_widgets.dart';

class FeedbackPage extends StatelessWidget {
  const FeedbackPage({
    super.key,
    required this.feedback,
    required this.onSend,
    this.onBack,
  });

  final FeedbackController feedback;

  /// Opens the sheet (the screenshot is taken first by the app).
  final VoidCallback onSend;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: feedback,
    builder: (context, _) {
      final theme = context.bb;
      final compact = SizeClass.of(context).isCompact;
      final reports = feedback.reports;
      final send = FbButton(
        key: const ValueKey('feedback-page-send'),
        label: 'Send feedback',
        glyph: glyphMessageSquareText,
        kind: FbButtonKind.primary,
        onTap: onSend,
      );
      final open = FbButton(
        key: const ValueKey('feedback-page-open'),
        label: 'Open folder',
        glyph: glyphFolderOpen,
        onTap: () => unawaited(feedback.open()),
      );
      return SettingsPage(
        title: 'Feedback',
        onBack: onBack,
        backKey: const ValueKey('settings-page-back'),
        children: [
          Text(
            'Reports are plain files, so you or an agent can read them. '
            'Nothing is uploaded.',
            style: ts(theme.typeScale.ui, theme.muted),
          ),
          const SizedBox(height: 4),
          Text(
            feedback.location,
            key: const ValueKey('feedback-path'),
            style: ts(theme.typeScale.uiSmall, theme.muted, mono: true),
          ),
          const SizedBox(height: 12),
          if (compact) ...[
            Row(children: [send, const SizedBox(width: 8), open]),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: SettingsHeading(
                  reports.isEmpty
                      ? 'Saved reports'
                      : 'Saved on this computer, ${reports.length}',
                ),
              ),
              if (!compact) ...[open, const SizedBox(width: 8), send],
            ],
          ),
          const SizedBox(height: 8),
          if (reports.isEmpty)
            _Empty(compact: compact, onSend: onSend)
          else
            GroupCard(
              children: [
                for (final entry in reports)
                  _ReportRow(
                    key: ValueKey('feedback-row-${entry.id}'),
                    entry: entry,
                    feedback: feedback,
                    compact: compact,
                  ),
              ],
            ),
        ],
      );
    },
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.compact, required this.onSend});

  final bool compact;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return DecoratedBox(
      key: const ValueKey('feedback-empty'),
      decoration: BoxDecoration(
        color: theme.surface2,
        border: Border.all(color: theme.seam),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            glyphIcon(glyphMessageSquareText, size: 28, color: theme.faint),
            const SizedBox(height: 8),
            Text(
              'No feedback saved',
              style: ts(theme.typeScale.body, theme.ink, weight: 600),
            ),
            const SizedBox(height: 4),
            Text(
              'Send feedback saves a report on this computer: your text, a '
              'screenshot and diagnostics. Press Ctrl+Shift+F in any window.',
              textAlign: TextAlign.center,
              style: ts(theme.typeScale.ui, theme.muted),
            ),
            const SizedBox(height: 12),
            FbButton(
              key: const ValueKey('feedback-empty-send'),
              label: 'Send feedback',
              glyph: glyphMessageSquareText,
              kind: FbButtonKind.primary,
              onTap: onSend,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({
    super.key,
    required this.entry,
    required this.feedback,
    required this.compact,
  });

  final FeedbackEntry entry;
  final FeedbackController feedback;
  final bool compact;

  Future<void> _delete(BuildContext context) async {
    final names = entry.files;
    final list = names.length == 1
        ? names.first
        : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
    final ok = await showConfirm(
      context,
      title: 'Delete this feedback?',
      message:
          '${reportStamp(entry.id)}: ${entry.firstLine}\n'
          '$list ${names.length == 1 ? 'is' : 'are'} deleted from this '
          'computer. This can’t be undone.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (ok) await feedback.delete(entry.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final copied = feedback.copiedId == entry.id;
    Widget indicator(LucideGlyph glyph, String label) => Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          glyphIcon(glyph, size: 14, color: theme.muted),
          const SizedBox(width: 4),
          Text(label, style: ts(theme.typeScale.uiSmall, theme.muted)),
        ],
      ),
    );
    final meta = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          reportStamp(entry.id),
          style: ts(theme.typeScale.uiSmall, theme.muted, mono: true),
        ),
        if (entry.hasScreenshot) indicator(glyphImage, 'Screenshot'),
        if (entry.hasChat) indicator(glyphMessagesSquare, 'Chat'),
        if (copied)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                'Copied as Markdown',
                style: ts(theme.typeScale.uiSmall, theme.muted),
              ),
            ),
          ),
      ],
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        meta,
        const SizedBox(height: 2),
        Text(
          entry.firstLine,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: ts(theme.typeScale.ui, theme.ink),
        ),
      ],
    );
    final actions = compact
        ? [
            FbButton(
              key: ValueKey('feedback-open-${entry.id}'),
              label: 'Open folder',
              glyph: glyphFolderOpen,
              kind: FbButtonKind.quiet,
              onTap: () => unawaited(feedback.open(entry.id)),
            ),
            FbButton(
              key: ValueKey('feedback-copy-${entry.id}'),
              label: copied ? 'Copied' : 'Copy as Markdown',
              glyph: copied ? glyphCheck : glyphCopy,
              kind: FbButtonKind.quiet,
              onTap: () => unawaited(feedback.copyMarkdown(entry.id)),
            ),
            FbButton(
              key: ValueKey('feedback-delete-${entry.id}'),
              label: 'Delete',
              glyph: glyphTrash,
              kind: FbButtonKind.quiet,
              onTap: () => unawaited(_delete(context)),
            ),
          ]
        : [
            FbIconButton(
              key: ValueKey('feedback-open-${entry.id}'),
              glyph: glyphFolderOpen,
              label: 'Open folder',
              onTap: () => unawaited(feedback.open(entry.id)),
            ),
            FbIconButton(
              key: ValueKey('feedback-copy-${entry.id}'),
              glyph: copied ? glyphCheck : glyphCopy,
              label: copied ? 'Copied' : 'Copy as Markdown',
              onTap: () => unawaited(feedback.copyMarkdown(entry.id)),
            ),
            FbIconButton(
              key: ValueKey('feedback-delete-${entry.id}'),
              glyph: glyphTrash,
              label: 'Delete',
              onTap: () => unawaited(_delete(context)),
            ),
          ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text,
                const SizedBox(height: 4),
                Wrap(children: actions),
              ],
            )
          : Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: 8),
                ...actions,
              ],
            ),
    );
  }
}
