// The phone's home when no host is open: the host menu and Settings, and a
// line saying what to do. With a host open the chat list is home instead (the
// workbench); this is only the empty state.

import 'package:agent_kit/agent_kit.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../feedback/glyphs.dart' show glyphChevronDown;
import '../settings/remote_glyphs.dart';
import '../settings/settings_widgets.dart' show glyphIcon;
import 'workspace_menu.dart';

class PhoneHome extends StatelessWidget {
  const PhoneHome({
    super.key,
    required this.hostMenu,
    required this.onSettings,
    this.hasHosts = false,
    this.opening = false,
  });

  final HostMenu? hostMenu;
  final VoidCallback onSettings;

  /// Hosts are saved, but none is open (it did not answer, or none was tried).
  final bool hasHosts;

  /// A host is being connected to.
  final bool opening;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final menu = hostMenu;
    final message = opening
        ? 'Opening the host.'
        : hasHosts
        ? 'No host is open. Open the host menu and choose a host to see its '
              'chats.'
        : 'No host selected. Open the host menu and add a host to see its '
              'chats.';
    return ColoredBox(
      color: theme.canvas,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: hasHosts ? 'Hosts' : 'Add a host',
                      excludeSemantics: true,
                      onTap: menu == null
                          ? null
                          : () => showHostSheet(context, hosts: menu),
                      child: Hover(
                        key: const ValueKey('phone-host-button'),
                        onTap: menu == null
                            ? null
                            : () => showHostSheet(context, hosts: menu),
                        borderRadius: theme.radii.ctl,
                        lift: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: SizedBox(
                          height: 48,
                          child: Row(
                            children: [
                              glyphIcon(
                                glyphMonitor,
                                size: 18,
                                color: theme.muted,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  hasHosts ? 'No host' : 'Add a host',
                                  style: ts(
                                    theme.typeScale.ui,
                                    theme.ink,
                                    weight: 700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              glyphIcon(
                                glyphChevronDown,
                                size: 16,
                                color: theme.muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Settings',
                    excludeSemantics: true,
                    onTap: onSettings,
                    child: Hover(
                      key: const ValueKey('phone-settings'),
                      onTap: onSettings,
                      borderRadius: theme.radii.ctl,
                      lift: 0,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: glyphIcon(
                            glyphSettings,
                            size: 20,
                            color: theme.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      message,
                      key: const ValueKey('phone-home-message'),
                      textAlign: TextAlign.center,
                      style: ts(theme.typeScale.ui, theme.muted),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Opacity(
                opacity: 0.5,
                child: PrimaryButton(
                  key: const ValueKey('phone-new-chat'),
                  label: 'New chat',
                  height: 48,
                  icon: Ico.compose,
                  onTap: () {},
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
