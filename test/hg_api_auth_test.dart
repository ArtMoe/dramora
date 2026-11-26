import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/api/hg_api.dart';
import 'package:guomu/hg/api/hg_source_pool.dart';

class _TestRouter implements HgSourceRouter {
  _TestRouter(this.sources);

  final List<String> sources;

  @override
  String get baseUrl => sources.first;

  @override
  List<String> get rankedSources => sources;

  @override
  Future<void> recordFailure(String baseUrl) async {}

  @override
  Future<void> recordSuccess(
    String baseUrl,
    Duration latency, {
    required bool promote,
  }) async {}
}

typedef _Reply = ({int statusCode, Map<String, dynamic> body});

class _AuthServer {
  _AuthServer(this.server, this.replies) {
    server.listen(_handle);
  }

  final HttpServer server;
  final _Reply Function(String source, String apiPath, int call) replies;
  final Map<String, int> _calls = {};

  String get origin => 'http://127.0.0.1:${server.port}';

  Future<void> _handle(HttpRequest request) async {
    final rawBody = await utf8.decoder.bind(request).join();
    Map<String, dynamic>? envelope;
    if (rawBody.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawBody);
        if (decoded is Map) {
          envelope = Map<String, dynamic>.from(decoded);
        }
      } on FormatException {
        // Direct GET requests have no body; the route comes from the URI.
      }
    }

    final segments = request.uri.pathSegments;
    final hasSourcePrefix = segments.isNotEmpty && segments.first != 'api';
    final source = hasSourcePrefix ? segments.first : '';
    final directPath = segments.isEmpty
        ? ''
        : '/${segments.skip(hasSourcePrefix ? 1 : 0).join('/')}';
    final directRequestPath = request.uri.hasQuery
        ? '$directPath?${request.uri.query}'
        : directPath;
    final apiPath = directRequestPath.isNotEmpty
        ? directRequestPath
        : envelope?['path']?.toString() ?? '';
    final key = '$source:$apiPath';
    final call = (_calls[key] ?? 0) + 1;
    _calls[key] = call;
    final reply = replies(source, apiPath, call);
    request.response.statusCode = reply.statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(reply.body));
    await request.response.close();
  }

  Future<void> close() => server.close(force: true);
}

Map<String, dynamic> _unauthorized() => {'status': 0, 'msg': 'invalid token'};

Map<String, dynamic> _me() => {
  'status': 1,
  'data': {'id': 338861, 'username': 'DearLicy', 'nickname': 'DearLicy'},
};

