// The Send feedback sheet: what happened, the screenshot taken before it
// opened, the diagnostics as they will be saved, and, when a chat is open,
// an option to attach its last 20 messages. Save writes the report on this
// computer; nothing is sent.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../app_tokens.dart';
import '../settings/settings_widgets.dart' show glyphIcon;
import 'feedback_controller.dart';
import 'feedback_widgets.dart';
import 'glyphs.dart';
import 'redact.dart';

/// The window as a PNG, taken before the sheet opens.
class WindowShot {
  const WindowShot(this.png, this.size);

  final Uint8List png;

  /// The window's size in logical pixels.
  final Size size;
}

/// Captures the [RepaintBoundary] behind [key]; null when it cannot (nothing
/// drawn yet, or the engine did not answer in time).
Future<WindowShot?> captureWindow(GlobalKey key) async {
  try {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || boundary.debugNeedsPaint) return null;
    final ratio = ui.PlatformDispatcher.instance.views.isEmpty
        ? 1.0
        : ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    final image = await boundary.toImage(pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return null;
    return WindowShot(data.buffer.asUint8List(), boundary.size);
  } on Object {
    return null;
  }
}

/// Opens the sheet over [context]. [shot] is the window taken beforehand.
/// Completes when the sheet closes; the controller then holds the saved id
/// when a report was saved.
Future<void> showFeedbackSheet(
  BuildContext context, {
  required FeedbackController controller,
  WindowShot? shot,
}) async {
  if (controller.sheetOpen) return;
  controller.sheetOpen = true;
  controller.log.desktop('feedback sheet opened');
  try {
    await showModalPanel<void>(
      context,
      (_) => FeedbackSheet(controller: controller, shot: shot),
      width: Panels.feedback.width,
      height: Panels.feedback.height,
    );
  } finally {
    controller.sheetOpen = false;
  }
}

class FeedbackSheet extends StatefulWidget {
  const FeedbackSheet({super.key, required this.controller, this.shot});

  final FeedbackController controller;
  final WindowShot? shot;

  @override
  State<FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<FeedbackSheet> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  late final String _diagnostics = widget.controller.diagnostics();
  late final String? _chatId = widget.controller.host.currentChatId;

  bool _shot = true;
  bool _diagOpen = false;
  bool _attachChat = false;
  bool _chatOpen = false;
  bool _chatLoading = false;
  String? _chatError;
  FeedbackChat? _chat;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _canSave => _text.text.trim().isNotEmpty && !_saving;

