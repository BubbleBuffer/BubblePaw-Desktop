// The dialogs of Remote access: Pair a device (permissions, code, number to
// compare and device name, done) and Revoke. Each is a modal panel over Settings.

import 'dart:async';

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:qr/qr.dart';

import '../app_tokens.dart';
import '../feedback/glyphs.dart' show glyphCheck;
import '../remote/pairing_flow.dart';
import '../remote/remote_access.dart';
import '../remote/remote_controller.dart';
import 'action_widgets.dart';
import 'remote_glyphs.dart';
import 'settings_widgets.dart';
import 'text_box.dart';

/// The frame every Remote access dialog shares: a title with an optional
/// step line, the body and a footer row of actions.
class DialogFrame extends StatelessWidget {
  const DialogFrame({
    super.key,
    required this.title,
    required this.body,
    required this.footer,
    this.step = '',
  });

  final String title;
  final String step;
  final List<Widget> body;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      namesRoute: true,
      label: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.xl,
              Space.md,
              Space.md,
              Space.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: ts(
                        theme.typeScale.h2,
                        theme.ink,
                        weight: Weight.strong,
                      ),
                    ),
                  ),
                ),
                if (step.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: Space.sm),
                    child: Text(
                      step,
                      key: const ValueKey('dialog-step'),
                      style: ts(
                        theme.typeScale.uiSmall,
                        theme.muted,
                        weight: Weight.regular,
                      ),
                    ),
                  ),
                IconBtn(
                  Ico.close,
                  key: const ValueKey('dialog-close'),
                  size: ControlSize.md,
                  semanticLabel: 'Close',
                  onTap: () => Navigator.of(context).maybePop(),
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
                Space.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: body,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.xl,
              Space.sm,
              Space.xl,
              Space.lg,
            ),
            child: footer,
          ),
        ],
      ),
    );
  }
}

/// A footer: [leading] on the left, the actions on the right.
Widget dialogFooter(List<Widget> actions, {Widget? leading}) => Row(
  children: [
    if (leading != null) Expanded(child: leading) else const Spacer(),
    for (var i = 0; i < actions.length; i++) ...[
      if (i > 0) const Gap(Space.sm),
      actions[i],
    ],
  ],
);

/// "Pair a device". Resolves when the dialog closes.
Future<void> showPairDialog(
  BuildContext context, {
  required RemoteController remote,
  required String reachLabel,
  Future<void> Function(String text)? onCopy,
}) async {
  final flow = PairingFlow(access: remote.access, onAdded: remote.deviceAdded);
  try {
    await showModalPanel<void>(
      context,
      (_) => SizeClassBuilder(
        builder: (_, _) =>
            PairDialog(flow: flow, reachLabel: reachLabel, onCopy: onCopy),
      ),
      width: Panels.pairDevice.width,
      height: Panels.pairDevice.height,
      shrink: true,
    );
  } finally {
    await flow.cancel();
    flow.dispose();
  }
}

const _profiles = <(String, String, String)>[
  (
    'read',
    'Read',
    'View chats and results. Cannot send messages or approve anything.',
  ),
  (
    'edit',
    'Edit',
    'Send messages and approve file edits. Cannot run commands.',
  ),
  (
    'full',
    'Full',
    "Everything on this computer's host, including running commands and "
        'changing settings.',
  ),
];

String profileName(String profile) => switch (profile) {
  'read' => 'Read',
  'edit' => 'Edit',
  'full' => 'Full',
  final other => other,
};

