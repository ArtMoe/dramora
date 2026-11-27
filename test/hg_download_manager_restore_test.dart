import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guomu/hg/api/hg_api.dart';
import 'package:guomu/hg/models/hg_download_models.dart';
import 'package:guomu/hg/models/hg_models.dart';
import 'package:guomu/hg/utils/hg_download_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ResumeApi extends HgApi {
  _ResumeApi() : super(baseUrl: 'https://example.test');

  @override
  Future<HgVideoDetail> video(int id) async {
    return HgVideoDetail.fromJson({
      'id': id,
      'title': '恢复下载测试',
      'episode_count': 1,
      'episodes': [
        {'ep_num': 1},
      ],
    });
  }
}

class _ResumeDownloads extends HgDownloadManager {
  _ResumeDownloads(super.api, super.prefs);

  final List<int> resumed = [];

  @override
  Future<void> startDramaDownload(
    HgVideoDetail detail, {
    bool? autoUpdate,
    bool downloadNow = true,
  }) async {
    resumed.add(detail.id);
  }
}

void main() {
  test(
    'interrupted downloads are marked then resumed after app restore',
    () async {
      final task = const HgDownloadTask(
        videoId: 10586,
        title: '蜜桃臀',
        cover: '',
        totalEpisodes: 6,
        state: '下载中 · 第 1/6 集',
        progress: 0.1,
        receivedBytes: 20 * 1024 * 1024,
        totalBytes: 500 * 1024 * 1024,
        speedBytesPerSecond: 100 * 1024,
      );
      SharedPreferences.setMockInitialValues({
        'guomu.downloads.v1': jsonEncode([task.toJson()]),
      });
      final prefs = await SharedPreferences.getInstance();
      final manager = _ResumeDownloads(_ResumeApi(), prefs);
      addTearDown(manager.dispose);

      await manager.restore();

      expect(manager.tasks.single.state, '等待恢复');
      expect(manager.tasks.single.speedBytesPerSecond, 0);
      expect(manager.tasks.single.isDownloading, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 1400));
      expect(manager.resumed, [10586]);
    },
  );

  test(
    'incomplete downloaded HLS playlists are not treated as playable',
    () async {
      final root = await Directory('.tmp').create(recursive: true);
      final directory = await root.createTemp('download-integrity-');
      final manifest = File('${directory.path}/index.m3u8');
      await manifest.writeAsString('''#EXTM3U
#EXTINF:2,
seg_00000.ts
#EXT-X-ENDLIST
''');
      addTearDown(() => directory.delete(recursive: true));
      final task = HgDownloadTask(
        videoId: 20001,
        title: '缓存完整性测试',
        cover: '',
        totalEpisodes: 1,
        state: '已缓存',
        episodes: {
          1: HgDownloadedEpisode(
            number: 1,
            directory: directory.path,
            manifestPath: manifest.path,
            bytes: 100,
            updatedAt: '',
          ),
        },
      );
      SharedPreferences.setMockInitialValues({
        'guomu.downloads.v1': jsonEncode([task.toJson()]),
      });
      final prefs = await SharedPreferences.getInstance();
      final manager = HgDownloadManager(_ResumeApi(), prefs);
      addTearDown(manager.dispose);

      expect(await manager.localPlaylist(20001, 1), isNull);
    },
  );

  test('downloaded direct videos are playable without HLS parsing', () async {
    final root = await Directory('.tmp').create(recursive: true);
    final directory = await root.createTemp('download-direct-video-');
    final video = File('${directory.path}/video.mp4');
    await video.writeAsBytes(<int>[0, 1, 2, 3]);
    addTearDown(() => directory.delete(recursive: true));
    final task = HgDownloadTask(
      videoId: 20002,
      title: '直链缓存测试',
      cover: '',
      totalEpisodes: 1,
      state: '已缓存',
      episodes: {
        1: HgDownloadedEpisode(
          number: 1,
          directory: directory.path,
          manifestPath: video.path,
          bytes: 4,
          updatedAt: '',
        ),
      },
    );
    SharedPreferences.setMockInitialValues({
      'guomu.downloads.v1': jsonEncode([task.toJson()]),
    });
    final prefs = await SharedPreferences.getInstance();
    final manager = HgDownloadManager(_ResumeApi(), prefs);
    addTearDown(manager.dispose);

    expect(await manager.localPlaylist(20002, 1), video.path);
  });
}
