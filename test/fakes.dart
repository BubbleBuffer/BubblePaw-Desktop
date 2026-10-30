// Fakes for the network and the installer, so
// no test reaches the internet or runs `tar`.

import 'dart:async';
import 'dart:io';

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
