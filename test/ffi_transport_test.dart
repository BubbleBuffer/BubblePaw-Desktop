// The embedded host as the kit's transport, over a fake NativeHost (no native
// library): requests, errors, notifications, shutdown and a lost session.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';
import 'package:bubblepaw_desktop/src/config.dart';
import 'package:bubblepaw_desktop/src/core/ffi_transport.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/rust/api/host.dart';
import 'package:flutter_test/flutter_test.dart';

/// A host that answers from [handlers] and speaks through [events].
class FakeNativeHost implements NativeHost {
  FakeNativeHost({this.attached = false});

  @override
  final bool attached;

  /// `(method, paramsJson)` of every call, in order.
  final calls = <(String, String)>[];

  /// The result JSON for a method; a handler may throw a [HostCallError].
  final handlers = <String, FutureOr<String> Function(String paramsJson)>{};

  final events = StreamController<String>();
  var closeCalls = 0;

  @override
  Future<String> call(String method, String paramsJson) async {
    calls.add((method, paramsJson));
    final handler = handlers[method];
    if (handler == null) {
      throw HostCallError(
        kind: HostErrorKind.rpc,
        code: -32601,
        message: 'unknown method',
      );
    }
    return handler(paramsJson);
  }

  @override
  Stream<String> notifications() => events.stream;

  @override
  Future<void> close() async {
    closeCalls++;
    if (!events.isClosed) unawaited(events.close());
  }
}

Future<FfiBubblePawTransport> _open(FakeNativeHost host) =>
    FfiBubblePawTransport.open(
      dataDirectory: '/d',
      workspaceDirectory: '/w',
      opener: ({required dataDir, required workspaceDir}) async => host,
      requestTimeout: const Duration(seconds: 5),
      shutdownTimeout: const Duration(seconds: 2),
    );

String _fail(HostErrorKind kind, int code, String message, [String? data]) =>
    throw HostCallError(
      kind: kind,
      code: code,
      message: message,
      dataJson: data,
    );

String _initialize(String _) => jsonEncode({
  'protocol_version': BubblePawBackend.protocolVersion,
  'features': ['sessions', 'events'],
});