  Future<void> _toggleChat() async {
    if (_attachChat) {
      setState(() {
        _attachChat = false;
        _chatOpen = false;
      });
      return;
    }
    setState(() {
      _attachChat = true;
      _chatLoading = true;
      _chatError = null;
    });
    try {
      final chat = await widget.controller.openChat();
      if (!mounted) return;
      setState(() {
        _chat = chat;
        _chatLoading = false;
        if (chat == null) {
          _attachChat = false;
          _chatError = 'This chat could not be read, so it is not attached.';
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _attachChat = false;
        _chatLoading = false;
        _chatError =
            'The host did not return this chat, so it is not attached. '
            'Try again, or save without it.';
      });
    }
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final shot = widget.shot;
    try {
      await widget.controller.save(
        text: _text.text,
        diagnostics: _diagnostics,
        screenshot: _shot ? shot?.png : null,
        screenshotNote: shot == null
            ? null
            : 'this window, ${shot.size.width.round()}x${shot.size.height.round()}, '
                  'taken before the sheet opened',
        chat: _attachChat ? _chat : null,
      );
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            'The report was not saved: the folder ${widget.controller.location} '
            'could not be written. Check that it exists and has room, then save again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final controller = widget.controller;
    final shot = widget.shot;
    final chat = _attachChat ? _chat : null;
    final chatText = chat == null ? '' : controller.chatMarkdown(chat);
    final diagLines = _diagnostics.split('\n').length;
    final diagCount = redactedCount(_diagnostics);
    final chatCount = redactedCount(chatText);
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      namesRoute: true,
      label: 'Send feedback',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.xl,
              Space.lg,
              Space.xl,
              Space.md,
            ),
            child: Row(
              children: [
                glyphIcon(
                  glyphMessageSquareText,
                  size: IconSize.xl,
                  color: theme.ink,
                ),
                const Gap(Space.md),
                Semantics(
                  header: true,
                  child: Text(
                    'Send feedback',
                    style: ts(
                      theme.typeScale.h2,
                      theme.ink,
                      weight: Weight.semibold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: theme.seam)),
            ),
            child: const SizedBox(width: double.infinity),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                Space.xl,
                Space.lg,
                Space.xl,
                Space.xxs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'What happened?',
                    style: ts(
                      theme.typeScale.ui,
                      theme.ink,
                      weight: Weight.semibold,
                    ),
                  ),
                  const Gap(Space.hair),
                  Text(
                    'Include what you expected instead.',
                    style: ts(theme.typeScale.uiSmall, theme.muted),
                  ),
                  const Gap(Space.sm),
                  FieldFrame(
                    padding: const EdgeInsets.all(Space.md),
                    child: Semantics(
                      label: 'What happened?',
                      textField: true,
                      multiline: true,
                      child: EditableText(
                        key: const ValueKey('feedback-text'),
                        controller: _text,
                        focusNode: _focus,
                        autofocus: true,
                        style: ts(theme.typeScale.body, theme.ink),
                        cursorColor: theme.ink,
                        backgroundCursorColor: theme.faint,
                        selectionColor: theme.accent.withValues(
                          alpha: Alpha.wash,
                        ),
                        selectionControls: noteSelectionControls,
                        keyboardType: TextInputType.multiline,
                        minLines: 5,
                        maxLines: 9,
                      ),
                    ),
                  ),
                  const Gap(Space.lg),
                  _screenshot(theme, shot),
                  const Gap(Space.lg),
                  DisclosureRow(
                    key: const ValueKey('feedback-diag-toggle'),
                    title: 'Diagnostics',
                    summary: '$diagLines lines, $diagCount values redacted',
                    expanded: _diagOpen,
                    onTap: () => setState(() => _diagOpen = !_diagOpen),
                  ),
                  if (_diagOpen) ...[
                    const Gap(Space.sm),
                    FbCodeBlock(
                      key: const ValueKey('feedback-diag-text'),
                      text: _diagnostics,
                      label: 'Diagnostics text that will be saved',
                    ),
                    const Gap(Space.sm),
                    Text(
                      'This is the exact text saved in report.md. Tokens, keys '
                      'and passwords are replaced with [redacted], and your '
                      'home folder shows as ~.',
                      style: ts(theme.typeScale.uiSmall, theme.muted),
                    ),
                  ],
                  if (_chatId != null) ...[
                    const Gap(Space.lg),
                    _ChatCheck(
                      key: const ValueKey('feedback-chat-check'),
                      value: _attachChat,
                      busy: _chatLoading,
                      onTap: _chatLoading ? null : _toggleChat,
                    ),
                    if (_chatError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.xxs),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _chatError!,
                            key: const ValueKey('feedback-chat-error'),
                            style: ts(theme.typeScale.uiSmall, theme.dangerInk),
                          ),
                        ),
                      ),
                    if (chat != null) ...[
                      const Gap(Space.sm),
                      DisclosureRow(
                        key: const ValueKey('feedback-chat-toggle'),
                        title: 'Chat messages',
                        summary:
                            '${chat.lines.length.clamp(0, 20)} messages, '
                            '$chatCount ${chatCount == 1 ? 'value' : 'values'} redacted',
                        expanded: _chatOpen,
                        onTap: () => setState(() => _chatOpen = !_chatOpen),
                      ),
                      if (_chatOpen) ...[
                        const Gap(Space.sm),
                        FbCodeBlock(
                          key: const ValueKey('feedback-chat-text'),
                          text: chatText,
                          label: 'Chat text that will be saved',
                        ),
                        const Gap(Space.sm),
                        Text(
                          'This is the exact text saved in chat.md. Tokens, '
                          'keys and passwords are replaced with [redacted], '
                          'and your home folder shows as ~.',
                          style: ts(theme.typeScale.uiSmall, theme.muted),
                        ),
                      ],
                    ],
                  ],
                  const Gap(Space.lg),
                  Text(
                    'Saved on this computer in the feedback folder'
                    '${chat != null ? ', with chat.md' : ''}. Nothing is sent.',
                    style: ts(theme.typeScale.uiSmall, theme.muted),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.sm),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          key: const ValueKey('feedback-error'),
                          style: ts(theme.typeScale.ui, theme.dangerInk),
                        ),
                      ),
                    ),
                  const Gap(Space.md),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: theme.seam)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.xl,
                Space.md,
                Space.xl,
                Space.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _text.text.trim().isEmpty
                          ? 'Describe what happened to save.'
                          : '',
                      key: const ValueKey('feedback-need'),
                      style: ts(theme.typeScale.uiSmall, theme.muted),
                    ),
                  ),
                  FbButton(
                    key: const ValueKey('feedback-cancel'),
                    label: 'Cancel',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const Gap(Space.sm),
                  FbButton(
                    key: const ValueKey('feedback-save'),
                    label: _saving ? 'Saving…' : 'Save',
                    glyph: glyphSave,
                    kind: FbButtonKind.primary,
                    onTap: _canSave ? _save : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _screenshot(BbTheme theme, WindowShot? shot) {
    Widget row(List<Widget> children, {EdgeInsets? padding}) => DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface2,
        border: Border.all(color: theme.seam),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(Space.sm),
        child: Row(children: children),
      ),
    );
    final label = Text(
      'Screenshot',
      style: ts(theme.typeScale.ui, theme.ink, weight: Weight.semibold),
    );
    if (shot == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label,
          const Gap(Space.xxs),
          row([
            Expanded(
              child: Text(
                'No screenshot was available for this window, so none will be '
                'saved.',
                key: const ValueKey('feedback-shot-none'),
                style: ts(theme.typeScale.ui, theme.muted),
              ),
            ),
          ]),
        ],
      );
    }
    const width = FeedbackSizes.shotWidth;
    final height = shot.size.height <= 0
        ? FeedbackSizes.shotFallbackHeight
        : width * shot.size.height / shot.size.width;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        label,
        const Gap(Space.xxs),
        if (_shot)
          row([
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: theme.thread),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.sm),
                child: ExcludeSemantics(
                  child: Image.memory(
                    shot.png,
                    width: width,
                    height: height,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => SizedBox(
                      width: width,
                      height: height,
                      child: ColoredBox(color: theme.canvas),
                    ),
                  ),
                ),
              ),
            ),
            const Gap(Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'screenshot.png',
                    style: ts(theme.typeScale.ui, theme.ink, mono: true),
                  ),
                  Text(
                    'This window, ${shot.size.width.round()}×'
                    '${shot.size.height.round()}. Taken before this sheet '
                    'opened.',
                    style: ts(theme.typeScale.uiSmall, theme.muted),
                  ),
                ],
              ),
            ),
            FbIconButton(
              key: const ValueKey('feedback-shot-remove'),
              glyph: glyphClose,
              label: 'Remove screenshot',
              onTap: () => setState(() => _shot = false),
            ),
          ])
        else
          row(
            [
              Expanded(
                child: Text(
                  'No screenshot will be saved.',
                  key: const ValueKey('feedback-shot-removed'),
                  style: ts(theme.typeScale.ui, theme.muted),
                ),
              ),
              FbButton(
                key: const ValueKey('feedback-shot-add'),
                label: 'Add screenshot',
                glyph: glyphImage,
                kind: FbButtonKind.quiet,
                onTap: () => setState(() => _shot = true),
              ),
            ],
            padding: const EdgeInsets.fromLTRB(
              Space.md,
              Space.sm,
              Space.sm,
              Space.sm,
            ),
          ),
      ],
    );
  }
}

