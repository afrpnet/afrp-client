import Cocoa
import FlutterMacOS
import Metal

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    // Flutter 的 macOS 渲染完全依赖 Metal（Impeller / Skia 都需要）。
    // 虚拟机、黑苹果或老旧显卡没有 Metal 设备时会只剩一个空白窗口，
    // 这里直接给出可读的原因，避免让用户面对白屏无从判断。
    let device = MTLCreateSystemDefaultDevice()
    NSLog("AFRP OIDC Client: Metal device = %@", device?.name ?? "nil")
    if device == nil {
      let alert = NSAlert()
      alert.alertStyle = .critical
      alert.messageText = "无法显示界面：系统没有 Metal 图形设备"
      alert.informativeText = "当前 macOS 没有可用的 Metal 设备（OpenCore/虚拟机或老旧显卡常见），Flutter 界面无法渲染。\n\n请在有 Metal 支持的 Mac 上运行，或为虚拟机开启 GPU/Metal 加速。"
      alert.addButton(withTitle: "退出")
      alert.runModal()
      NSApp.terminate(nil)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
