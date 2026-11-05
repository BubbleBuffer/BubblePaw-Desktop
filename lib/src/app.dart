// The app shell: the kit's AgentWorkbench on a backend the HostController
// owns, with settings and failure notices around it.

import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart'
    show ChatSummary, FileDiff, KitCapability;
import 'package:bb_ui/bb_ui.dart'
    show AppColors, Ico, PrimaryButton, SecondaryButton;
import 'package:flutter/foundation.dart' show LicenseEntry;
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';

import 'feedback/feedback_controller.dart';
import 'feedback/feedback_sheet.dart';
import 'guarded_backend.dart';
import 'host_controller.dart';
import 'remote/host_links.dart';
import 'remote/hosts_controller.dart';
import 'remote/project_groups.dart';
import 'remote/remote_chats.dart';
import 'remote/remote_workbench.dart';
import 'pick_folder.dart' as picker;
import 'platform/releases.dart';
import 'preferences.dart';
import 'screens/diff_review.dart';
import 'screens/host_open_notice.dart';
import 'screens/needs_setup_notice.dart';
import 'screens/notice.dart';
import 'screens/phone_home.dart';
import 'screens/saved_notice.dart';
import 'screens/tray_notice.dart';
import 'screens/update_dialog.dart';
import 'screens/workspace_menu.dart';
import 'settings/licences_page.dart';
import 'settings/settings_shell.dart';

class BubblePawApp extends StatefulWidget {
  const BubblePawApp({
    super.key,
    required this.controller,
    required this.feedback,
    this.brightness,
    this.pickFolder = picker.pickFolder,
    this.services = const PlatformServices(),
    this.licenceSource = LicencesPage.defaultSource,
  });

  final HostController controller;

  /// Saved feedback, and what the feedback sheet writes to.
  final FeedbackController feedback;

  /// Asks for a folder (the native picker); tests pass their own.
  final Future<String?> Function() pickFolder;

  /// The network and the operating system, for About.
  final PlatformServices services;

  /// Where the Licences page reads its entries.
  final Stream<LicenseEntry> Function() licenceSource;

  /// Forces light or dark; follows the platform when null.
  final Brightness? brightness;

  @override
  State<BubblePawApp> createState() => _BubblePawAppState();
}

class _BubblePawAppState extends State<BubblePawApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await widget.controller.close();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WidgetsApp(
    title: 'BubblePaw',
    color: AppColors.light.desk,
    debugShowCheckedModeBanner: false,
    pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, secondary) => builder(context),
    ),
    // The theme sits above the navigator, so overlays (selection handles,
    // menus) read it too.
    builder: (context, child) => ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => BbThemeScope(
        brightness:
            widget.brightness ??
            switch (widget.controller.prefs.theme) {
              ThemeSetting.light => Brightness.light,
              ThemeSetting.dark => Brightness.dark,
              ThemeSetting.system => MediaQuery.platformBrightnessOf(context),
            },
        child: child!,
      ),
    ),
    home: AppShell(
      controller: widget.controller,
      feedback: widget.feedback,
      pickFolder: widget.pickFolder,
      services: widget.services,
      licenceSource: widget.licenceSource,
    ),
  );
}

