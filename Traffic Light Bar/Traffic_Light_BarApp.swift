import SwiftUI
import AppKit

@main
struct Traffic_Light_BarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // ⚠️ 不要在 init() 里访问 NSApp！
    // SwiftUI App.init() 阶段 NSApp (NSApplication!) 尚未被系统初始化，
    // 强制访问会导致 "Unexpectedly found nil while implicitly unwrapping" 崩溃。
    // 激活策略统一在 AppDelegate.applicationWillFinishLaunching 里设置。

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
