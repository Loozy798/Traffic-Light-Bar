import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 配置状态栏图标
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusBarItem?.button?.image = NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "Traffic Monitor")
        statusBarItem?.button?.action = #selector(togglePopover)
        
        // 配置弹出面板
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 260, height: 400)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: ContentView(monitor: SystemMonitor()))
    }

    @objc private func togglePopover() {
        guard let button = statusBarItem?.button, let popover else { return }
        popover.isShown ? popover.performClose(nil) : popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}