void main() {
  test(
    'an initialize request makes one native call and returns its result',
    () async {
      final host = FakeNativeHost()..handlers['initialize'] = _initialize;
      final transport = await _open(host);
      addTearDown(transport.dispose);

      final result = await transport.request('initialize');
      expect(result, {
        'protocol_version': BubblePawBackend.protocolVersion,
        'features': ['sessions', 'events'],
      });
      expect(host.calls, [('initialize', '{}')]);
    },
  );

  test('request parameters reach the host as JSON', () async {
    final host = FakeNativeHost()
      ..handlers['session.open'] = (params) => '{"echo":$params}';
    final transport = await _open(host);
    addTearDown(transport.dispose);

    final result = await transport.request('session.open', {'title': 'T'});
    expect(result, {
      'echo': {'title': 'T'},
    });
    expect(jsonDecode(host.calls.single.$2), {'title': 'T'});
  });

  test('the transport reports whether the host was already running', () async {
    final host = FakeNativeHost(attached: true);
    final transport = await _open(host);
    addTearDown(transport.dispose);
    expect(transport.attached, isTrue);
  });

  test(
    'an RPC error with its code and message is classified by the kit',
    () async {
      final host = FakeNativeHost();
      host.handlers['session.get'] = (_) =>
          _fail(HostErrorKind.rpc, -32000, 'unknown session s_1', '{"x":1}');
      host.handlers['session.send'] = (_) =>
          _fail(HostErrorKind.rpc, -32000, 'session is busy');
      host.handlers['session.rename'] = (_) =>
          _fail(HostErrorKind.invalidParams, 0, 'invalid title');
      final transport = await _open(host);
      addTearDown(transport.dispose);

      await expectLater(
        transport.request('session.get'),
        throwsA(
          isA<BubblePawException>().having((e) => e.code, 'code', 'notFound'),
        ),
      );
      await expectLater(
        transport.request('session.send'),
        throwsA(
          isA<BubblePawException>().having((e) => e.code, 'code', 'busy'),
        ),
      );
      // Invalid parameters are sent as -32602 and classified from the message.
      await expectLater(
        transport.request('session.rename'),
        throwsA(
          isA<BubblePawException>().having((e) => e.code, 'code', 'invalid'),
        ),
      );
    },
  );

  test('a notification line becomes a notification', () async {
    final host = FakeNativeHost();
    final transport = await _open(host);
    addTearDown(transport.dispose);

    final first = transport.notifications.first;
    host.events.add(
      '{"jsonrpc":"2.0","method":"event","params":{"session":"s_1","seq":1}}',
    );
    expect(await first, {
      'jsonrpc': '2.0',
      'method': 'event',
      'params': {'session': 's_1', 'seq': 1},
    });
  });

  test('dispose closes the host and does not send shutdown to it', () async {
    final host = FakeNativeHost()..handlers['initialize'] = _initialize;
    final transport = await _open(host);
    await transport.request('initialize');

    await transport.dispose();
    expect(host.closeCalls, 1);
    expect(host.calls.map((c) => c.$1), ['initialize']);
  });

  test('the notification stream ending unasked is a host exit', () async {
    final host = FakeNativeHost()
      ..handlers['session.get'] = (_) => Completer<String>().future;
    final transport = await _open(host);
    addTearDown(transport.dispose);

    final lost = expectLater(
      transport.notifications,
      emitsError(
        isA<BubblePawHostExited>().having((e) => e.exitCode, 'exitCode', 1),
      ),
    );
    // A call in flight when the session ends fails with the exit too.
    final pending = expectLater(
      transport.request('session.get'),
      throwsA(isA<BubblePawHostExited>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await host.events.close();
    await lost;
    await pending;
    expect(host.closeCalls, 1);
  });

  test('a lost session completes the backend connectionLost', () async {
    final host = FakeNativeHost()..handlers['initialize'] = _initialize;
    final transport = await _open(host);
    final backend = await BubblePawBackend.connect(
      transport,
      workspaceDirectory: '/w',
    );
    addTearDown(backend.dispose);

    await host.events.close();
    expect(await backend.connectionLost, isA<BubblePawHostExited>());
  });

  test('a session ended on purpose is not a loss', () async {
    final host = FakeNativeHost()..handlers['initialize'] = _initialize;
    final transport = await _open(host);
    final backend = await BubblePawBackend.connect(
      transport,
      workspaceDirectory: '/w',
    );
    var lost = false;
    unawaited(backend.connectionLost.then((_) => lost = true));

    await backend.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(lost, isFalse);
    expect(host.closeCalls, 1);
  });

  group('opening the host', () {
    test(
      'an opener failing with HostCallError becomes startFailed with its text',
      () async {
        Future<NativeHost> failing({
          required String dataDir,
          required String workspaceDir,
        }) async => throw HostCallError(
          kind: HostErrorKind.host,
          code: 0,
          message: 'The data directory is locked',
        );

        await expectLater(
          FfiBubblePawTransport.open(
            dataDirectory: '/d',
            workspaceDirectory: '/w',
            opener: failing,
          ),
          throwsA(
            isA<BubblePawException>()
                .having((e) => e.code, 'code', 'startFailed')
                .having(
                  (e) => e.message,
                  'message',
                  'The data directory is locked.',
                ),
          ),
        );
      },
    );

    test('an empty host message gets a plain one', () async {
      await expectLater(
        FfiBubblePawTransport.open(
          dataDirectory: '/d',
          workspaceDirectory: '/w',
          opener: ({required dataDir, required workspaceDir}) async =>
              throw HostCallError(
                kind: HostErrorKind.host,
                code: 0,
                message: '  ',
              ),
        ),
        throwsA(
          isA<BubblePawException>().having(
            (e) => e.message,
            'message',
            'The BubblePaw host could not be started.',
          ),
        ),
      );
    });

    test(
      'startBubblePaw passes the directories and surfaces the failure',
      () async {
        final root = await Directory.systemTemp.createTemp('bpd-ffi');
        addTearDown(() => root.delete(recursive: true));
        String? data;
        String? workspace;
        await expectLater(
          startBubblePaw(
            AppConfig(
              workspaceDirectory: '${root.path}/workspace',
              dataDirectory: '${root.path}/data',
            ),
            opener: ({required dataDir, required workspaceDir}) async {
              data = dataDir;
              workspace = workspaceDir;
              throw HostCallError(
                kind: HostErrorKind.host,
                code: 0,
                message: 'Another BubblePaw owns this data directory.',
              );
            },
          ),
          throwsA(
            isA<BubblePawException>()
                .having((e) => e.code, 'code', 'startFailed')
                .having(
                  (e) => e.message,
                  'message',
                  'Another BubblePaw owns this data directory.',
                ),
          ),
        );
        expect(data, '${root.path}/data');
        expect(workspace, '${root.path}/workspace');
        expect(Directory('${root.path}/data').existsSync(), isTrue);
      },
    );
  });
}
