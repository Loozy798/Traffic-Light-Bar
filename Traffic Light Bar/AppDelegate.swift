import AppKit
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem?
    let monitor       = SystemMonitor()
    let energyMonitor = EnergyMonitor()
    let preferences   = AppPreferences.shared

    private var cancellables    = Set<AnyCancellable>()
    private var popover:         NSPopover?
    private var eventMonitor:    Any?
    private var dashboardWindow: NSWindow?

    // MARK: - 生命周期

    func applicationWillFinishLaunching(_ notification: Notification) {
        // ✅ 此处 NSApp 已由系统初始化，可安全调用
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 用 orderOut 而非 close，避免触发 windowShouldClose 等回调
        DispatchQueue.main.async {
            NSApp.windows
                .filter { $0 !== self.dashboardWindow }
                .forEach { $0.orderOut(nil) }
        }

        setupStatusBar()
        setupPopover()

        monitor.$stats
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stats in
                self?.updateTrafficLightIcon(stats: stats)
                self?.energyMonitor.threshold = self?.preferences.energyThreshold ?? 20
            }
            .store(in: &cancellables)

        updateTrafficLightIcon(stats: monitor.stats)

        // 睡眠唤醒修复
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - 状态栏

    private func setupStatusBar() {
        if statusBarItem == nil {
            statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        guard let button = statusBarItem?.button else { return }
        button.target = self
        button.action = #selector(handleStatusBarClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    // MARK: - Popover

    private func setupPopover() {
        let p = NSPopover()
        p.contentSize = NSSize(width: 300, height: 440)
        p.behavior = .transient
        p.animates = true
        let view = ContentView(
            monitor: monitor,
            energyMonitor: energyMonitor,
            preferences: preferences,
            onOpenDashboard: { [weak self] in
                self?.popover?.performClose(nil)
                self?.removeEventMonitor()
                self?.showDashboard()
            }
        )
        p.contentViewController = NSHostingController<ContentView>(rootView: view)
        self.popover = p
    }

    // MARK: - 点击处理

    @objc private func handleStatusBarClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let dash = NSMenuItem(title: "打开仪表盘", action: #selector(openDashboard), keyEquivalent: "d")
        dash.image = NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: nil)
        dash.target = self
        menu.addItem(dash)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Traffic Light Bar", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        if let button = statusBarItem?.button {
            menu.popUp(positioning: nil,
                       at: NSPoint(x: 0, y: button.bounds.height), in: button)
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
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover?.performClose(nil)
            self?.removeEventMonitor()
        }
    }

    private func removeEventMonitor() {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    // MARK: - 仪表盘窗口（#5 打开时显示 Dock / #6 显示 App 名称菜单）

    @objc private func openDashboard() { showDashboard() }

    func showDashboard() {
        if let w = dashboardWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // ✅ 切换为 regular → Dock 显示图标 + 菜单栏显示 "Traffic Light Bar" 及 About
        NSApp.setActivationPolicy(.regular)

        let view = DashboardView(
            monitor: monitor,
            energyMonitor: energyMonitor,
            preferences: preferences
        )
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title       = "Traffic Light Bar — 仪表盘"
        w.contentView = NSHostingView(rootView: view)
        w.setFrameAutosaveName("TLBDashboard")
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow = w

        // 窗口关闭时回到 accessory 模式（隐藏 Dock 图标）
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: w,
            queue: .main
        ) { [weak self] _ in
            self?.dashboardWindow = nil
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - 图标更新（#2 仅 CPU + 内存）

    private func updateTrafficLightIcon(stats: SystemStats) {
        let cpu = stats.cpuUsage
        let mem = stats.memoryTotal > 0
            ? Double(stats.memoryUsed) / Double(stats.memoryTotal) * 100 : 0
        // ✅ 压力值 = CPU 60% + 内存 40%
        let load     = cpu * 0.6 + mem * 0.4
        let loadRatio = min(load / 100, 1.0)

        if let icon = renderIcon(loadRatio: loadRatio) {
            statusBarItem?.button?.image = icon
        }
    }

    private func renderIcon(loadRatio: Double) -> NSImage? {
        let size    = NSSize(width: 18, height: 18)
        let hosting = NSHostingView(rootView: TrafficLightIconView(loadRatio: loadRatio))
        hosting.frame = NSRect(origin: .zero, size: size)
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let img = NSImage(size: size)
        img.addRepresentation(rep)
        img.isTemplate = false
        return img
    }

    // MARK: - 睡眠唤醒

    @objc private func handleWake() {
        popover?.performClose(nil)
        removeEventMonitor()
        setupStatusBar()
        updateTrafficLightIcon(stats: monitor.stats)
    }

    // MARK: - 操作

    @objc func quitApp() { NSApp.terminate(nil) }

    @objc func toggleLaunchAtStartup() {
        let id   = Bundle.main.bundleIdentifier ?? ""
        let path = ("~/Library/LaunchAgents/\(id).plist" as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        } else {
            guard let exec = Bundle.main.executablePath else { return }
            let plist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>\(id)</string>
<key>ProgramArguments</key><array><string>\(exec)</string></array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><false/>
</dict></plist>
"""
            try? plist.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
