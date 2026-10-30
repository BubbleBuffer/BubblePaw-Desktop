// The BubblePaw host, in this process, as an agent-kit transport.
//
// Core runs inside the app (native/, through flutter_rust_bridge). The agent
// kit's BubblePawBackend speaks newline-delimited JSON-RPC through a
// BubblePawTransport; so that parsing, timeouts and error classification stay
// in the kit, this transport hands the kit's own stdio framing a pipe whose
// other end is the native host: each request line becomes one native call and
// each reply, error or notification becomes one line back.

import 'dart:async';
import 'dart:convert';

import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

import '../rust/api/host.dart' as native;
import '../rust/frb_generated.dart';

/// What the transport needs from the native host. The real one is
/// [NativeHostHandle]; tests pass fakes.
abstract interface class NativeHost {
  /// Another process owns the host; closing only ends this session.
  bool get attached;

  /// One host-API call. Throws [native.HostCallError].
  Future<String> call(String method, String paramsJson);

  /// Notifications as JSON text. Ends when the session does.
  Stream<String> notifications();

  Future<void> close();
}

typedef NativeHostOpener = Future<NativeHost> Function({
  required String dataDir,
  required String workspaceDir,
});

/// The Core release the app embeds, such as `0.4.0`.
String embeddedCoreVersion() => native.coreVersion();

Future<void>? _loading;

/// Where the native library is loaded from. Null finds it next to the app;
/// tests that run against a built `native/` crate point it at the file.
ExternalLibrary? nativeLibraryOverride;

/// Loads the native library once.
Future<void> loadNativeLibrary() =>
    _loading ??= RustLib.init(externalLibrary: nativeLibraryOverride);

/// Opens (attaches to or becomes) the host on [dataDir].
Future<NativeHost> openNativeHost({
  required String dataDir,
  required String workspaceDir,
}) async {
  await loadNativeLibrary();
  final host = await native.BubblePawHost.open(
    dataDir: dataDir,
    workspaceDir: workspaceDir,
  );
  return NativeHostHandle(host);
}

class NativeHostHandle implements NativeHost {
  NativeHostHandle(this._host);

  final native.BubblePawHost _host;

  @override
  bool get attached => _host.attached;

  @override
  Future<String> call(String method, String paramsJson) =>
      _host.call(method: method, paramsJson: paramsJson);

  @override
  Stream<String> notifications() => _host.notifications();

  @override
  Future<void> close() => _host.close();
}

class FfiBubblePawTransport implements BubblePawTransport {
  FfiBubblePawTransport._(this._pipe, this._inner);

  /// Opens the host on [dataDirectory] through [opener] (the native one by
  /// default) and returns a transport over it.
  static Future<FfiBubblePawTransport> open({
    required String dataDirectory,
    required String workspaceDirectory,
    NativeHostOpener opener = openNativeHost,
    Duration requestTimeout = const Duration(seconds: 30),
    Duration shutdownTimeout = const Duration(seconds: 5),
  }) async {
    final NativeHost host;
    try {
      host = await opener(
        dataDir: dataDirectory,
        workspaceDir: workspaceDirectory,
      );
    } on native.HostCallError catch (error) {
      // The host's own words: it names the cause (a locked store, a bad
      // config) that "could not start" cannot.
      final text = error.message.trim();
      throw BubblePawException(
        'startFailed',
        text.isEmpty
            ? 'The BubblePaw host could not be started.'
            : text.endsWith('.')
            ? text
            : '$text.',
      );
    }
    final pipe = _HostPipe(host);
    final inner = StdioBubblePawTransport.forTesting(
      stdout: pipe.stdout,
      stdin: pipe.stdin,
      exitCode: pipe.exitCode,
      requestTimeout: requestTimeout,
      shutdownTimeout: shutdownTimeout,
    );
    return FfiBubblePawTransport._(pipe, inner);
  }

  final _HostPipe _pipe;
  final StdioBubblePawTransport _inner;

  /// The host was already running in another process.
  bool get attached => _pipe.host.attached;

