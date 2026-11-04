// The tray menu as data. Building it is pure, so it is tested without a tray.

import '../host_controller.dart';
import '../remote/remote_access.dart' show ShareMode;

/// One row of the tray menu.
class TrayItem {
  const TrayItem(
    this.key,
    this.label, {
    this.enabled = true,
    this.checked = false,
  });

  /// A thin line between groups.
  const TrayItem.separator()
    : key = separatorKey,
      label = '',
      enabled = false,
      checked = false;

  /// What the adapter reports back when the row is chosen.
  final String key;
  final String label;
  final bool enabled;

  /// A check item: whether the tick shows.
  final bool checked;

  bool get isSeparator => key == separatorKey;

  static const separatorKey = '-';
  static const open = 'open';
  static const status = 'status';
  static const share = 'share';
  static const waiting = 'waiting';
  static const restart = 'restart';
  static const quit = 'quit';

  @override
  bool operator ==(Object other) =>
      other is TrayItem &&
      other.key == key &&
      other.label == label &&
      other.enabled == enabled &&
      other.checked == checked;

  @override
  int get hashCode => Object.hash(key, label, enabled, checked);

  @override
  String toString() => isSeparator ? '---' : '$key: $label';
}

/// The menu for a host in [phase] with [waitingChats] chats that need the
/// person: Open BubblePaw, the host's state, "Share this host" while the host
/// runs and can be shared ([canShare]; ticked when [shared], reached by
/// [mode]), the waiting chats when there are any, Restart host, Quit
/// BubblePaw.
List<TrayItem> trayMenu({
  required HostPhase phase,
  int waitingChats = 0,
  bool canShare = false,
  bool shared = false,
  ShareMode mode = ShareMode.relay,
}) => [
  const TrayItem(TrayItem.open, 'Open BubblePaw'),
  const TrayItem.separator(),
  TrayItem(
    TrayItem.status,
    hostStatusLine(phase, shared: shared, mode: mode),
    enabled: false,
  ),
  if (canShare && phase == HostPhase.running)
    TrayItem(TrayItem.share, 'Share this host', checked: shared),
  if (waitingChats > 0)
    TrayItem(
      TrayItem.waiting,
      waitingChats == 1
          ? '1 chat waiting for you'
          : '$waitingChats chats waiting for you',
    ),
  const TrayItem.separator(),
  const TrayItem(TrayItem.restart, 'Restart host'),
  const TrayItem.separator(),
  const TrayItem(TrayItem.quit, 'Quit BubblePaw'),
];

/// The host's state in a few words, with how it is shared when it is.
String hostStatusLine(
  HostPhase phase, {
  bool shared = false,
  ShareMode mode = ShareMode.relay,
}) {
  if (phase == HostPhase.running && shared) {
    final via = mode == ShareMode.relay ? 'relay' : 'Cloudflare Tunnel';
    return 'Host running · shared via $via';
  }
  return switch (phase) {
    HostPhase.running => 'Host running',
    HostPhase.starting => 'Host starting',
    HostPhase.stopped || HostPhase.failed => 'Host stopped',
  };
}
