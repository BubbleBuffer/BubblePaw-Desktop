// The dialogs of Remote access: Pair a device (permissions, code, number to
// compare, done) and Revoke. Each is a modal panel over Settings.

import 'dart:async';

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:qr/qr.dart';

import '../remote/pairing_flow.dart';
import '../remote/remote_access.dart';
import '../remote/remote_controller.dart';
import 'action_widgets.dart';
import 'remote_glyphs.dart';
import 'settings_widgets.dart';

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
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: ts(theme.typeScale.h2, theme.ink, weight: 600),
                    ),
                  ),
                ),
                if (step.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      step,
                      key: const ValueKey('dialog-step'),
                      style: ts(theme.typeScale.uiSmall, theme.muted),
                    ),
                  ),
                IconBtn(
                  Ico.close,
                  key: const ValueKey('dialog-close'),
                  size: 32,
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: body,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
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
      if (i > 0) const SizedBox(width: 8),
      actions[i],
    ],
  ],
);

/// "Pair a device". Resolves when the dialog closes.
Future<void> showPairDialog(
  BuildContext context, {
  required RemoteController remote,
  required String reachLabel,
}) async {
  final flow = PairingFlow(access: remote.access, onAdded: remote.deviceAdded);
  try {
    await showModalPanel<void>(
      context,
      (_) => SizeClassBuilder(
        builder: (_, _) => PairDialog(flow: flow, reachLabel: reachLabel),
      ),
      width: 480,
      height: 640,
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

class PairDialog extends StatelessWidget {
  const PairDialog({super.key, required this.flow, required this.reachLabel});

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
        const SizedBox(height: 12),
        for (final (id, title, text) in _profiles)
          ChoiceCard(
            key: ValueKey('profile-$id'),
            title: title,
            description: text,
            selected: flow.profile == id,
            onTap: () => flow.chooseProfile(id),
          ),
        Text(
          'You can revoke the device later in Share this host.',
          style: ts(theme.typeScale.uiSmall, theme.muted),
        ),
        if (flow.error != null) ...[
          const SizedBox(height: 8),
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
    final compact = SizeClass.of(context).isCompact;
    final code = offer.code.length == 10
        ? '${offer.code.substring(0, 5)}-${offer.code.substring(5)}'
        : offer.code;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Code', style: ts(theme.typeScale.uiSmall, theme.muted)),
        const SizedBox(height: 4),
        Text(
          code,
          key: const ValueKey('pair-code'),
          style: ts(theme.typeScale.h2, theme.ink, weight: 600, mono: true),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            glyphIcon(glyphClock, size: 15, color: theme.muted),
            const SizedBox(width: 6),
            Text(
              flow.expired
                  ? 'Code expired'
                  : 'Expires in ${countdownText(flow.secondsLeft)}',
              key: const ValueKey('pair-countdown'),
              style: ts(theme.typeScale.ui, theme.muted),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Address in the QR code and the code',
          style: ts(theme.typeScale.uiSmall, theme.muted),
        ),
        Text(
          offer.address,
          key: const ValueKey('pair-address'),
          style: ts(theme.typeScale.uiSmall, theme.ink, mono: true),
        ),
      ],
    );
    final qr = QrView(data: offer.qrPayload, size: compact ? 160 : 148);
    return DialogFrame(
      title: 'Pair a device',
      step: 'Step 2 of 3',
      body: [
        if (compact)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [qr, const SizedBox(height: 16), details],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              qr,
              const SizedBox(width: 20),
              Expanded(child: details),
            ],
          ),
        const SizedBox(height: 16),
        Text(
          'On the new device, choose Add a host, then scan the QR code or '
          'enter the code. The code works once.',
          style: ts(theme.typeScale.uiSmall, theme.muted),
        ),
      ],
      footer: dialogFooter(
        leading: flow.expired
            ? null
            : Row(
                children: [
                  glyphIcon(glyphLoader, size: 15, color: theme.muted),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Waiting for the new device',
                      style: ts(theme.typeScale.uiSmall, theme.muted),
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
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Semantics(
              label: 'Number to compare',
              child: Text(
                shown,
                key: const ValueKey('pair-number'),
                style: ts(
                  theme.typeScale.h2,
                  theme.ink,
                  weight: 600,
                  mono: true,
                ).copyWith(fontSize: 32, letterSpacing: 2),
              ),
            ),
          ),
        ),
        Text(
          "If the numbers differ, someone else may be using the code. Choose "
          "They don't match; the code is cancelled.",
          style: ts(theme.typeScale.uiSmall, theme.muted),
        ),
        if (flow.error != null) ...[
          const SizedBox(height: 8),
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
        ActionButton(
          key: const ValueKey('pair-match'),
          label: 'They match',
          kind: ActionKind.primary,
          onTap: flow.busy ? () {} : () => unawaited(flow.approve()),
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
        const SizedBox(height: 12),
        GroupCard(
          children: [
            KeyValueRow('Reaches this host by', reachLabel, mono: false),
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

/// A QR code for [data]: dark modules on a light plate, whatever the theme,
/// so a camera reads it.
class QrView extends StatelessWidget {
  const QrView({super.key, required this.data, this.size = 148});

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
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final dark = Paint()..color = const Color(0xFF111111);
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
