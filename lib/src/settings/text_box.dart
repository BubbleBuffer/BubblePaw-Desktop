// A framed text input and a labelled field, for the Remote access dialogs and
// page. The same look as the MCP form's fields.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

/// A label, an optional hint, the field and its error line.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.hint,
    this.error = '',
    this.bottom = 16,
  });

  final String label;
  final String? hint;
  final String error;
  final Widget child;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: ts(theme.typeScale.uiSmall, theme.ink, weight: 600),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                hint!,
                style: ts(theme.typeScale.uiSmall, theme.muted),
              ),
            ),
          const SizedBox(height: 6),
          child,
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                error,
                style: ts(theme.typeScale.uiSmall, theme.dangerInk),
              ),
            ),
        ],
      ),
    );
  }
}

/// One text input: a framed field that can hide its text and show an error.
class TextBox extends StatefulWidget {
  const TextBox({
    super.key,
    required this.controller,
    required this.label,
    this.fieldKey,
    this.placeholder = '',
    this.mono = false,
    this.obscure = false,
    this.invalid = false,
    this.readOnly = false,
    this.suffix,
    this.onSubmitted,
    this.onChanged,
    this.onBlur,
  });

  final TextEditingController controller;
  final String label;
  final Key? fieldKey;
  final String placeholder;
  final bool mono;
  final bool obscure;
  final bool invalid;
  final bool readOnly;

  /// Fixed text after the input, such as `.example.com`.
  final String? suffix;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  /// The field lost focus.
  final ValueChanged<String>? onBlur;

  @override
  State<TextBox> createState() => _TextBoxState();
}

class _TextBoxState extends State<TextBox> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (!_focus.hasFocus) widget.onBlur?.call(widget.controller.text);
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final style = ts(theme.typeScale.ui, theme.ink, mono: widget.mono);
    final field = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.readOnly ? null : _focus.requestFocus,
      child: FieldFrame(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Semantics(
          label: widget.label,
          textField: true,
          child: Row(
            children: [
              Expanded(
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    ListenableBuilder(
                      listenable: widget.controller,
                      builder: (_, _) => widget.controller.text.isEmpty
                          ? IgnorePointer(
                              child: Text(
                                widget.placeholder,
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: style.copyWith(color: theme.faint),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    EditableText(
                      key: widget.fieldKey,
                      controller: widget.controller,
                      focusNode: _focus,
                      style: style,
                      cursorColor: theme.ink,
                      backgroundCursorColor: theme.faint,
                      selectionColor: theme.accent.withValues(alpha: 0.3),
                      selectionControls: noteSelectionControls,
                      obscureText: widget.obscure,
                      readOnly: widget.readOnly,
                      maxLines: 1,
                      onSubmitted: widget.onSubmitted,
                      onChanged: widget.onChanged,
                    ),
                  ],
                ),
              ),
              if (widget.suffix != null)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    widget.suffix!,
                    style: ts(theme.typeScale.ui, theme.muted, mono: true),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    final framed = widget.invalid
        ? DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.dangerInk),
            ),
            child: field,
          )
        : field;
    return widget.readOnly ? Opacity(opacity: .6, child: framed) : framed;
  }
}
