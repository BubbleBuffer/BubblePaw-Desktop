// The way "Add a host" reads a pairing link from a QR code. Only the phone
// sets one (main_phone.dart); with none set the dialog offers the paste field
// alone.

import 'package:flutter/widgets.dart';

/// Opens the camera over [context] and resolves with the text of the first QR
/// code read, or null when the person backs out.
typedef LinkScanner = Future<String?> Function(BuildContext context);

/// The scanner "Add a host" offers. Set once at start up (and by tests).
LinkScanner? linkScanner;
