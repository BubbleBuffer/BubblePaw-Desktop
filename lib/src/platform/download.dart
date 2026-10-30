// Network access for downloads, behind a small interface so tests pass fakes,
// and the verified download app updates use: bytes go to a
// partial file, their SHA256 is checked, and only a match is kept.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

/// A response body and its length when the server said it.
class ByteSource {
  const ByteSource(this.bytes, this.length);

  final Stream<List<int>> bytes;
  final int? length;
}

/// What the network gives the app: text and a stream of bytes.
abstract interface class HttpFetcher {
  /// The body of [url] as text. Throws a [FetchException].
  Future<String> getText(Uri url);

  /// Opens [url] for streaming. Throws a [FetchException].
  Future<ByteSource> open(Uri url);
}

enum FetchFailure { offline, server, interrupted, checksum, cancelled }

/// Why a fetch ended. [message] is a sentence that can be shown.
class FetchException implements Exception {
  const FetchException(
    this.kind,
    this.message, {
    this.received,
    this.total,
    this.expected,
    this.actual,
  });

  final FetchFailure kind;
  final String message;

  /// Bytes received and expected when the download stopped.
  final int? received;
  final int? total;

  /// The checksums that disagreed (lower-case hex).
  final String? expected;
  final String? actual;

  @override
  String toString() => message;
}

/// Asked to stop a download; checked between chunks.
class DownloadCancel {
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// A fetcher for a computer with no network: every call fails as offline.
/// Used where nothing should reach the network (scripted runs, tests).
class OfflineFetcher implements HttpFetcher {
  const OfflineFetcher();

  static const _error = FetchException(
    FetchFailure.offline,
    'This computer is offline.',
  );

  @override
  Future<String> getText(Uri url) => Future.error(_error);

  @override
  Future<ByteSource> open(Uri url) => Future.error(_error);
}

/// The fetcher that uses dart:io.
class DartHttpFetcher implements HttpFetcher {
  const DartHttpFetcher();

  HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..userAgent = 'BubblePaw-Desktop';

  FetchException _map(Object error) {
    if (error is FetchException) return error;
    if (error is SocketException ||
        error is HandshakeException ||
        error is TimeoutException) {
      return const FetchException(
        FetchFailure.offline,
        'The server could not be reached.',
      );
    }
    return const FetchException(
      FetchFailure.interrupted,
      'The connection dropped.',
    );
  }

  Future<HttpClientResponse> _get(HttpClient client, Uri url) async {
    final request = await client.getUrl(url);
    request.headers.set('Accept', '*/*');
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw FetchException(
        FetchFailure.server,
        'The server answered ${response.statusCode}.',
      );
    }
    return response;
  }

  @override
  Future<String> getText(Uri url) async {
    final client = _client();
    try {
      final response = await _get(client, url);
      return await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 20));
    } on Object catch (error) {
      throw _map(error);
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<ByteSource> open(Uri url) async {
    final client = _client();
    try {
      final response = await _get(client, url);
      final length = response.contentLength < 0 ? null : response.contentLength;
      Stream<List<int>> bytes() async* {
        try {
          yield* response;
        } on Object catch (error) {
          throw _map(error);
        } finally {
          client.close(force: true);
        }
      }

      return ByteSource(bytes(), length);
    } on Object catch (error) {
      client.close(force: true);
      throw _map(error);
    }
  }
}

class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;

  @override
  void add(crypto.Digest data) => value = data;

  @override
  void close() {}
}

/// The lower-case hex SHA256 of [bytes].
String sha256Hex(List<int> bytes) => crypto.sha256.convert(bytes).toString();

/// Downloads [url] to [destination] and keeps it only when its SHA256 is
/// [expectedSha256]. Writes to `<destination>.part` first, so a stopped or
/// wrong download leaves nothing at [destination]. Throws a
/// [FetchException]: `checksum` carries both hashes, `cancelled` follows
/// [cancel], the rest say how far the download got.
Future<void> downloadVerified({
  required HttpFetcher fetcher,
  required Uri url,
  required String expectedSha256,
  required File destination,
  void Function(int received, int? total)? onProgress,
  DownloadCancel? cancel,
}) async {
  await destination.parent.create(recursive: true);
  final part = File('${destination.path}.part');
  final digest = _DigestSink();
  final hasher = crypto.sha256.startChunkedConversion(digest);
  IOSink? sink;
  var received = 0;
  int? total;
  const cancelled = FetchException(
    FetchFailure.cancelled,
    'The download was cancelled.',
  );
  try {
    final source = await fetcher.open(url);
    total = source.length;
    onProgress?.call(0, total);
    sink = part.openWrite();
    await for (final chunk in source.bytes) {
      if (cancel?.cancelled ?? false) throw cancelled;
      sink.add(chunk);
      hasher.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }
    if (cancel?.cancelled ?? false) throw cancelled;
    hasher.close();
    await sink.close();
    sink = null;
    if (total != null && received != total) {
      throw FetchException(
        FetchFailure.interrupted,
        'The download ended early.',
        received: received,
        total: total,
      );
    }
    final actual = digest.value.toString();
    final expected = expectedSha256.toLowerCase();
    if (actual != expected) {
      throw FetchException(
        FetchFailure.checksum,
        'The file does not match its published checksum.',
        expected: expected,
        actual: actual,
      );
    }
    if (await destination.exists()) await destination.delete();
    await part.rename(destination.path);
  } on Object catch (error) {
    try {
      await sink?.close();
    } on Object {
      // Already closed or broken; the partial file is removed below.
    }
    try {
      if (await part.exists()) await part.delete();
    } on Object {
      // A partial file that cannot be removed is overwritten next time.
    }
    if (error is FetchException) {
      // Progress at the point of failure, when the error does not carry it.
      if (error.kind == FetchFailure.interrupted && error.received == null) {
        throw FetchException(
          error.kind,
          error.message,
          received: received,
          total: total,
        );
      }
      rethrow;
    }
    throw FetchException(
      FetchFailure.interrupted,
      'The file could not be saved.',
      received: received,
      total: total,
    );
  }
}
