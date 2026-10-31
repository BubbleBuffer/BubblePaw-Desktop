// config.get and config.set over the agent kit's transport: the request
// shapes, and how the replies and refusals read.

import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';
import 'package:bubblepaw_desktop/src/core/host_settings.dart';
import 'package:flutter_test/flutter_test.dart';

class _Transport implements BubblePawTransport {
  final calls = <(String, Map<String, Object?>)>[];
  Object? reply;
  BubblePawException? error;

  @override
  Future<Object?> request(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    calls.add((method, params));
    final failure = error;
    if (failure != null) throw failure;
    return reply;
  }

  @override
  Stream<Map<String, Object?>> get notifications => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

void main() {
  test('get sends the key and reads each setting', () async {
    final transport = _Transport()
      ..reply = {
        'settings': [
          {
            'key': 'model.main',
            'value': 'demo/scripted',
            'live': true,
            'pending_restart': false,
          },
          {
            'key': 'model.provider',
            'value': null,
            'live': true,
            'pending_restart': true,
          },
        ],
      };
    final settings = TransportHostSettings(transport);
    final list = await settings.get('model');
    expect(transport.calls.single.$1, 'config.get');
    expect(transport.calls.single.$2, {'key': 'model'});
    expect(list.map((s) => s.key), ['model.main', 'model.provider']);
    expect(list.first.value, 'demo/scripted');
    expect(list.last.value, isNull);
    expect(list.last.pendingRestart, isTrue);
  });

  test('get without a key asks for everything', () async {
    final transport = _Transport()..reply = {'settings': <Object?>[]};
    await TransportHostSettings(transport).get();
    expect(transport.calls.single.$1, 'config.get');
    expect(transport.calls.single.$2, isEmpty);
  });

  test('a host that sends no settings list says so', () async {
    final transport = _Transport()..reply = {'version': '0.6.0'};
    expect(
      TransportHostSettings(transport).get(),
      throwsA(isA<HostSettingsException>()),
    );
  });

  test('set sends key and value and reads live and restart_required', () async {
    final transport = _Transport()
      ..reply = {'key': 'model.main', 'applied': 'live', 'reload': null};
    final settings = TransportHostSettings(transport);
    final live = await settings.set('model.main', 'demo/scripted-fast');
    final call = transport.calls.single;
    expect(call.$1, 'config.set');
    expect(call.$2, {'key': 'model.main', 'value': 'demo/scripted-fast'});
    expect(live.applied, SettingApplied.live);

    transport.reply = {
      'key': 'storage.data_dir',
      'applied': 'restart_required',
    };
    final later = await settings.set('storage.data_dir', '/data');
    expect(later.applied, SettingApplied.restartRequired);
  });

  test('a refusal reaches the caller with the kit\'s safe message', () async {
    final transport = _Transport()
      ..error = const BubblePawException(
        'rpcError',
        'The BubblePaw host rejected the request.',
      );
    await expectLater(
      TransportHostSettings(transport).set('model.main', 7),
      throwsA(
        isA<HostSettingsException>().having(
          (e) => e.message,
          'message',
          'The BubblePaw host rejected the request.',
        ),
      ),
    );
  });

  test('an unknown applied value is an error', () async {
    final transport = _Transport()..reply = {'applied': 'maybe'};
    expect(
      TransportHostSettings(transport).set('model.main', 'x'),
      throwsA(isA<HostSettingsException>()),
    );
  });
}
