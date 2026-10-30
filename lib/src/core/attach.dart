// Attaching to a host that is already running on the selected data
// directory, instead of starting a second one on the same store.

import '../config.dart';
import '../host_controller.dart';

/// Connects to a host that already runs on [AppConfig.dataDirectory].
/// Returns null when there is none, so the caller starts its own.
///
/// The returned backend's `dispose` must only disconnect: an attached host
/// keeps running when BubblePaw detaches or quits.
typedef HostAttacher = Future<StartedBackend?> Function(AppConfig config);

/// Looks for a running host on the data directory of [config].
///
/// TODO(core): Core does not publish a discovery file or listen on an
/// endpoint yet (the stdio transport in agent_kit_bubblepaw only talks to a
/// child it starts), so there is nothing to find and this always answers
/// null. When Core writes a discovery file into its data directory, read it
/// here and connect to the endpoint it names.
Future<StartedBackend?> attachToRunningHost(AppConfig config) async => null;