/// Draws the state of [controller]: settings, a notice, or the workbench.
/// Ctrl+Shift+F opens the feedback sheet over any of them.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.controller,
    required this.feedback,
    this.pickFolder = picker.pickFolder,
    this.services = const PlatformServices(),
    this.licenceSource = LicencesPage.defaultSource,
  });

  final HostController controller;
  final FeedbackController feedback;
  final Future<String?> Function() pickFolder;
  final PlatformServices services;
  final Stream<LicenseEntry> Function() licenceSource;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // The root the screenshot is taken from.
  final _root = GlobalKey();

  HostController get controller => widget.controller;
  FeedbackController get feedback => widget.feedback;

  /// Takes the screenshot of the window as it is, then opens the sheet.
  Future<void> _sendFeedback() async {
    if (feedback.sheetOpen) return;
    final shot = await captureWindow(_root)
        .timeout(const Duration(seconds: 3), onTimeout: () => null);
    if (!mounted) return;
    await showFeedbackSheet(context, controller: feedback, shot: shot);
  }

  @override
  void initState() {
    super.initState();
    // Not a focus shortcut: it must work whatever has the focus, and the
    // update dialog and the sheet take the focus for their own Escape.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyF ||
        !HardwareKeyboard.instance.isControlPressed ||
        !HardwareKeyboard.instance.isShiftPressed) {
      return false;
    }
    unawaited(_sendFeedback());
    return true;
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: _root,
    child: ListenableBuilder(
      listenable: Listenable.merge([controller, feedback]),
      builder: (context, _) => Stack(
        children: [
          Positioned.fill(child: _screen(context)),
          if (controller.trayNoticePending)
            Positioned(
              right: 16,
              bottom: 16,
              child: TrayNotice(onDismiss: controller.dismissTrayNotice),
            ),
          if (controller.needsSetupPending)
            Positioned(
              right: 16,
              bottom: controller.trayNoticePending ? 72 : 16,
              child: NeedsSetupNotice(
                onOpenModels: controller.openModelsFromNotice,
                onDismiss: controller.dismissNeedsSetup,
              ),
            ),
          if (feedback.savedId != null)
            Positioned(
              right: 16,
              bottom:
                  (controller.trayNoticePending ? 72 : 16) +
                  (controller.needsSetupPending ? 56 : 0),
              child: SavedNotice(
                id: feedback.savedId!,
                onOpen: () => unawaited(feedback.open(feedback.savedId)),
                onDismiss: feedback.dismissSaved,
              ),
            ),
          if (controller.openError != null)
            Positioned(
              left: 16,
              right: 16,
              bottom:
                  (controller.trayNoticePending ? 72 : 16) +
                  (controller.needsSetupPending ? 56 : 0) +
                  (feedback.savedId != null ? 56 : 0),
              // Bounded on both sides, so a long message wraps on a phone.
              child: Align(
                alignment: Alignment.bottomRight,
                heightFactor: 1,
                child: HostOpenNotice(
                  message: controller.openError!,
                  onDismiss: controller.dismissOpenError,
                ),
              ),
            ),
          if (controller.updates.dialogOpen)
            Positioned.fill(
              child: UpdateDialog(
                updates: controller.updates,
                services: widget.services,
              ),
            ),
        ],
      ),
    ),
  );

  /// The hosts in the switcher; null when this app has no saved hosts side.
  HostMenu? _hostMenu() {
    final hosts = controller.hosts;
    if (hosts == null) return null;
    return HostMenu(
      listenable: Listenable.merge([controller, hosts]),
      choices: () => hostChoices(controller, hosts),
      onPick: (id) {
        if (id == null) {
          unawaited(controller.openLocalHost());
        } else {
          unawaited(controller.openRemoteHost(id));
        }
      },
      onAdd: controller.requestAddHost,
    );
  }

  /// The phone: the open host's chats, or the empty home without one.
  Widget _phone() {
    final backend = controller.backend;
    final hosts = controller.hosts;
    if (backend == null) {
      return ListenableBuilder(
        listenable: hosts ?? controller,
        builder: (context, _) => PhoneHome(
          hostMenu: _hostMenu(),
          onSettings: controller.openSettings,
          hasHosts: hosts != null && hosts.hosts.isNotEmpty,
          opening: controller.opening,
        ),
      );
    }
    return Workbench(
      // A new host is a new workbench.
      key: ObjectKey(backend),
      backend: backend,
      createdChats: controller.createdChats,
      now: controller.now,
      workspaceName: '',
      initials: '',
      onSettings: controller.openSettings,
      hostMenu: _hostMenu(),
      remoteRows: controller.remoteRows,
      remoteRail: controller.remoteRail,
      remoteName: controller.openHost?.label ?? 'Host',
      finishedTurnsOpen: controller.prefs.turnLayout == TurnLayoutSetting.open,
      phone: true,
    );
  }

  Widget _screen(BuildContext context) {
    final pickFolder = widget.pickFolder;
    final services = widget.services;
    final licenceSource = widget.licenceSource;
    if (controller.settingsOpen) {
      return SettingsShell(
        // A fresh page each time it opens.
        key: ValueKey(('settings', controller.config)),
        controller: controller,
        services: services,
        feedback: feedback,
        onSendFeedback: () => unawaited(_sendFeedback()),
        licenceSource: licenceSource,
        onClose: controller.closeSettings,
        phone: !controller.localHost,
      );
    }
    if (!controller.localHost) return _phone();
    return switch (controller.phase) {
      HostPhase.stopped => Notice(
        title: 'The host is not running',
        message:
            'BubblePaw starts without the host while "Start the host when '
            'BubblePaw starts" is off. Chats are unavailable until it runs.',
        actions: [
          PrimaryButton(
            key: const ValueKey('notice-start'),
            label: 'Start the host',
            height: 36,
            icon: Ico.turnInto,
            onTap: () => unawaited(controller.restart()),
          ),
          SecondaryButton(
            key: const ValueKey('notice-settings'),
            label: 'Settings',
            height: 36,
            onTap: () => controller.openSettings(),
          ),
        ],
      ),
      HostPhase.starting => Notice(
        title: controller.usingScripted
            ? 'Starting the scripted backend'
            : 'Starting BubblePaw',
        message: 'Connecting to the host. Chats appear when it answers.',
      ),
      HostPhase.failed => Notice(
        title: controller.failure!.title,
        message: controller.failure!.message,
        actions: [
          PrimaryButton(
            key: const ValueKey('notice-restart'),
            label: 'Restart',
            height: 36,
            icon: Ico.turnInto,
            onTap: () => unawaited(controller.restart()),
          ),
          SecondaryButton(
            key: const ValueKey('notice-settings'),
            label: 'Settings',
            height: 36,
            onTap: () => controller.openSettings(),
          ),
        ],
      ),
      HostPhase.running => Workbench(
        // A new host is a new workbench.
        key: ObjectKey(controller.backend),
        backend: controller.backend!,
        createdChats: controller.createdChats,
        now: controller.now,
        workspaceName: controller.workspaceLabel,
        initials: controller.workspaceInitials,
        onSettings: controller.openSettings,
        workspace: controller.config?.workspaceDirectory ?? '',
        workspaces: controller.recentWorkspaces,
        onSwitchWorkspace: (path) =>
            unawaited(controller.switchWorkspace(path)),
        pickFolder: pickFolder,
        hostMenu: _hostMenu(),
        remoteRows: controller.remoteRows,
        remoteRail: controller.remoteRail,
        remoteName: controller.openHost?.label ?? 'Host',
        finishedTurnsOpen:
            controller.prefs.turnLayout == TurnLayoutSetting.open,
      ),
    };
  }
}

