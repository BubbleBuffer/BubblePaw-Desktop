// Fakes for the network and the installer, so
// no test reaches the internet or runs `tar`.

import 'dart:async';
import 'dart:io';

import 'package:bubblepaw_desktop/src/core/host_settings.dart';
import 'package:bubblepaw_desktop/src/platform/download.dart';
import 'package:bubblepaw_desktop/src/updates/update_controller.dart';

/// Serves texts and bytes by URL. A URL with no entry answers 404.
class FakeFetcher implements HttpFetcher {
  final texts = <String, String>{};
  final bytes = <String, List<int>>{};

  /// Throws for every call when set.
  FetchException? failWith;

  /// The byte stream stops after this many bytes with an error.
  int? breakAfter;

  /// Keeps the byte stream open after its data, for a download in progress.
  Completer<void>? hold;

  final requested = <String>[];

  @override
  Future<String> getText(Uri url) async {
    requested.add(url.toString());
    final failure = failWith;
    if (failure != null) throw failure;
    final text = texts[url.toString()];
    if (text == null) {
      throw const FetchException(
        FetchFailure.server,
        'The server answered 404.',
      );
    }
    return text;
  }

  @override
  Future<ByteSource> open(Uri url) async {
    requested.add(url.toString());
    final failure = failWith;
    if (failure != null) throw failure;
    final data = bytes[url.toString()];
    if (data == null) {
      throw const FetchException(
        FetchFailure.server,
        'The server answered 404.',
      );
    }
    Stream<List<int>> stream() async* {
      final cut = breakAfter;
      if (cut != null && cut < data.length) {
        yield data.sublist(0, cut);
        throw const FetchException(
          FetchFailure.interrupted,
          'The connection dropped.',
        );
      }
      // Two chunks, so progress moves.
      final half = data.length ~/ 2;
      yield data.sublist(0, half);
      yield data.sublist(half);
      await hold?.future;
    }

    return ByteSource(stream(), data.length);
  }
}

/// An installer that records what it was asked.
class FakeInstaller implements UpdateInstaller {
  FakeInstaller({this.canInstall = true, this.fails = false});

  @override
  final bool canInstall;
  final bool fails;
  final installed = <String>[];

  @override
  Future<void> install(File file) async {
    if (fails) throw const FileSystemException('no');
    installed.add(file.path);
  }
}

/// The host's settings in memory, with the calls it received. A key in
/// [restartOnly] answers `restart_required` to a change and keeps the
/// running value; any other key applies at once.
class FakeHostSettings implements HostSettings {
  FakeHostSettings({
    Map<String, Object?>? values,
    this.restartOnly = const {},
    this.failWith,
    this.toolList = const [],
    this.skillList = const [],
  }) : values = {...?values};

  /// What `tools.list` reports.
  final List<HostTool> toolList;

  /// What `skills.list` reports; a skill's switch is its
  /// `skills.<name>.enabled` value when one is set.
  final List<HostSkill> skillList;

  final Map<String, Object?> values;

  /// Keys whose changes apply after a restart.
  final Set<String> restartOnly;

  /// Throws for every `set` when given.
  HostSettingsException? failWith;

  final reads = <String?>[];
  final writes = <(String, Object?)>[];

  @override
  Future<List<HostSetting>> get([String? key]) async {
    reads.add(key);
    return [
      for (final entry in values.entries)
        if (key == null || entry.key == key || entry.key.startsWith('$key.'))
          HostSetting(key: entry.key, value: entry.value),
    ];
  }

  @override
  Future<SettingChange> set(String key, Object? value) async {
    writes.add((key, value));
    final failure = failWith;
    if (failure != null) throw failure;
    if (restartOnly.contains(key)) {
      return SettingChange(key: key, applied: SettingApplied.restartRequired);
    }
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
    return SettingChange(key: key, applied: SettingApplied.live);
  }

  @override
  Future<List<HostTool>> tools() async => toolList;

  @override
  Future<HostSkills> skills() async => HostSkills(
    enabled: true,
    skills: [
      for (final skill in skillList)
        HostSkill(
          name: skill.name,
          description: skill.description,
          source: skill.source,
          path: skill.path,
          enabled: values['skills.${skill.name}.enabled'] is bool
              ? values['skills.${skill.name}.enabled']! as bool
              : skill.enabled,
        ),
    ],
  );
}