  @override
  Future<Object?> request(
    String method, [
    Map<String, Object?> params = const {},
  ]) => _inner.request(method, params);

  @override
  Stream<Map<String, Object?>> get notifications => _inner.notifications;

  @override
  Future<void> dispose() => _inner.dispose();
}

/// The pipe the kit's stdio transport talks to.
class _HostPipe {
  _HostPipe(this.host) {
    stdin = _RequestSink(_request);
    _subscription = host.notifications().listen(
      _writeLine,
      onError: (Object _) => _lose(),
      onDone: () {
        if (!_closing) _lose();
      },
    );
  }

  final NativeHost host;
  late final _RequestSink stdin;
  final _out = StreamController<List<int>>();
  final _exit = Completer<int>();
  StreamSubscription<String>? _subscription;
  bool _closing = false;
  bool _lost = false;

  Stream<List<int>> get stdout => _out.stream;
  Future<int> get exitCode => _exit.future;

  void _writeLine(String line) {
    if (_out.isClosed) return;
    _out.add(utf8.encode('$line\n'));
  }

  Future<void> _request(String line) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, Object?>) return;
    final id = decoded['id'];
    final method = decoded['method'];
    if (id is! int || method is! String) return;
    if (method == 'shutdown') {
      _writeLine('{"jsonrpc":"2.0","id":$id,"result":{}}');
      unawaited(_shutdown());
      return;
    }
    try {
      final result = await host.call(
        method,
        jsonEncode(decoded['params'] ?? {}),
      );
      _writeLine('{"jsonrpc":"2.0","id":$id,"result":$result}');
    } on native.HostCallError catch (error) {
      switch (error.kind) {
        case native.HostErrorKind.rpc:
          _writeLine(
            _errorFrame(id, error.code.toInt(), error.message, error.dataJson),
          );
        case native.HostErrorKind.invalidParams:
          _writeLine(_errorFrame(id, -32602, error.message, null));
        case native.HostErrorKind.disconnected ||
            native.HostErrorKind.protocol ||
            native.HostErrorKind.host ||
            native.HostErrorKind.closed:
          _lose();
      }
    } on Object {
      _lose();
    }
  }

  static String _errorFrame(int id, int code, String message, String? data) {
    final error = <String, Object?>{'code': code, 'message': message};
    // `data` is already JSON text; keep it out of the string-encoded fields.
    final head = jsonEncode(error);
    final body = data == null
        ? head
        : '${head.substring(0, head.length - 1)},"data":$data}';
    return '{"jsonrpc":"2.0","id":$id,"error":$body}';
  }

  Future<void> _shutdown() async {
    if (_closing) return;
    _closing = true;
    try {
      await host.close();
    } on Object {
      // The host is gone either way.
    }
    // Not awaited: the generated stream's cancel completes only when the
    // native side lets go of the sink, which can take until the process ends.
    unawaited(_subscription?.cancel());
    await _finish(0);
  }

  /// The session ended without being asked to: the kit sees the host exit.
  void _lose() {
    if (_lost || _closing) return;
    _lost = true;
    unawaited(_subscription?.cancel());
    unawaited(() async {
      try {
        await host.close();
      } on Object {
        // Already gone.
      }
      await _finish(1);
    }());
  }

  Future<void> _finish(int code) async {
    if (!_out.isClosed) await _out.close();
    if (!_exit.isCompleted) _exit.complete(code);
  }
}

class _RequestSink implements StreamSink<List<int>> {
  _RequestSink(this._onLine);

  final Future<void> Function(String line) _onLine;
  final List<int> _buffer = [];
  final _done = Completer<void>();

  @override
  void add(List<int> data) {
    for (final byte in data) {
      if (byte == 10) {
        final line = utf8.decode(_buffer, allowMalformed: true);
        _buffer.clear();
        if (line.isNotEmpty) unawaited(_onLine(line));
      } else {
        _buffer.add(byte);
      }
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.forEach(add);

  @override
  Future<void> close() {
    if (!_done.isCompleted) _done.complete();
    return _done.future;
  }

  @override
  Future<void> get done => _done.future;
}
