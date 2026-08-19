import Cocoa
import AVFoundation
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private let mediaProbeChannelName = "video_collage/media_probe"
  private let mediaDialogChannelName = "video_collage/media_dialogs"
  private let mediaOpenChannelName = "video_collage/media_open"
  private var mediaOpenChannel: FlutterMethodChannel?
  private var pendingOpenFilePaths: [String] = []

  override func applicationDidFinishLaunching(_ notification: Notification) {
    guard let flutterViewController = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      super.applicationDidFinishLaunching(notification)
      return
    }

    let channel = FlutterMethodChannel(
      name: mediaProbeChannelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    let dialogChannel = FlutterMethodChannel(
      name: mediaDialogChannelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    let openChannel = FlutterMethodChannel(
      name: mediaOpenChannelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    mediaOpenChannel = openChannel

    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "probeVideoMetadata" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let path = arguments["path"] as? String
      else {
        result(
          FlutterError(
            code: "invalid-arguments",
            message: "Expected a file path.",
            details: nil
          )
        )
        return
      }

      self?.probeVideoMetadata(path: path, result: result)
    }

    dialogChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "pickMediaWithMetadata" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.pickMediaWithMetadata(result: result)
    }

    openChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "consumePendingMediaFiles" else {
        result(FlutterMethodNotImplemented)
        return
      }

      let paths = self?.pendingOpenFilePaths ?? []
      self?.pendingOpenFilePaths.removeAll()
      result(paths)
    }

    super.applicationDidFinishLaunching(notification)
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    queueOpenedMediaFiles(filenames, application: sender)
    sender.reply(toOpenOrPrint: .success)
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    queueOpenedMediaFiles(
      urls.filter(\.isFileURL).map(\.path),
      application: application
    )
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  private func queueOpenedMediaFiles(_ paths: [String], application: NSApplication) {
    for path in paths where !pendingOpenFilePaths.contains(path) {
      pendingOpenFilePaths.append(path)
    }

    guard !paths.isEmpty else {
      return
    }
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    application.activate(ignoringOtherApps: true)
    mediaOpenChannel?.invokeMethod("mediaFilesOpened", arguments: nil)
  }

  private func probeVideoMetadata(path: String, result: @escaping FlutterResult) {
    let url = URL(fileURLWithPath: path)
    let accessed = url.startAccessingSecurityScopedResource()
    defer {
      if accessed {
        url.stopAccessingSecurityScopedResource()
      }
    }

    let asset = AVURLAsset(url: url)
    guard let videoTrack = asset.tracks(withMediaType: .video).first else {
      result(
        FlutterError(
          code: "no-video-track",
          message: "No video track found.",
          details: path
        )
      )
      return
    }

    let transformedSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
    let width = Int(abs(transformedSize.width).rounded())
    let height = Int(abs(transformedSize.height).rounded())
    let durationSeconds = CMTimeGetSeconds(asset.duration)
    let hasAudio = !asset.tracks(withMediaType: .audio).isEmpty
    let frameRate = Double(videoTrack.nominalFrameRate)

    result([
      "width": width,
      "height": height,
      "durationSeconds": durationSeconds.isFinite ? durationSeconds : 0,
      "hasAudio": hasAudio,
      "frameRate": frameRate.isFinite ? frameRate : 0,
    ])
  }

  private func pickMediaWithMetadata(result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.prompt = "Add Media"
    panel.allowedFileTypes = [
      "mp4", "mov", "m4v", "avi", "mkv", "webm",
      "jpg", "jpeg", "png", "webp", "heic", "heif"
    ]

    guard panel.runModal() == .OK else {
      result([[String: Any]]())
      return
    }

    // Return selected paths immediately. Preview initialization and metadata
    // probing happen asynchronously in Flutter so one slow file cannot hold up
    // every placeholder and the first visible frame.
    result(panel.urls.map { ["path": $0.path] })
  }

}
