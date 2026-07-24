import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private let initialContentSize = NSSize(width: 1080, height: 840)
  private let minimumContentSize = NSSize(width: 800, height: 600)
  private let savedContentWidthKey = "video_collage.window.contentWidth"
  private let savedContentHeightKey = "video_collage.window.contentHeight"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.contentMinSize = minimumContentSize
    self.delegate = self
    self.setContentSize(restoredContentSize())

    RegisterGeneratedPlugins(registry: flutterViewController)
    self.title = "Video Collage Studio"

    super.awakeFromNib()
  }

  func windowDidResize(_ notification: Notification) {
    saveContentSize()
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
