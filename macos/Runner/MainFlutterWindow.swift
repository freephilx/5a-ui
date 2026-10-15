import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    flutterViewController.backgroundColor = .clear
    let container = NSViewController()
    container.view = NSView()
    container.addChild(flutterViewController)
    let sidebarMaterial = NSVisualEffectView()
    sidebarMaterial.material = .sidebar
    sidebarMaterial.blendingMode = .behindWindow
    sidebarMaterial.state = .followsWindowActiveState
    for view in [sidebarMaterial, flutterViewController.view] {
      view.translatesAutoresizingMaskIntoConstraints = false
      container.view.addSubview(view)
      NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
        view.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
        view.topAnchor.constraint(equalTo: container.view.topAnchor),
        view.bottomAnchor.constraint(equalTo: container.view.bottomAnchor),
      ])
    }
    self.contentViewController = container
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)

    let channel = FlutterMethodChannel(
      name: "app.fivea/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
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
