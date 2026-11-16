// The camera view that reads a pairing QR code (phone only). It resolves with
// the text of the first code, or null when the person closes it.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

Future<String?> scanQrCode(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push<String>(
      PageRouteBuilder<String>(
        opaque: true,
        pageBuilder: (_, _, _) => const _QrScanPage(),
      ),
    );

class _QrScanPage extends StatefulWidget {
  const _QrScanPage();

  @override
  State<_QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<_QrScanPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _detected(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final text = code.rawValue;
      if (text != null && text.isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(text);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return ColoredBox(
      color: theme.canvas,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.sm,
                Space.sm,
                Space.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Scan QR code',
                      style: ts(
                        theme.typeScale.h2,
                        theme.ink,
                        weight: Weight.semibold,
                      ),
                    ),
                  ),
                  IconBtn(
                    Ico.close,
                    key: const ValueKey('scan-close'),
                    size: ControlSize.xl,
                    semanticLabel: 'Close',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                0,
                Space.lg,
                Space.md,
              ),
              child: Text(
                'Point the camera at the code shown by the host.',
                style: ts(theme.typeScale.ui, theme.muted),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.sheet),
                  child: MobileScanner(
                    controller: _controller,
                    onDetect: _detected,
                    errorBuilder: (context, error) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(Space.xl),
                        child: Text(
                          'The camera is not available. Paste the pairing '
                          'link instead.',
                          textAlign: TextAlign.center,
                          style: ts(theme.typeScale.ui, theme.muted),
                        ),
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