/// The kit's workbench plus the diff overlay and rewind navigation.
class Workbench extends StatefulWidget {
  const Workbench({
    super.key,
    required this.backend,
    required this.workspaceName,
    required this.initials,
    required this.onSettings,
    this.workspace = '',
    this.workspaces = const [],
    this.hostMenu,
    this.onSwitchWorkspace,
    this.pickFolder,
    this.createdChats,
    this.now,
    this.remoteRows,
    this.remoteRail,
    this.remoteName = 'Host',
    this.phone = false,
    this.finishedTurnsOpen = false,
  });

  /// Whether the steps of a finished turn start open (Settings, General, Turn
  /// layout).
  final bool finishedTurnsOpen;

  /// A phone: the chat list is home, a chat opens over it, and the host menu
  /// is a sheet from the bottom.
  final bool phone;

  final GuardedBackend backend;
  final Stream<ChatSummary>? createdChats;
  final DateTime? now;
  final String workspaceName;
  final String initials;
  final VoidCallback onSettings;

  /// The open workspace's path and the recent ones the rail menu lists.
  final String workspace;
  final List<String> workspaces;

  /// Switches to a workspace; the host restarts with it.
  final ValueChanged<String>? onSwitchWorkspace;

  /// Asks for a folder for "Open folder…".
  final Future<String?> Function()? pickFolder;

  /// The hosts group of the rail menu; null for none.
  final HostMenu? hostMenu;

  /// Set for an open saved host: its chat rows, which project groups are
  /// open and its name. The rail then groups the chats by project.
  final RemoteChatRows? remoteRows;
  final ProjectRailState? remoteRail;
  final String remoteName;

  @override
  State<Workbench> createState() => _WorkbenchState();
}

class _WorkbenchState extends State<Workbench> {
  StreamSubscription<ChatSummary>? _created;
  String? _openChatId;
  FileDiff? _review;

