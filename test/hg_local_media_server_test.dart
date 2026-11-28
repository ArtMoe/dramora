import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/services/hg_local_media_server_native.dart';

void main() {
  test(
    'serves downloaded HLS playlists and byte ranges over loopback',
    () async {
      final root = await Directory('.tmp').create(recursive: true);
      final directory = await root.createTemp('local-media-server-');
      final playlist = File('${directory.path}/index.m3u8');
      final segment = File('${directory.path}/seg_00000.ts');
      await playlist.writeAsString('''#EXTM3U
#EXTINF:2,
seg_00000.ts
#EXT-X-ENDLIST
''');
      await segment.writeAsString('abcdef');
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await HgLocalMediaServer.shutdown();
        await directory.delete(recursive: true);
      });

      final url = await HgLocalMediaServer.playlistUrl(playlist.path);
      expect(url, isNotNull);
      expect(url, startsWith('http://127.0.0.1:'));

      final playlistRequest = await client.getUrl(Uri.parse(url!));
      final playlistResponse = await playlistRequest.close();
      final playlistBody = await playlistResponse
          .transform(utf8.decoder)
          .join();
      expect(playlistResponse.statusCode, HttpStatus.ok);
      expect(
        playlistResponse.headers.contentType?.mimeType,
        contains('mpegurl'),
      );
      expect(playlistBody, contains('seg_00000.ts'));

      final segmentUri = Uri.parse(url).resolve('seg_00000.ts');
      final rangeRequest = await client.getUrl(segmentUri);
      rangeRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=1-3');
      final rangeResponse = await rangeRequest.close();
      final bytes = await rangeResponse.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      expect(rangeResponse.statusCode, HttpStatus.partialContent);
      expect(
        rangeResponse.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 1-3/6',
      );
      expect(utf8.decode(bytes), 'bcd');
    },
  );

  test('serves downloaded direct video files with byte ranges', () async {
    final root = await Directory('.tmp').create(recursive: true);
    final directory = await root.createTemp('local-media-video-');
    final video = File('${directory.path}/video.mp4');
    await video.writeAsBytes(List<int>.generate(12, (index) => index));
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await HgLocalMediaServer.shutdown();
      await directory.delete(recursive: true);
    });

    final url = await HgLocalMediaServer.playlistUrl(video.path);
    expect(url, isNotNull);
    final request = await client.getUrl(Uri.parse(url!));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=4-7');
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );

    expect(response.statusCode, HttpStatus.partialContent);
    expect(response.headers.contentType?.mimeType, 'video/mp4');
    expect(bytes, <int>[4, 5, 6, 7]);
  });
}
