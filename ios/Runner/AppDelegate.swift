import UIKit
import Flutter
import UserNotifications
import AVFoundation
import MediaPlayer
import ActivityKit
import workmanager_apple

struct GuomuActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var kind: String
    var title: String
    var subtitle: String
    var episode: Int
    var totalEpisodes: Int
    var episodeLabel: String
    var detail: String
    var progress: Double
    var coverBase64: String
    var deepLink: String
  }

  var activityKey: String
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var deepLinkChannel: FlutterMethodChannel?
  private var liveActivityChannel: FlutterMethodChannel?
  private var nowPlayingChannel: FlutterMethodChannel?
  private var downloadBackgroundChannel: FlutterMethodChannel?
  private var pendingDeepLink: String?
  private var remoteCommandsConfigured = false
  private var activityCoverCache: [String: String] = [:]
  private var nowPlayingIsPlaying = false
  private var downloadBackgroundTask: UIBackgroundTaskIdentifier = .invalid
  private var silentDownloadPlayer: AVAudioPlayer?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.guomu.huangguo.update-check",
      earliestBeginInSeconds: NSNumber(value: 24 * 60 * 60)
    )
    UNUserNotificationCenter.current().delegate = self
    configureAudioSession()

    if let controller = window?.rootViewController as? FlutterViewController {
      configureShareChannel(controller)
      configureDeepLinkChannel(controller)
      configureNowPlayingChannel(controller)
      configureLiveActivityChannel(controller)
      configureDownloadBackgroundChannel(controller)
    }

    configureRemoteCommands()
    if let url = launchOptions?[.url] as? URL, url.scheme == "guomu" {
      pendingDeepLink = url.absoluteString
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func configureAudioSession() {
    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playback,
        mode: .moviePlayback,
        options: [.mixWithOthers, .allowAirPlay, .allowBluetoothA2DP]
      )
    } catch {
      // Audio configuration must never prevent app startup.
    }
  }

  private func configureShareChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.guomu.huangguo/share",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "share" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any]
      let title = args?["title"] as? String ?? ""
      let text = args?["text"] as? String ?? ""
      let url = args?["url"] as? String ?? ""
      let shareText = [title, text, url]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n")
      let activity = UIActivityViewController(
        activityItems: [shareText],
        applicationActivities: nil
      )
      if let popover = activity.popoverPresentationController {
        popover.sourceView = controller.view
        popover.sourceRect = CGRect(
          x: controller.view.bounds.midX,
          y: controller.view.bounds.maxY - 40,
          width: 1,
          height: 1
        )
      }
      self?.window?.rootViewController?.present(activity, animated: true) {
        result(true)
      }
    }
  }

  private func configureDeepLinkChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.guomu.huangguo/deeplink",
      binaryMessenger: controller.binaryMessenger
    )
    deepLinkChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "getInitialLink" {
        result(self?.pendingDeepLink)
        self?.pendingDeepLink = nil
        return
      }
      result(FlutterMethodNotImplemented)
    }
  }

  private func configureNowPlayingChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.guomu.huangguo/nowplaying",
      binaryMessenger: controller.binaryMessenger
    )
    nowPlayingChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "update":
        self?.updateNowPlaying(call.arguments as? [String: Any] ?? [:])
        result(nil)
      case "clear":
        self?.clearNowPlaying()
        result(nil)
      case "prepareArtwork":
        self?.prepareArtwork(call.arguments, result: result, maxSide: 512)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func configureLiveActivityChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.guomu.huangguo/liveactivity",
      binaryMessenger: controller.binaryMessenger
    )
    liveActivityChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "isAvailable":
        if #available(iOS 16.1, *) {
          result(ActivityAuthorizationInfo().areActivitiesEnabled)
        } else {
          result(false)
        }
      case "prepareArtwork":
        self?.prepareArtwork(call.arguments, result: result, maxSide: 256)
      case "showOrUpdate":
        self?.showOrUpdateActivity(call.arguments, result: result)
      case "end":
        self?.endActivities(call.arguments, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func configureDownloadBackgroundChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.guomu.huangguo/downloadbackground",
      binaryMessenger: controller.binaryMessenger
    )
    downloadBackgroundChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setActive" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let active = call.arguments as? Bool ?? false
      self?.setDownloadBackgroundActive(active)
      result(nil)
    }
  }

  private func prepareArtwork(
    _ rawArguments: Any?,
    result: @escaping FlutterResult,
    maxSide: CGFloat
  ) {
    guard let args = rawArguments as? [String: Any],
          let bytes = args["bytes"] as? FlutterStandardTypedData,
          let image = UIImage(data: bytes.data),
          image.size.width > 0,
          image.size.height > 0 else {
      result("")
      return
    }
    let key = (args["key"] as? String ?? "artwork")
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: ":", with: "-")
      .prefix(72)
    do {
      let directory = try artworkDirectory()
      let destination = directory.appendingPathComponent("artwork-\(key).jpg")
      guard let jpeg = resizedJpeg(image, maxSide: maxSide, quality: 0.82) else {
        result("")
        return
      }
      try jpeg.write(to: destination, options: .atomic)
      result(destination.path)
    } catch {
      result("")
    }
  }

  private func artworkDirectory() throws -> URL {
    let root = FileManager.default.urls(
      for: .cachesDirectory,
      in: .userDomainMask
    )[0]
    let directory = root.appendingPathComponent("GuomuArtwork", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }

  private func resizedJpeg(
    _ image: UIImage,
    maxSide: CGFloat,
    quality: CGFloat
  ) -> Data? {
    let scale = min(1, maxSide / max(image.size.width, image.size.height))
    let size = CGSize(
      width: max(1, image.size.width * scale),
      height: max(1, image.size.height * scale)
    )
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let thumbnail = UIGraphicsImageRenderer(size: size, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
    return thumbnail.jpegData(compressionQuality: quality)
  }

  private func activityCoverData(_ bytes: FlutterStandardTypedData?) -> String? {
    guard let bytes, let image = UIImage(data: bytes.data) else { return nil }
    guard let jpeg = resizedJpeg(image, maxSide: 96, quality: 0.58) else {
      return nil
    }
    return jpeg.base64EncodedString()
  }

  private func showOrUpdateActivity(
    _ rawArguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard #available(iOS 16.1, *) else {
      result(FlutterError(code: "UNSUPPORTED_IOS", message: nil, details: nil))
      return
    }
    guard let args = rawArguments as? [String: Any] else {
      result(FlutterError(code: "BAD_ARGS", message: nil, details: nil))
      return
    }
    let activityKey = args["activityKey"] as? String ?? "guomu-now-playing"
    if let coverData = activityCoverData(args["coverBytes"] as? FlutterStandardTypedData) {
      activityCoverCache[activityKey] = coverData
      UserDefaults.standard.set(coverData, forKey: "guomu.activity.cover.\(activityKey)")
    }
    Task { @MainActor in
      let activity = Activity<GuomuActivityAttributes>.activities.first {
        $0.attributes.activityKey == activityKey &&
        $0.activityState != .dismissed &&
        $0.activityState != .ended
      }
      let state = GuomuActivityAttributes.ContentState(
        kind: args["kind"] as? String ?? "playback",
        title: args["title"] as? String ?? "果幕短剧",
        subtitle: args["subtitle"] as? String ?? "黄果短剧",
        episode: (args["episode"] as? NSNumber)?.intValue ?? 0,
        totalEpisodes: (args["totalEpisodes"] as? NSNumber)?.intValue ?? 0,
        episodeLabel: args["episodeLabel"] as? String ?? "",
        detail: args["detail"] as? String ?? "",
        progress: (args["progress"] as? NSNumber)?.doubleValue ?? 0,
        coverBase64: activityCoverCache[activityKey]
          ?? UserDefaults.standard.string(forKey: "guomu.activity.cover.\(activityKey)")
          ?? "",
        deepLink: args["deepLink"] as? String ?? "guomu://"
      )
      do {
        if let activity {
          await activity.update(using: state)
        } else {
          _ = try Activity.request(
            attributes: GuomuActivityAttributes(activityKey: activityKey),
            contentState: state,
            pushType: nil
          )
        }
        result(nil)
      } catch {
        result(FlutterError(
          code: "LIVE_ACTIVITY_ERROR",
          message: error.localizedDescription,
          details: nil
        ))
      }
    }
  }

  private func endActivities(_ rawArguments: Any?, result: @escaping FlutterResult) {
    guard #available(iOS 16.1, *) else {
      result(nil)
      return
    }
    let args = rawArguments as? [String: Any]
    let activityKey = args?["activityKey"] as? String ?? ""
    Task { @MainActor in
      let activities = Activity<GuomuActivityAttributes>.activities.filter {
        activityKey.isEmpty || $0.attributes.activityKey == activityKey
      }
      for activity in activities {
        await activity.end(dismissalPolicy: .immediate)
      }
      result(nil)
    }
  }

  private func configureRemoteCommands() {
    guard !remoteCommandsConfigured else { return }
    remoteCommandsConfigured = true
    let center = MPRemoteCommandCenter.shared()
    center.playCommand.isEnabled = true
    center.pauseCommand.isEnabled = true
    center.togglePlayPauseCommand.isEnabled = true
    center.changePlaybackPositionCommand.isEnabled = true
    center.playCommand.addTarget { [weak self] _ in
      self?.nowPlayingChannel?.invokeMethod("play", arguments: nil)
      return .success
    }
    center.pauseCommand.addTarget { [weak self] _ in
      self?.nowPlayingChannel?.invokeMethod("pause", arguments: nil)
      return .success
    }
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.nowPlayingChannel?.invokeMethod("toggle", arguments: nil)
      return .success
    }
    center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let seekEvent = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      self?.nowPlayingChannel?.invokeMethod("seekTo", arguments: seekEvent.positionTime)
      return .success
    }
  }

  private func updateNowPlaying(_ args: [String: Any]) {
    let title = args["title"] as? String ?? "果幕短剧"
    let subtitle = args["subtitle"] as? String ?? "黄果短剧"
    let position = (args["positionMs"] as? NSNumber)?.doubleValue ?? 0
    let duration = (args["durationMs"] as? NSNumber)?.doubleValue ?? 0
    let speed = max((args["speed"] as? NSNumber)?.doubleValue ?? 1, 0.1)
    let isPlaying = args["isPlaying"] as? Bool ?? false
    let deepLink = args["deepLink"] as? String ?? "guomu://"
    nowPlayingIsPlaying = isPlaying

    var info: [String: Any] = [
      MPMediaItemPropertyTitle: title,
      MPMediaItemPropertyArtist: subtitle,
      MPMediaItemPropertyAlbumTitle: "果幕 · 黄果短剧",
      MPNowPlayingInfoPropertyElapsedPlaybackTime: position / 1000,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? speed : 0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: speed,
      MPNowPlayingInfoPropertyExternalContentIdentifier: deepLink,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
    ]
    if duration > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = duration / 1000
    }
    if let artworkPath = args["artworkPath"] as? String,
       !artworkPath.isEmpty,
       let image = UIImage(contentsOfFile: artworkPath) {
      info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
        boundsSize: image.size
      ) { _ in image }
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    UIApplication.shared.beginReceivingRemoteControlEvents()
    do {
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      // The system keeps the current audio session when activation fails.
    }
  }

  private func clearNowPlaying() {
    nowPlayingIsPlaying = false
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    MPNowPlayingInfoCenter.default().playbackState = .stopped
    UIApplication.shared.endReceivingRemoteControlEvents()
    if silentDownloadPlayer == nil {
      do {
        try AVAudioSession.sharedInstance().setActive(
          false,
          options: .notifyOthersOnDeactivation
        )
      } catch {
        // Other audio is restored by the system.
      }
    }
  }

  private func setDownloadBackgroundActive(_ active: Bool) {
    if active {
      startDownloadBackgroundWork()
    } else {
      stopDownloadBackgroundWork()
    }
  }

  private func startDownloadBackgroundWork() {
    configureAudioSession()
    do {
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      // The background task below still provides the system-allowed runtime.
    }
    if downloadBackgroundTask == .invalid {
      downloadBackgroundTask = UIApplication.shared.beginBackgroundTask(
        withName: "GuomuDownload"
      ) { [weak self] in
        self?.stopDownloadBackgroundWork()
      }
    }
    guard silentDownloadPlayer == nil else { return }
    do {
      let player = try AVAudioPlayer(data: silentWavData())
      player.numberOfLoops = -1
      player.volume = 0
      player.prepareToPlay()
      player.play()
      silentDownloadPlayer = player
    } catch {
      silentDownloadPlayer = nil
    }
  }

  private func stopDownloadBackgroundWork() {
    silentDownloadPlayer?.stop()
    silentDownloadPlayer = nil
    if downloadBackgroundTask != .invalid {
      UIApplication.shared.endBackgroundTask(downloadBackgroundTask)
      downloadBackgroundTask = .invalid
    }
    if !nowPlayingIsPlaying {
      do {
        try AVAudioSession.sharedInstance().setActive(
          false,
          options: .notifyOthersOnDeactivation
        )
      } catch {
        // Another audio owner may still need the session.
      }
    }
  }

  private func silentWavData() -> Data {
    let sampleRate: UInt32 = 8_000
    let bitsPerSample: UInt16 = 16
    let channels: UInt16 = 1
    let seconds: UInt32 = 1
    let bytesPerSample = UInt32(bitsPerSample / 8)
    let dataSize = sampleRate * seconds * UInt32(channels) * bytesPerSample
    let byteRate = sampleRate * UInt32(channels) * bytesPerSample
    let blockAlign = channels * (bitsPerSample / 8)
    var data = Data("RIFF".utf8)
    appendLE(UInt32(36) + dataSize, to: &data)
    data.append(Data("WAVE".utf8))
    data.append(Data("fmt ".utf8))
    appendLE(UInt32(16), to: &data)
    appendLE(UInt16(1), to: &data)
    appendLE(channels, to: &data)
    appendLE(sampleRate, to: &data)
    appendLE(byteRate, to: &data)
    appendLE(blockAlign, to: &data)
    appendLE(bitsPerSample, to: &data)
    data.append(Data("data".utf8))
    appendLE(dataSize, to: &data)
    data.append(Data(repeating: 0, count: Int(dataSize)))
    return data
  }

  private func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { bytes in
      data.append(contentsOf: bytes.map { $0 })
    }
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme == "guomu" {
      pendingDeepLink = url.absoluteString
      deepLinkChannel?.invokeMethod("link", arguments: url.absoluteString)
      return true
    }
    return super.application(app, open: url, options: options)
  }
}