void main() {
  test(
    'playback stays query-token-free in both guest and signed-in states',
    () async {
      final seenPaths = <String>[];
      late _AuthServer endpoint;
      endpoint = _AuthServer(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        (source, path, call) {
          seenPaths.add(path);
          if (Uri.parse(path).path == '/api/videos/12/episodes/1/playback') {
            if (Uri.parse(path).queryParameters.containsKey('token')) {
              return (statusCode: 200, body: {'status': 0, 'msg': '播放参数无效'});
            }
            return (
              statusCode: 200,
              body: {
                'status': 1,
                'data': {
                  'streams': {'main': 'https://cdn.test/main.m3u8'},
                },
              },
            );
          }
          return (statusCode: 404, body: {'status': 0});
        },
      );
      addTearDown(endpoint.close);
      final api = HgApi(
        dio: Dio(),
        sourceRouter: _TestRouter([endpoint.origin]),
      );

      final guest = await api.playback(12, 1);
      api.token = 'query-token';
      final signedIn = await api.playback(12, 1);

      expect(guest.videoUrl, 'https://cdn.test/main.m3u8');
      expect(signedIn.videoUrl, 'https://cdn.test/main.m3u8');
      expect(seenPaths, List.filled(2, '/api/videos/12/episodes/1/playback'));
    },
  );

  test(
    'authenticated requests use the upstream token query parameter',
    () async {
      final seenPaths = <String>[];
      late _AuthServer endpoint;
      endpoint = _AuthServer(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        (source, path, call) {
          seenPaths.add(path);
          final uri = Uri.parse(path);
          if (uri.path == '/api/account/me' &&
              uri.queryParameters['token'] == 'query-token') {
            return (statusCode: 200, body: _me());
          }
          if (uri.path == '/api/users/me/collects' &&
              uri.queryParameters['token'] == 'query-token' &&
              uri.queryParameters['page'] == '1' &&
              uri.queryParameters['size'] == '20') {
            return (
              statusCode: 200,
              body: {
                'status': 1,
                'data': {
                  'items': <Map<String, dynamic>>[],
                  'pagination': {'page': 1, 'pages': 0, 'total': 0},
                },
              },
            );
          }
          if (uri.path == '/api/account/logout' &&
              uri.queryParameters['token'] == 'query-token') {
            return (statusCode: 200, body: {'status': 1, 'data': true});
          }
          return (statusCode: 401, body: _unauthorized());
        },
      );
      addTearDown(endpoint.close);
      final api = HgApi(
        dio: Dio(),
        sourceRouter: _TestRouter([endpoint.origin]),
      )..token = 'query-token';

      final user = await api.me();
      final collects = await api.myCollects();
      await api.logout();

      expect(user.username, 'DearLicy');
      expect(collects.items, isEmpty);
      expect(seenPaths, [
        '/api/account/me?token=query-token',
        '/api/users/me/collects?page=1&size=20&token=query-token',
        '/api/account/logout?token=query-token',
      ]);
    },
  );

  test('a transient 401 does not clear a token that /me confirms', () async {
    late _AuthServer endpoint;
    endpoint = _AuthServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      (source, path, call) {
        if (path.startsWith('/api/users/me/collects')) {
          return (statusCode: 401, body: _unauthorized());
        }
        if (Uri.parse(path).path == '/api/account/me') {
          return (statusCode: 200, body: _me());
        }
        return (statusCode: 404, body: {'status': 0});
      },
    );
    addTearDown(endpoint.close);
    var expiredCalls = 0;
    final api =
        HgApi(
            dio: Dio(),
            sourceRouter: _TestRouter([
              endpoint.origin,
              '${endpoint.origin}/b',
            ]),
          )
          ..token = 'valid-token'
          ..onAuthenticationExpired = () => expiredCalls++;

    await expectLater(
      api.myCollects(),
      throwsA(
        isA<HgLoginRequiredException>().having(
          (error) => error.confirmed,
          'confirmed',
          isFalse,
        ),
      ),
    );
    expect(expiredCalls, 0);
  });

  test(
    'authenticated requests stay on the source that issued the token',
    () async {
      final primary = _AuthServer(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        (source, path, call) {
          if (path == '/api/account/loginByPassword') {
            return (
              statusCode: 200,
              body: {
                'status': 1,
                'data': {
                  'token': 'issued-by-a',
                  'user': {
                    'id': 338861,
                    'username': 'DearLicy',
                    'nickname': 'DearLicy',
                  },
                },
              },
            );
          }
          if (path.startsWith('/api/users/me/collects')) {
            return (
              statusCode: 200,
              body: {
                'status': 1,
                'data': {
                  'items': <Map<String, dynamic>>[],
                  'pagination': {'page': 1, 'pages': 0, 'total': 0},
                },
              },
            );
          }
          if (Uri.parse(path).path == '/api/account/me') {
            return (statusCode: 200, body: _me());
          }
          return (statusCode: 404, body: {'status': 0});
        },
      );
      final backup = _AuthServer(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        (source, path, call) => (statusCode: 401, body: _unauthorized()),
      );
      addTearDown(primary.close);
      addTearDown(backup.close);
      final api = HgApi(
        dio: Dio(),
        sourceRouter: _TestRouter([primary.origin, backup.origin]),
      );

      final session = await api.login('DearLicy', 'password');
      api.token = session.token;
      final collects = await api.myCollects();

      expect(collects.items, isEmpty);
      expect(api.baseUrl, primary.origin);
    },
  );

  test(
    'one rejecting source plus one valid source preserves the session',
    () async {
      late _AuthServer endpoint;
      endpoint = _AuthServer(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        (source, path, call) {
          if (path.startsWith('/api/users/me/collects')) {
            return (statusCode: 401, body: _unauthorized());
          }
          if (Uri.parse(path).path == '/api/account/me') {
            return source == 'a'
                ? (statusCode: 401, body: _unauthorized())
                : (statusCode: 200, body: _me());
          }
          return (statusCode: 404, body: {'status': 0});
        },
      );
      addTearDown(endpoint.close);
      var expiredCalls = 0;
      final api =
          HgApi(
              dio: Dio(),
              sourceRouter: _TestRouter([
                '${endpoint.origin}/a',
                '${endpoint.origin}/b',
              ]),
            )
            ..token = 'valid-token'
            ..onAuthenticationExpired = () => expiredCalls++;

      await expectLater(
        api.myCollects(),
        throwsA(
          isA<HgLoginRequiredException>().having(
            (error) => error.confirmed,
            'confirmed',
            isFalse,
          ),
        ),
      );
      expect(expiredCalls, 0);
    },
  );

  test('two sources rejecting /me confirm an expired token once', () async {
    late _AuthServer endpoint;
    endpoint = _AuthServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      (source, path, call) {
        if (path.startsWith('/api/users/me/collects')) {
          return (statusCode: 401, body: _unauthorized());
        }
        if (Uri.parse(path).path == '/api/account/me') {
          return (statusCode: 401, body: _unauthorized());
        }
        return (statusCode: 404, body: {'status': 0});
      },
    );
    addTearDown(endpoint.close);
    var expiredCalls = 0;
    final api =
        HgApi(
            dio: Dio(),
            sourceRouter: _TestRouter([
              '${endpoint.origin}/a',
              '${endpoint.origin}/b',
            ]),
          )
          ..token = 'expired-token'
          ..onAuthenticationExpired = () => expiredCalls++;

    await expectLater(
      api.myCollects(),
      throwsA(
        isA<HgLoginRequiredException>().having(
          (error) => error.confirmed,
          'confirmed',
          isTrue,
        ),
      ),
    );
    expect(expiredCalls, 1);
  });

  test(
    '403 is a permission error and never clears the login session',
    () async {
      late _AuthServer endpoint;
      endpoint = _AuthServer(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        (source, path, call) => (statusCode: 403, body: {'status': 0}),
      );
      addTearDown(endpoint.close);
      var expiredCalls = 0;
      final api =
          HgApi(dio: Dio(), sourceRouter: _TestRouter([endpoint.origin]))
            ..token = 'valid-token'
            ..onAuthenticationExpired = () => expiredCalls++;

      await expectLater(
        api.myCollects(),
        throwsA(
          isA<HgApiException>()
              .having((error) => error.statusCode, 'statusCode', 403)
              .having(
                (error) => error is HgLoginRequiredException,
                'loginRequired',
                isFalse,
              ),
        ),
      );
      expect(expiredCalls, 0);
    },
  );
}
