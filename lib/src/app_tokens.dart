// BubblePaw Desktop's own layout values: dialog sizes, columns and the few
// marks particular to its screens. Everything shared comes from bb_tokens
// (Space, ControlSize, IconSize, Stroke, Alpha, Radii, Widths, Sizes); only
// what is particular to this app is named here. The bb_lints rules accept
// raw values in a `*_tokens.dart` library and nowhere else.

import 'dart:ui' show Color;

/// The largest size of each modal panel (`showModalPanel`'s width and
/// height; the panel shrinks to the window).
abstract final class Panels {
  static const feedback = (width: 560.0, height: 760.0);
  static const mcpServer = (width: 520.0, height: 760.0);
  static const addHost = (width: 480.0, height: 560.0);
  static const pairDevice = (width: 480.0, height: 640.0);
  static const providerKey = (width: 460.0, height: 560.0);
  static const keyExport = (width: 460.0, height: 560.0);
  static const keyImport = (width: 460.0, height: 640.0);
  static const keyRegenerate = (width: 460.0, height: 520.0);
}

/// Sizes particular to the settings pages.
abstract final class SettingsSizes {
  /// The widest a settings page's column runs.
  static const double column = 640;

  /// The top bar of a settings page at compact width, at least this tall.
  static const double compactBar = 56;

  /// The "On" / "Off" label beside a switch.
  static const double switchState = 28;

  /// The label column of a fact row (versions, tunnel details), and the
  /// About page's versions table.
  static const double factLabel = 112, versionLabel = 120;

  /// A drawn checkbox and radio mark beside a label.
  static const double checkBox = 16, radioMark = 16;

  /// The dot in a state pill.
  static const double pillDot = 6;

  /// The bar beside the selected section in the settings nav.
  static const double navMark = 18;

  /// A determinate progress bar's thickness.
  static const double progressBar = 6;

  /// The pairing QR code: in a dialog, and larger at compact width where it
  /// sits alone.
  static const double qr = 148, qrCompact = 160;
}

/// Sizes particular to the feedback sheet.
abstract final class FeedbackSizes {
  /// A checkbox of the sheet's include list.
  static const double checkBox = 18;

  /// The screenshot's thumbnail width, and its height when the shot has no
  /// size.
  static const double shotWidth = 192, shotFallbackHeight = 120;

  /// A code block's height when the caller sets none.
  static const double codeBlock = 220;
}

/// The remote rail: the host row, the New chat row and its project picker.
abstract final class RailSizes {
  /// The host row (an online line over the host's name), at least this tall.
  static const double hostRow = 40;

  /// The New chat button's least width (icon, gap, label and padding), and
  /// the project chip beside it: no narrower than [chipMin], no wider than
  /// [chipMax].
  static const double newChatMin = 112, chipMin = 40, chipMax = 112;

  /// Where the project picker's menu hangs: under the New chat row, which
  /// sits under the host row (12 + 40 + 6 padding) and is 36 high with 4 of
  /// air below.
  static const double pickerTop = 12 + hostRow + 6 + 36 + 4;

  /// The picker menu's width and the most it shows before it scrolls.
  static const double pickerWidth = 200, pickerMaxHeight = 320;

  /// The online dot in the host row.
  static const double onlineDot = 7;
}

/// The host and workspace menu.
abstract final class MenuSizes {
  static const workspaceMenu = (min: 224.0, max: 320.0);
}

/// The workbench's split with the Context workspace, as the agent kit's own
/// workbench splits it: a share of the width between a minimum and a maximum.
abstract final class WorkbenchSizes {
  /// The workspace beside a medium chat.
  static const workspaceMedium = (min: 240.0, max: 420.0, share: .4);

  /// The chat beside an expanded workspace.
  static const chatExpanded = (min: 444.0, max: 584.0, share: .44);
}

/// A QR code is dark modules on a light plate whatever the theme, so a
/// camera reads it.
abstract final class QrColors {
  static const plate = Color(0xFFFFFFFF), module = Color(0xFF111111);
}
