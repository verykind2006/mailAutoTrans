import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // 仿 Gmail 的左侧栏 + 列表布局需要宽一点：默认 1320×860，最小 1000×640，居中
    self.setContentSize(NSSize(width: 1320, height: 860))
    self.contentMinSize = NSSize(width: 1000, height: 640)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
