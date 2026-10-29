// The tray menu as data. Building it is pure, so it is tested without a tray.

import '../host_controller.dart';

/// One row of the tray menu.
class TrayItem {
  const TrayItem(this.key, this.label, {this.enabled = true});

  /// A thin line between groups.
  const TrayItem.separator() : key = separatorKey, label = '', enabled = false;

  /// What the adapter reports back when the row is chosen.
  final String key;
  final String label;
  final bool enabled;

  bool get isSeparator => key == separatorKey;

  static const separatorKey = '-';
  static const open = 'open';
  static const status = 'status';
  static const waiting = 'waiting';
  static const restart = 'restart';
  static const quit = 'quit';

  @override
  bool operator ==(Object other) =>
      other is TrayItem &&
      other.key == key &&
      other.label == label &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(key, label, enabled);

  @override
  String toString() => isSeparator ? '---' : '$key: $label';
}

/// The menu for a host in [phase] with [waitingChats] chats that need the
/// person: Open BubblePaw, the host's state, the waiting chats when there are
/// any, Restart host, Quit BubblePaw.
List<TrayItem> trayMenu({required HostPhase phase, int waitingChats = 0}) => [
  const TrayItem(TrayItem.open, 'Open BubblePaw'),
  const TrayItem.separator(),
  TrayItem(TrayItem.status, hostStatusLine(phase), enabled: false),
  if (waitingChats > 0)
    TrayItem(
      TrayItem.waiting,
      waitingChats == 1
          ? '1 chat waiting for you'
          : '$waitingChats chats waiting for you',
    ),
  const TrayItem.separator(),
  TrayItem(
    TrayItem.restart,
    'Restart host',
    enabled: phase != HostPhase.setup,
  ),
  const TrayItem.separator(),
  const TrayItem(TrayItem.quit, 'Quit BubblePaw'),
];

/// The host's state in a few words.
String hostStatusLine(HostPhase phase) => switch (phase) {
  HostPhase.running => 'Host running',
  HostPhase.starting => 'Host starting',
  HostPhase.setup => 'Host not set up',
  HostPhase.stopped => 'Host not started',
  HostPhase.failed => 'Host stopped',
};
