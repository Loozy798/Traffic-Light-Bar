import AppKit
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem?
    let monitor = SystemMonitor()
    private var cancellables = Set<AnyCancellable>()
    private var popover: NSPopover?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 关闭所有可能创建的窗口
        NSApp.windows.forEach { $0.close() }

        // 配置状态栏
        setupStatusBar()

        // 监听系统负载变化，更新图标
        monitor.$stats
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stats in
                self?.updateTrafficLightIcon(stats: stats)
            }
            .store(in: &cancellables)

        // 立即更新一次图标
        updateTrafficLightIcon(stats: monitor.stats)

        // 创建 Popover
        setupPopover()

        // ✅ 监听睡眠唤醒，修复唤醒后菜单栏失效 bug
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    // MARK: - 状态栏配置（单独方法，唤醒后可重新调用）

    private func setupStatusBar() {
        if statusBarItem == nil {
            statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        if let button = statusBarItem?.button {
            button.target = self
            button.action = #selector(handleStatusBarClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    // MARK: - Popover 配置

    private func setupPopover() {
        let p = NSPopover()
        p.contentSize = NSSize(width: 300, height: 420)
        p.behavior = .transient
        p.animates = true
        let contentView = ContentView(monitor: monitor)
        p.contentViewController = NSHostingController<ContentView>(rootView: contentView)
        self.popover = p
    }

    // MARK: - 睡眠唤醒处理（核心 bug 修复）

    @objc private func handleWake() {
        // 关闭可能残留的 popover
        popover?.performClose(nil)
        removeEventMonitor()

        // 重新绑定按钮 target/action（睡眠后可能丢失）
        setupStatusBar()

        // 立即刷新图标
        updateTrafficLightIcon(stats: monitor.stats)
    }

    // MARK: - 更新图标（单个彩色大灯）

    private func updateTrafficLightIcon(stats: SystemStats) {
        let cpuLoad    = stats.cpuUsage
        let memoryLoad = stats.memoryTotal > 0
            ? (Double(stats.memoryUsed) / Double(stats.memoryTotal)) * 100 : 0
        let diskLoad   = stats.diskTotal > 0
            ? (Double(stats.diskUsed)   / Double(stats.diskTotal))   * 100 : 0

        let combinedLoad = cpuLoad * 0.4 + memoryLoad * 0.35 + diskLoad * 0.25

        let level: TrafficLightIconView.LoadLevel
        switch combinedLoad {
        case ..<30:   level = .low
        case 30..<70: level = .medium
        default:      level = .high
        }

        if let icon = renderIcon(level: level) {
            statusBarItem?.button?.image = icon
        }
    }

    /// 用 NSHostingView 正确渲染 SwiftUI 单灯为 NSImage
    private func renderIcon(level: TrafficLightIconView.LoadLevel) -> NSImage? {
        let size = NSSize(width: 18, height: 18)
        let iconView = TrafficLightIconView(loadLevel: level)
        let hosting = NSHostingView(rootView: iconView)
        hosting.frame = NSRect(origin: .zero, size: size)

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        image.isTemplate = false
        return image
    }

    // MARK: - 状态栏点击处理

    @objc private func handleStatusBarClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.type == .leftMouseUp {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        guard let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
            removeEventMonitor()
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            addEventMonitor()
        }
    }

    private func addEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.popover?.performClose(nil)
            self?.removeEventMonitor()
        }
    }

    private func removeEventMonitor() {
        if let m = eventMonitor {
            NSEvent.removeMonitor(m)
            eventMonitor = nil
        }
    }

    // MARK: - 生命周期

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - 开机自启

    @objc func toggleLaunchAtStartup() {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let plistPath = (
            "~/Library/LaunchAgents/\(bundleID).plist" as NSString
        ).expandingTildeInPath

        if FileManager.default.fileExists(atPath: plistPath) {
            try? FileManager.default.removeItem(atPath: plistPath)
        } else {
            guard let execPath = Bundle.main.executablePath else { return }
            let plistContent = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>\(bundleID)</string>
    <key>ProgramArguments</key>
    <array>
        <string>\(execPath)</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
"""
            try? plistContent.write(toFile: plistPath, atomically: true, encoding: .utf8)
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}