/// The "Attach the last 20 messages of this chat" checkbox row.
class _ChatCheck extends StatelessWidget {
  const _ChatCheck({
    super.key,
    required this.value,
    required this.busy,
    required this.onTap,
  });

  final bool value;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      container: true,
      checked: value,
      enabled: onTap != null,
      label: 'Attach the last 20 messages of this chat',
      hint: 'Saved as chat.md beside report.md. Tool calls show as one line each.',
      onTap: onTap,
      excludeSemantics: true,
      child: Hover(
        onTap: onTap,
        lift: 0,
        borderRadius: BorderRadius.circular(Radii.md),
        padding: const EdgeInsets.symmetric(
          vertical: Space.xs,
          horizontal: Space.hair,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: Space.hair),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: value ? theme.constructiveInk : theme.canvas,
                  border: Border.all(
                    color: value ? theme.constructiveInk : theme.threadStrong,
                  ),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: SizedBox(
                  width: FeedbackSizes.checkBox,
                  height: FeedbackSizes.checkBox,
                  child: value
                      ? Center(
                          child: glyphIcon(
                            glyphCheck,
                            size: IconSize.xs,
                            color: theme.canvas,
                          ),
                        )
                      : null,
                ),
              ),
            ),
            const Gap(Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    busy
                        ? 'Reading the last 20 messages…'
                        : 'Attach the last 20 messages of this chat',
                    style: ts(
                      theme.typeScale.ui,
                      theme.ink,
                      weight: Weight.semibold,
                    ),
                  ),
                  Text(
                    'Saved as chat.md beside report.md. Tool calls show as one '
                    'line each.',
                    style: ts(theme.typeScale.uiSmall, theme.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
