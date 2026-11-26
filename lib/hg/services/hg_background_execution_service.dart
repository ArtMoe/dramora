import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps an in-app download alive when iOS moves the app to the background.
///
/// iOS does not expose a general-purpose "run Dart forever" background API.
/// A short background task plus the audio background mode lets the existing
/// HLS downloader finish while the app is still alive. If the user force-quits
/// the app, iOS stops the process and the download is resumed on next launch.
abstract final class HgBackgroundExecutionService {
  static const _channel = MethodChannel(
    'com.guomu.huangguo/downloadbackground',
  );
  static bool _active = false;

  static Future<void> setDownloadActive(bool active) async {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.iOS ||
        _active == active) {
      return;
    }
    _active = active;
    try {
      await _channel.invokeMethod<void>('setActive', active);
    } catch (error) {
      debugPrint('Guomu download background mode skipped: $error');
    }
  }
}
