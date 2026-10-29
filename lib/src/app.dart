// The app shell: the kit's AgentWorkbench on a backend the HostController
// owns, with settings and failure notices around it.

import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart'
    show ChatSummary, FileDiff, KitCapability;
import 'package:bb_ui/bb_ui.dart'
    show AppColors, Ico, PrimaryButton, SecondaryButton;
import 'package:flutter/widgets.dart';

import 'guarded_backend.dart';
import 'host_controller.dart';
import 'pick_folder.dart' as picker;
import 'screens/diff_review.dart';
import 'screens/notice.dart';
import 'screens/settings_screen.dart';
import 'screens/workspace_menu.dart';

class BubblePawApp extends StatefulWidget {
  const BubblePawApp({
    super.key,
    required this.controller,
    this.brightness,
    this.pickFolder = picker.pickFolder,
  });

  final HostController controller;

  /// Asks for a folder (the native picker); tests pass their own.
  final Future<String?> Function() pickFolder;

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
    builder: (context, child) => BbThemeScope(
      brightness: widget.brightness ?? MediaQuery.platformBrightnessOf(context),
      child: child!,
    ),
    home: AppShell(
      controller: widget.controller,
      pickFolder: widget.pickFolder,
    ),
  );
}

/// Draws the state of [controller]: settings, a notice, or the workbench.
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.controller,
    this.pickFolder = picker.pickFolder,
  });

  final HostController controller;
  final Future<String?> Function() pickFolder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (controller.settingsOpen) {
        final first = controller.phase == HostPhase.setup;
        return SettingsScreen(
          // A fresh form each time it opens.
          key: ValueKey(('settings', controller.config)),
          initial: controller.config ?? controller.store.defaults,
          firstRun: first && controller.config == null,
          scripted: controller.usingScripted,
          backend: controller.phase == HostPhase.running
              ? controller.backend
              : null,
          onSave: (config) => unawaited(controller.saveAndStart(config)),
          onCancel: first ? null : controller.closeSettings,
        );
      }
      return switch (controller.phase) {
        HostPhase.setup || HostPhase.starting => Notice(
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
              onTap: controller.openSettings,
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
        ),
      };
    },
  );
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
    this.onSwitchWorkspace,
    this.pickFolder,
    this.createdChats,
    this.now,
  });

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

  @override
  State<Workbench> createState() => _WorkbenchState();
}

class _WorkbenchState extends State<Workbench> {
  StreamSubscription<ChatSummary>? _created;
  String? _openChatId;
  FileDiff? _review;

  // The workspace holds the Context pane. Without the capability the pane
  // has nothing to show, so the workbench gets no workspace at all.
  late final WorkspaceController? _workspace =
      widget.backend.capabilities.has(KitCapability.context)
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
    final switchTo = widget.onSwitchWorkspace;
    if (switchTo == null) return;
    unawaited(
      showWorkspaceMenu(
        context,
        current: widget.workspace,
        workspaces: widget.workspaces,
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
        child: AgentWorkbench(
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