  // The workspace holds the Context pane. Without the capability the pane
  // has nothing to show, so the workbench gets no workspace at all. The
  // phone has no room beside the chat.
  late final WorkspaceController? _workspace =
      !widget.phone && widget.backend.capabilities.has(KitCapability.context)
      ? (WorkspaceController()..addPane(WorkspaceKind.context.id))
      : null;

  @override
  void initState() {
    super.initState();
    // A rewind makes a new chat; open it. The key also refreshes the rail.
    _created = widget.createdChats?.listen((chat) {
      if (mounted) setState(() => _openChatId = chat.id);
    });
  }

  @override
  void dispose() {
    unawaited(_created?.cancel());
    _workspace?.dispose();
    super.dispose();
  }

  void _openWorkspaceMenu() {
    if (widget.phone) {
      final hosts = widget.hostMenu;
      if (hosts != null) unawaited(showHostSheet(context, hosts: hosts));
      return;
    }
    final switchTo = widget.onSwitchWorkspace;
    if (switchTo == null) return;
    unawaited(
      showWorkspaceMenu(
        context,
        current: widget.workspace,
        workspaces: widget.workspaces,
        hosts: widget.hostMenu,
        onPick: switchTo,
        onOpenFolder: () async {
          final path = await widget.pickFolder?.call();
          if (path != null && path.trim().isNotEmpty) switchTo(path);
        },
      ),
    );
  }

  void _showDiff(FileDiff diff) => setState(() => _review = diff);

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: widget.remoteRows != null && widget.remoteRail != null
            ? RemoteWorkbench(
                backend: widget.backend,
                rows: widget.remoteRows!,
                state: widget.remoteRail!,
                hostName: widget.remoteName,
                startOnList: widget.phone,
                initialChatId: _openChatId,
                now: widget.now,
                onSettings: widget.onSettings,
                onSwitchHost: _openWorkspaceMenu,
                workspaceController: _workspace,
                transcriptActions: TranscriptActions(
                  now: widget.now,
                  onReviewDiff: (edit) => _showDiff(edit.diff),
                  finishedActivityOpen: widget.finishedTurnsOpen,
                ),
                onReviewApproval: (approval) {
                  final diff = approval.diff;
                  if (diff != null) _showDiff(diff);
                },
              )
            : AgentWorkbench(
                key: ValueKey(_openChatId),
                backend: widget.backend,
                initialChatId: _openChatId,
                workspaceName: widget.workspaceName,
                initials: widget.initials,
                workspaceController: _workspace,
                workspacePaneBuilder: _workspace == null
                    ? null
                    : (context, tab) => const SizedBox.shrink(),
                now: widget.now,
                onSettings: widget.onSettings,
                onSwitchWorkspace: _openWorkspaceMenu,
                onReviewApproval: (approval) {
                  final diff = approval.diff;
                  if (diff != null) _showDiff(diff);
                },
                transcriptActions: TranscriptActions(
                  now: widget.now,
                  onReviewDiff: (edit) => _showDiff(edit.diff),
                  finishedActivityOpen: widget.finishedTurnsOpen,
                ),
              ),
      ),
      if (_review != null)
        Positioned.fill(
          child: DiffReview(
            diff: _review!,
            onClose: () => setState(() => _review = null),
          ),
        ),
    ],
  );
}

/// The rows of the host switcher: this computer, then each saved host with
/// whether it answers.
List<HostChoice> hostChoices(HostController controller, HostsController hosts) {
  final open = controller.openHostId;
  return [
    if (controller.localHost)
      HostChoice(
        id: null,
        name: 'This computer',
        state: 'Running',
        dot: true,
        selected: open == null,
      ),
    for (final h in hosts.hosts)
      HostChoice(
        id: h.id,
        name: h.label,
        state: switch (hosts.presenceOf(h.id)) {
          HostPresenceKind.online => 'Online · ${_via(h.via)}',
          HostPresenceKind.offline => 'Offline',
          HostPresenceKind.unknown => 'Not checked',
          null => 'Checking',
        },
        dot: hosts.presenceOf(h.id) == HostPresenceKind.online,
        selected: open == h.id,
      ),
  ];
}

String _via(HostVia via) =>
    via == HostVia.relay ? 'Relay' : 'Cloudflare Tunnel';
