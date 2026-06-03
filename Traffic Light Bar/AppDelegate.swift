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

        // 睡眠 / 唤醒修复
        let wsc = NSWorkspace.shared.notificationCenter
        wsc.addObserver(self, selector: #selector(handleSleep),
                        name: NSWorkspace.willSleepNotification, object: nil)
        wsc.addObserver(self, selector: #selector(handleWake),
                        name: NSWorkspace.didWakeNotification, object: nil)
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

        statusBarItem?.button?.image = renderIcon(loadRatio: loadRatio)
    }

    /// ✅ 纯 CoreGraphics 绘制，比 NSHostingView 快 10-20 倍
    /// 彻底避免每次更新都触发 SwiftUI 完整渲染管线
    private func renderIcon(loadRatio: Double) -> NSImage {
        let size  = NSSize(width: 18, height: 18)
        let hue   = (1.0 - min(max(loadRatio, 0), 1.0)) * 0.35
        let color = NSColor(hue: hue, saturation: 0.88, brightness: 0.88, alpha: 1.0)

        let img = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let cx: CGFloat = rect.midX
            let cy: CGFloat = rect.midY
            let cg  = color.cgColor
            let spc = CGColorSpaceCreateDeviceRGB()

            // 外发光（radial gradient: 不透明色 → 透明）
            let glowCols = [
                cg.copy(alpha: 0.40)!,
                cg.copy(alpha: 0.10)!,
                cg.copy(alpha: 0.00)!
            ] as CFArray
            let glowLocs: [CGFloat] = [0, 0.5, 1.0]
            if let g = CGGradient(colorsSpace: spc, colors: glowCols, locations: glowLocs) {
                ctx.drawRadialGradient(
                    g,
                    startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                    endCenter:   CGPoint(x: cx, y: cy), endRadius:   8.5,
                    options: []
                )
            }

            // 主灯体（带白色高光的 radial gradient）
            let dotCols = [
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.75),
                cg
            ] as CFArray
            let dotLocs: [CGFloat] = [0, 1.0]
            if let dg = CGGradient(colorsSpace: spc, colors: dotCols, locations: dotLocs) {
                ctx.drawRadialGradient(
                    dg,
                    startCenter: CGPoint(x: cx - 0.8, y: cy + 0.8), startRadius: 0,
                    endCenter:   CGPoint(x: cx,       y: cy),        endRadius:   4.5,
                    options: []
                )
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    // MARK: - 睡眠唤醒

    @objc private func handleSleep() {
        // 主动关闭 popover 和停止监控，防止睡眠期间 Task 堆积
        popover?.performClose(nil)
        removeEventMonitor()
    }

    @objc private func handleWake() {
        // 1) 立即关闭可能残留的 popover（防止悬停触发渲染卡死）
        popover?.performClose(nil)
        removeEventMonitor()

        // 2) 重新启动监控 Task（睡眠可能导致 Task.sleep 永远不醒、
        //    或 Mach 端口调用阻塞整个协作线程池）
        monitor.restart()
        energyMonitor.startMonitoring()

        // 3) 重建 Popover（旧的 NSHostingController 可能持有失效的渲染状态）
        setupPopover()

        // 4) 重建状态栏图标
        setupStatusBar()

        // 5) 延迟一帧刷新图标，等待第一次数据采集完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.updateTrafficLightIcon(stats: self.monitor.stats)
        }
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
