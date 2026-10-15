import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    flutterViewController.backgroundColor = .clear
    self.contentViewController = flutterViewController
    let flutterView = flutterViewController.view
    let sidebarMaterial = NSVisualEffectView()
    sidebarMaterial.material = .sidebar
    sidebarMaterial.blendingMode = .behindWindow
    sidebarMaterial.state = .followsWindowActiveState
    // Keep Flutter as the window's content controller so AppKit dispatches
    // input through its normal responder chain. The material only paints behind it.
    sidebarMaterial.translatesAutoresizingMaskIntoConstraints = false
    flutterView.addSubview(sidebarMaterial, positioned: .below, relativeTo: nil)
    NSLayoutConstraint.activate([
      sidebarMaterial.leadingAnchor.constraint(equalTo: flutterView.leadingAnchor),
      sidebarMaterial.trailingAnchor.constraint(equalTo: flutterView.trailingAnchor),
      sidebarMaterial.topAnchor.constraint(equalTo: flutterView.topAnchor),
      sidebarMaterial.bottomAnchor.constraint(equalTo: flutterView.bottomAnchor),
    ])
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)

    let channel = FlutterMethodChannel(
      name: "app.fivea/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "userHomeDirectory" {
        if let path = getpwuid(getuid())?.pointee.pw_dir {
          result(String(cString: path))
        } else {
          result(FlutterError(code: "HOME_DIRECTORY", message: "Unable to resolve user home", details: nil))
        }
        return
      }
      guard call.method == "setAppearance", let brightness = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.appearance = brightness == "system"
        ? nil
        : NSAppearance(named: brightness == "dark" ? .darkAqua : .aqua)
      result(nil)
    }
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
