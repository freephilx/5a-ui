import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    let availableSize = (screen ?? NSScreen.main)?.visibleFrame.size
      ?? NSSize(width: 1280, height: 900)
    self.setContentSize(NSSize(
      width: min(1200, availableSize.width - 48),
      height: min(800, availableSize.height - 80)
    ))
    self.contentMinSize = NSSize(width: 380, height: 400)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
