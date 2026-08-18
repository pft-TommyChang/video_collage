import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private let startupChannelName = "video_collage/startup"
  private let startupBackgroundColor = NSColor(
    srgbRed: 0xF4 / 255.0,
    green: 0xE7 / 255.0,
    blue: 0xD5 / 255.0,
    alpha: 1
  )
  private let initialContentSize = NSSize(width: 1080, height: 840)
  private let minimumContentSize = NSSize(width: 800, height: 600)
  private let savedContentWidthKey = "video_collage.window.contentWidth"
  private let savedContentHeightKey = "video_collage.window.contentHeight"
  private weak var startupView: NSView?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // FlutterView is black until its first frame. Match the app palette behind
    // the native startup view for a seamless transition into Flutter.
    self.backgroundColor = startupBackgroundColor
    flutterViewController.backgroundColor = startupBackgroundColor
    self.contentViewController = flutterViewController
    installStartupView(over: flutterViewController.view)
    self.contentMinSize = minimumContentSize
    self.delegate = self
    self.setContentSize(restoredContentSize())

    RegisterGeneratedPlugins(registry: flutterViewController)
    let startupChannel = FlutterMethodChannel(
      name: startupChannelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    startupChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "dismiss" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.dismissStartupView()
      result(nil)
    }
    self.title = "Perfect Collage"

    super.awakeFromNib()
  }

  func windowDidResize(_ notification: Notification) {
    saveContentSize()
  }

  private func installStartupView(over flutterView: NSView) {
    let startupView = NSView(frame: flutterView.bounds)
    startupView.autoresizingMask = [.width, .height]
    startupView.wantsLayer = true
    startupView.layer?.backgroundColor = startupBackgroundColor.cgColor

    let iconView = NSImageView()
    iconView.image = NSApplication.shared.applicationIconImage
    iconView.imageScaling = .scaleProportionallyUpOrDown
    iconView.translatesAutoresizingMaskIntoConstraints = false

    let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? "Perfect Collage"
    let appNameLabel = NSTextField(labelWithString: appName)
    appNameLabel.font = .systemFont(ofSize: 36, weight: .semibold)
    appNameLabel.textColor = NSColor(
      srgbRed: 0x17 / 255.0,
      green: 0x1A / 255.0,
      blue: 0x21 / 255.0,
      alpha: 1
    )
    appNameLabel.alignment = .center

    let contentStack = NSStackView(views: [iconView, appNameLabel])
    contentStack.orientation = .horizontal
    contentStack.alignment = .centerY
    contentStack.spacing = 20
    contentStack.translatesAutoresizingMaskIntoConstraints = false
    startupView.addSubview(contentStack)

    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: 96),
      iconView.heightAnchor.constraint(equalToConstant: 96),
      contentStack.centerXAnchor.constraint(equalTo: startupView.centerXAnchor),
      contentStack.centerYAnchor.constraint(equalTo: startupView.centerYAnchor),
    ])

    flutterView.addSubview(startupView)
    self.startupView = startupView
  }

  private func dismissStartupView() {
    guard let startupView else {
      return
    }
    self.startupView = nil

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.12
      startupView.animator().alphaValue = 0
    } completionHandler: {
      startupView.removeFromSuperview()
    }
  }

  private func restoredContentSize() -> NSSize {
    let defaults = UserDefaults.standard
    let savedWidth = defaults.double(forKey: savedContentWidthKey)
    let savedHeight = defaults.double(forKey: savedContentHeightKey)

    guard savedWidth > 0, savedHeight > 0 else {
      return initialContentSize
    }

    return NSSize(
      width: max(savedWidth, minimumContentSize.width),
      height: max(savedHeight, minimumContentSize.height)
    )
  }

  private func saveContentSize() {
    let contentSize = self.contentView?.frame.size
      ?? self.contentRect(forFrameRect: self.frame).size
    let defaults = UserDefaults.standard
    defaults.set(max(contentSize.width, minimumContentSize.width), forKey: savedContentWidthKey)
    defaults.set(max(contentSize.height, minimumContentSize.height), forKey: savedContentHeightKey)
  }
}