/// A checkbox with a label and one line under it.
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    super.key,
    required this.value,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final bool value;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Semantics(
      container: true,
      checked: value,
      label: label,
      hint: detail,
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
              child: Container(
                width: SettingsSizes.checkBox,
                height: SettingsSizes.checkBox,
                decoration: BoxDecoration(
                  color: value ? theme.accent : theme.surface,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(
                    color: value ? theme.accent : theme.threadStrong,
                  ),
                ),
                child: value
                    ? Center(
                        child: glyphIcon(
                          glyphCheck,
                          size: IconSize.xs,
                          color: theme.onAccent,
                        ),
                      )
                    : null,
              ),
            ),
            const Gap(Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: ts(theme.typeScale.ui, theme.ink)),
                  Text(
                    detail,
                    style: ts(
                      theme.typeScale.uiSmall,
                      theme.muted,
                      weight: Weight.regular,
                    ),
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

class PairDialog extends StatelessWidget {
  const PairDialog({
    super.key,
    required this.flow,
    required this.reachLabel,
    this.onCopy,
  });

  /// Copies text to the clipboard; null hides "Copy pairing link".
  final Future<void> Function(String text)? onCopy;

  final PairingFlow flow;

  /// "Relay" or "Cloudflare Tunnel", for the last step.
  final String reachLabel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: flow,
    builder: (context, _) => switch (flow.step) {
      PairingStep.profile => _profileStep(context),
      PairingStep.code => _codeStep(context),
      PairingStep.compare => _compareStep(context),
      PairingStep.added => _addedStep(context),
    },
  );

  Widget _profileStep(BuildContext context) {
    final theme = context.bb;
    return DialogFrame(
      title: 'Choose permissions',
      step: 'Step 1 of 3',
      body: [
        Text(
          'What the new device may do on this computer.',
          style: ts(theme.typeScale.ui, theme.ink),
        ),
        const Gap(Space.md),
        for (final (id, title, text) in _profiles)
          ChoiceCard(
            key: ValueKey('profile-$id'),
            title: title,
            description: text,
            selected: flow.profile == id,
            onTap: () => flow.chooseProfile(id),
          ),
        const Gap(Space.xxs),
        _CheckRow(
          key: const ValueKey('pair-egress'),
          value: flow.egress,
          label:
              'Allow this device to send model traffic through this computer',
          detail:
              "The device's model requests pass through this computer. "
              'Prompts and keys stay on the device.',
          onTap: () => flow.chooseEgress(!flow.egress),
        ),
        const Gap(Space.md),
        Text(
          'You can revoke the device later in Share this host.',
          style: ts(
            theme.typeScale.uiSmall,
            theme.muted,
            weight: Weight.regular,
          ),
        ),
        if (flow.error != null) ...[
          const Gap(Space.sm),
          Text(
            flow.error!,
            key: const ValueKey('pair-error'),
            style: ts(theme.typeScale.ui, theme.dangerInk),
          ),
        ],
      ],
      footer: dialogFooter([
        ActionButton(
          key: const ValueKey('pair-cancel'),
          label: 'Cancel',
          onTap: () => Navigator.of(context).maybePop(),
        ),
        ActionButton(
          key: const ValueKey('pair-continue'),
          label: 'Make a code',
          kind: ActionKind.primary,
          onTap: flow.busy ? () {} : () => unawaited(flow.createCode()),
        ),
      ]),
    );
  }

  Widget _codeStep(BuildContext context) {
    final theme = context.bb;
    final offer = flow.offer!;
    final compact = sizeClassOf(context).isCompact;
    final code = offer.code.length == 10
        ? '${offer.code.substring(0, 5)}-${offer.code.substring(5)}'
        : offer.code;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Code',
          style: ts(
            theme.typeScale.uiSmall,
            theme.muted,
            weight: Weight.regular,
          ),
        ),
        const Gap(Space.xxs),
        Text(
          code,
          key: const ValueKey('pair-code'),
          style: ts(
            theme.typeScale.h2,
            theme.ink,
            weight: Weight.strong,
            mono: true,
          ),
        ),
        const Gap(Space.sm),
        Row(
          children: [
            glyphIcon(glyphClock, size: IconSize.sm, color: theme.muted),
            const Gap(Space.xs),
            Text(
              flow.expired
                  ? 'Code expired'
                  : 'Expires in ${countdownText(flow.secondsLeft)}',
              key: const ValueKey('pair-countdown'),
              style: ts(
                theme.typeScale.ui,
                theme.muted,
                weight: Weight.regular,
              ),
            ),
          ],
        ),
        const Gap(Space.md),
        Text(
          'Address in the QR code and the code',
          style: ts(
            theme.typeScale.uiSmall,
            theme.muted,
            weight: Weight.regular,
          ),
        ),
        Text(
          offer.address,
          key: const ValueKey('pair-address'),
          style: ts(
            theme.typeScale.uiSmall,
            theme.ink,
            mono: true,
            weight: Weight.regular,
          ),
        ),
      ],
    );
    final qr = QrView(
      data: offer.qrPayload,
      size: compact ? SettingsSizes.qrCompact : SettingsSizes.qr,
    );
    return DialogFrame(
      title: 'Pair a device',
      step: 'Step 2 of 3',
      body: [
        if (compact)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [qr, const Gap(Space.lg), details],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              qr,
              const Gap(Space.xl),
              Expanded(child: details),
            ],
          ),
        const Gap(Space.lg),
        Text(
          'On the new device, choose Add a host, then scan the QR code or '
          'paste the pairing link. The code works once.',
          style: ts(
            theme.typeScale.uiSmall,
            theme.muted,
            weight: Weight.regular,
          ),
        ),
        if (onCopy != null) ...[
          const Gap(Space.md),
          Align(
            alignment: Alignment.centerLeft,
            child: ActionButton(
              key: const ValueKey('pair-copy-link'),
              label: 'Copy pairing link',
              glyph: glyphCopy,
              onTap: () => unawaited(onCopy!(offer.qrPayload)),
            ),
          ),
        ],
      ],
      footer: dialogFooter(
        leading: flow.expired
            ? null
            : Row(
                children: [
                  glyphIcon(glyphLoader, size: IconSize.sm, color: theme.muted),
                  const Gap(Space.xs),
                  Flexible(
                    child: Text(
                      'Waiting for the new device',
                      style: ts(
                        theme.typeScale.uiSmall,
                        theme.muted,
                        weight: Weight.regular,
                      ),
                    ),
                  ),
                ],
              ),
        [
          ActionButton(
            key: const ValueKey('pair-new-code'),
            label: 'New code',
            glyph: glyphRefresh,
            onTap: () => unawaited(flow.newCode()),
          ),
          ActionButton(
            key: const ValueKey('pair-cancel'),
            label: 'Cancel',
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _compareStep(BuildContext context) {
    final theme = context.bb;
    final request = flow.request!;
    final digits = request.comparison;
    final shown = digits.length == 6
        ? '${digits.substring(0, 3)} ${digits.substring(3)}'
        : digits;
    return DialogFrame(
      title: 'Confirm the number',
      step: 'Step 3 of 3',
      body: [
        Text(
          '${request.deviceName} wants to pair. Check that this number is '
          'the same on that device.',
          style: ts(theme.typeScale.ui, theme.ink),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xl),
          child: Center(
            child: Semantics(
              label: 'Number to compare',
              child: Text(
                shown,
                key: const ValueKey('pair-number'),
                style: ts(
                  theme.typeScale.display,
                  theme.ink,
                  weight: Weight.strong,
                  mono: true,
                ),
              ),
            ),
          ),
        ),
        Text(
          "If the numbers differ, someone else may be using the code. Choose "
          "They don't match; the code is cancelled.",
          style: ts(
            theme.typeScale.uiSmall,
            theme.muted,
            weight: Weight.regular,
          ),
        ),
        const Gap(Space.lg),
        _DeviceNameField(flow: flow),
        if (flow.error != null) ...[
          const Gap(Space.sm),
          Text(
            flow.error!,
            key: const ValueKey('pair-error'),
            style: ts(theme.typeScale.ui, theme.dangerInk),
          ),
        ],
      ],
      footer: dialogFooter([
        ActionButton(
          key: const ValueKey('pair-mismatch'),
          label: "They don't match",
          onTap: () async {
            final navigator = Navigator.of(context);
            await flow.decline();
            await navigator.maybePop();
          },
        ),
        Opacity(
          opacity: flow.canApprove ? 1 : Alpha.muted,
          child: ActionButton(
            key: const ValueKey('pair-match'),
            label: 'They match',
            kind: ActionKind.primary,
            onTap: flow.busy || !flow.canApprove
                ? () {}
                : () => unawaited(flow.approve()),
          ),
        ),
      ]),
    );
  }

  Widget _addedStep(BuildContext context) {
    final device = flow.added!;
    final name = device.label.isEmpty ? 'The device' : device.label;
    return DialogFrame(
      title: 'Device added',
      body: [
        NoticeBox(
          key: const ValueKey('pair-added'),
          tone: NoticeTone.good,
          child: Text(
            '$name can now open this computer with the '
            '${profileName(device.profile)} profile.',
          ),
        ),
        const Gap(Space.md),
        GroupCard(
          children: [
            SettingsKeyValueRow(
              'Reaches this host by',
              reachLabel,
              mono: false,
            ),
          ],
        ),
      ],
      footer: dialogFooter([
        ActionButton(
          key: const ValueKey('pair-done'),
          label: 'Done',
          kind: ActionKind.primary,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ]),
    );
  }
}

/// The "Device name" field of the number step: starts as the name the device
/// announced and keeps what the person types in the flow.
class _DeviceNameField extends StatefulWidget {
  const _DeviceNameField({required this.flow});

  final PairingFlow flow;

  @override
  State<_DeviceNameField> createState() => _DeviceNameFieldState();
}

class _DeviceNameFieldState extends State<_DeviceNameField> {
  late final _controller = TextEditingController(text: widget.flow.deviceName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LabeledField(
    label: 'Device name',
    bottom: 0,
    child: TextBox(
      controller: _controller,
      fieldKey: const ValueKey('pair-name'),
      label: 'Device name',
      onChanged: widget.flow.setDeviceName,
    ),
  );
}

/// A QR code for [data]: dark modules on a light plate, whatever the theme,
/// so a camera reads it.
class QrView extends StatelessWidget {
  const QrView({super.key, required this.data, this.size = SettingsSizes.qr});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final code = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    return Semantics(
      label: 'QR code with the pairing details',
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          key: const ValueKey('pair-qr'),
          painter: _QrPainter(QrImage(code)),
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image);

  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    const quiet = 2;
    final count = image.moduleCount + quiet * 2;
    final cell = size.width / count;
    canvas.drawRect(Offset.zero & size, Paint()..color = QrColors.plate);
    final dark = Paint()..color = QrColors.module;
    for (var y = 0; y < image.moduleCount; y++) {
      for (var x = 0; x < image.moduleCount; x++) {
        if (image.isDark(y, x)) {
          canvas.drawRect(
            Rect.fromLTWH(
              (x + quiet) * cell,
              (y + quiet) * cell,
              cell + 0.5,
              cell + 0.5,
            ),
            dark,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image;
}

/// Asks to revoke [device]. True when confirmed.
Future<bool> confirmRevoke(BuildContext context, DeviceEntry device) =>
    showConfirm(
      context,
      title: 'Revoke ${device.label}?',
      message:
          '${device.label} can no longer open this computer. It has to be '
          'paired again with a new code. Its chats on this computer stay.',
      confirmLabel: 'Revoke ${device.label}',
      danger: true,
    );
