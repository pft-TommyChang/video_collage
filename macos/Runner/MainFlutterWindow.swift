import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let initialContentSize = NSSize(width: 1080, height: 840)
  private let minimumContentSize = NSSize(width: 800, height: 600)

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setContentSize(initialContentSize)
    self.contentMinSize = minimumContentSize

    RegisterGeneratedPlugins(registry: flutterViewController)
    self.title = "Video Collage Studio"

    super.awakeFromNib()
  }
}
