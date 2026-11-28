import 'dart:async';
import 'dart:io';

/// Serves downloaded HLS files over loopback because native HLS players handle
/// HTTP media sources more consistently than `file://` playlists on mobile.
abstract final class HgLocalMediaServer {
  static HttpServer? _server;
  static Future<HttpServer>? _starting;
  static final Map<String, Directory> _mounts = {};
  static final Map<String, String> _directoryTokens = {};
  static int _nextToken = 0;

  static Future<String?> playlistUrl(String manifestPath) async {
    final manifest = File(manifestPath);
    if (!await manifest.exists()) return null;
    final server = await (_starting ??= _startServer());
    final directory = manifest.parent.absolute;
    var token = _directoryTokens[directory.path];
    if (token == null) {
      token = 'm${DateTime.now().millisecondsSinceEpoch}-${_nextToken++}';
      _directoryTokens[directory.path] = token;
      _mounts[token] = directory;
    }
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      pathSegments: ['media', token, manifest.uri.pathSegments.last],
    ).toString();
  }

  static Future<HttpServer> _startServer() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((request) => unawaited(_handle(request)));
    return server;
  }

  static Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments;
      if (segments.length != 3 || segments.first != 'media') {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final directory = _mounts[segments[1]];
      final fileName = segments[2];
      if (directory == null ||
          fileName.isEmpty ||
          fileName == '.' ||
          fileName == '..') {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final file = File('${directory.path}/$fileName');
      if (!await file.exists()) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }

      final size = await file.length();
      var start = 0;
      var end = size > 0 ? size - 1 : 0;
      final range = _parseRange(
        request.headers.value(HttpHeaders.rangeHeader),
        size,
      );
      if (range == null &&
          request.headers.value(HttpHeaders.rangeHeader) != null) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
        return;
      }
      if (range != null) {
        start = range.$1;
        end = range.$2;
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$size',
        );
      }

      response.headers.contentType = _contentType(file.path);
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.contentLength = size == 0 ? 0 : end - start + 1;
      if (request.method == 'HEAD' || size == 0) return;
      await response.addStream(file.openRead(start, end + 1));
    } catch (_) {
      try {
        response.statusCode = HttpStatus.internalServerError;
      } catch (_) {}
    } finally {
      await response.close();
    }
  }

  static (int, int)? _parseRange(String? header, int size) {
    if (header == null || header.trim().isEmpty) return null;
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (match == null || size <= 0) return null;
    final startText = match.group(1) ?? '';
    final endText = match.group(2) ?? '';
    int start;
    int end;
    if (startText.isEmpty) {
      final suffixLength = int.tryParse(endText);
      if (suffixLength == null || suffixLength <= 0) return null;
      start = (size - suffixLength).clamp(0, size - 1);
      end = size - 1;
    } else {
      final parsedStart = int.tryParse(startText);
      if (parsedStart == null || parsedStart < 0 || parsedStart >= size) {
        return null;
      }
      start = parsedStart;
      final parsedEnd = endText.isEmpty ? size - 1 : int.tryParse(endText);
      if (parsedEnd == null || parsedEnd < start) return null;
      end = parsedEnd.clamp(start, size - 1);
    }
    return (start, end);
  }

  static ContentType _contentType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.m3u8')) {
      return ContentType('application', 'vnd.apple.mpegurl');
    }
    if (lower.endsWith('.ts') || lower.endsWith('.mts')) {
      return ContentType('video', 'mp2t');
    }
    if (lower.endsWith('.m4s')) return ContentType('video', 'iso.segment');
    if (lower.endsWith('.mp4')) return ContentType('video', 'mp4');
    if (lower.endsWith('.aac')) return ContentType('audio', 'aac');
    if (lower.endsWith('.key')) {
      return ContentType('application', 'octet-stream');
    }
    return ContentType.binary;
  }

  static Future<void> shutdown() async {
    final server = _server;
    _server = null;
    _starting = null;
    _mounts.clear();
    _directoryTokens.clear();
    if (server != null) await server.close(force: true);
  }
}
