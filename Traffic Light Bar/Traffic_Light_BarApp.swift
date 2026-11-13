import SwiftUI

@main
struct Traffic_Light_BarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        Settings {
            PreferencesView(preferences: appDelegate.preferences, loginItem: appDelegate.loginItem)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("偏好设置…") { appDelegate.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("显示状态面板") { appDelegate.showStatusPanel() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("打开仪表盘") { appDelegate.showDashboard() }
                    .keyboardShortcut("d", modifiers: .command)
            }
        }
    }
}
