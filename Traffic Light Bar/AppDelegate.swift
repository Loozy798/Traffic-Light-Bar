import AppKit
import SwiftUI
import Combine
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    let monitor = SystemMonitor()
    let energyMonitor = EnergyMonitor()
    let preferences = AppPreferences.shared
    let loginItem = LoginItemManager()
    private var statusBarItem: NSStatusItem?
    private var popover: NSPopover?
    private var dashboardWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isSleeping = false
    private var iconLevel: ResourceLevel?
    private let logger = Logger(subsystem: "Booster-Studio.Traffic-Light-Bar", category: "Windowing")

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupPopover()
        monitor.$stats.sink { [weak self] stats in self?.updateStatus(stats) }.store(in: &cancellables)
        monitor.$isPaused.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateStatus(self.monitor.stats)
                self.updateProcessSampling()
            }
        }.store(in: &cancellables)
        preferences.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { [weak self] in self?.applyPreferences() }
        }.store(in: &cancellables)
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleSleep() }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWake() }
        })
        applyPreferences()
        if ProcessInfo.processInfo.arguments.contains("--dashboard") { showDashboard() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard()
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        monitor.sleep()
        energyMonitor.setActive(false)
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
    func applicationDidBecomeActive(_ notification: Notification) { loginItem.refresh() }

    private func applyPreferences() {
        monitor.setInterval(preferences.refreshInterval)
        energyMonitor.threshold = preferences.energyThreshold
        updateStatus(monitor.stats)
        updateProcessSampling()
    }
    private func updateProcessSampling() {
        let visible = popover?.isShown == true || (dashboardWindow?.isVisible == true && dashboardWindow?.isMiniaturized == false)
        energyMonitor.setActive(!isSleeping && !monitor.isPaused && (visible || preferences.showEnergyWarning))
    }

    private func setupStatusBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusBarItem?.button else { return }
        button.target = self
        button.action = #selector(statusBarClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        button.imagePosition = .imageLeading
    }
    private func setupPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 360, height: 620)
        let content = ContentView(monitor: monitor, energyMonitor: energyMonitor, preferences: preferences,
                                  onOpenDashboard: { [weak self] in self?.showDashboard() },
                                  onOpenSettings: { [weak self] in self?.showSettings() })
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        self.popover = popover
    }
    @objc private func statusBarClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp { showContextMenu(); return }
        guard let popover else { return }
        if popover.isShown { popover.performClose(sender) }
        else { showStatusPanel() }
    }
    func popoverDidClose(_ notification: Notification) {
        logger.info("Status panel closed")
        updateProcessSampling()
    }

    @objc func showStatusPanel() {
        NSApp.activate(ignoringOtherApps: true)
        // A menu command must finish tracking before presenting a transient popover.
        DispatchQueue.main.async { [weak self] in
            guard let self, let button = self.statusBarItem?.button, let popover = self.popover else { return }
            if !popover.isShown { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
            popover.contentViewController?.view.window?.makeKey()
            self.logger.info("Status panel opened: \(popover.isShown)")
            self.updateProcessSampling()
        }
    }

    private func showContextMenu() {
        popover?.performClose(nil)
        let menu = NSMenu()
        addMenuItem("打开仪表盘", action: #selector(showDashboard), key: "d", to: menu)
        addMenuItem("偏好设置…", action: #selector(showSettings), key: ",", to: menu)
        menu.addItem(.separator())
        addMenuItem(monitor.isPaused ? "恢复监控" : "暂停监控", action: #selector(togglePause), to: menu)
        addMenuItem("打开活动监视器", action: #selector(openActivityMonitor), to: menu)
        menu.addItem(.separator())
        addMenuItem("退出 Traffic Light Bar", action: #selector(quitApp), key: "q", to: menu)
        if let button = statusBarItem?.button { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button) }
    }
    private func addMenuItem(_ title: String, action: Selector, key: String = "", to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc func showDashboard() {
        popover?.performClose(nil)
        if dashboardWindow == nil {
            let content = DashboardView(monitor: monitor, energyMonitor: energyMonitor, preferences: preferences,
                                        onOpenSettings: { [weak self] in self?.showSettings() })
            let window = makeWindow(title: "Traffic Light Bar", size: NSSize(width: 1000, height: 760), content: content)
            window.minSize = NSSize(width: 840, height: 620)
            window.setFrameAutosaveName("TLBDashboardV2")
            dashboardWindow = window
        }
        present(dashboardWindow)
        logger.info("Dashboard opened")
        updateProcessSampling()
    }
    @objc func showSettings() {
        popover?.performClose(nil)
        if settingsWindow == nil {
            let content = PreferencesView(preferences: preferences, loginItem: loginItem)
            let window = makeWindow(title: "偏好设置", size: NSSize(width: 510, height: 650), content: content)
            window.styleMask.remove(.resizable)
            settingsWindow = window
        }
        loginItem.refresh()
        present(settingsWindow)
        logger.info("Settings opened")
    }
    private func makeWindow<Content: View>(title: String, size: NSSize, content: Content) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.contentView = NSHostingView(rootView: content)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }
    private func present(_ window: NSWindow?) {
        NSApp.setActivationPolicy(.regular)
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let hasWindow = self.dashboardWindow?.isVisible == true || self.settingsWindow?.isVisible == true
            if !hasWindow { NSApp.setActivationPolicy(.accessory) }
            self.updateProcessSampling()
        }
    }
    func windowDidMiniaturize(_ notification: Notification) { updateProcessSampling() }
    func windowDidDeminiaturize(_ notification: Notification) { updateProcessSampling() }

    private func updateStatus(_ stats: SystemStats) {
        guard let button = statusBarItem?.button else { return }
        let level: ResourceLevel = monitor.isPaused ? .unknown : stats.level
        if iconLevel != level {
            button.image = statusIcon(level)
            iconLevel = level
        }
        switch preferences.statusDisplay {
        case .light: button.title = ""
        case .cpu: button.title = " CPU \(MetricFormat.percent(stats.cpuUsage))"
        case .memory: button.title = " MEM \(stats.memoryTotal > 0 ? MetricFormat.percent(stats.memoryRatio * 100) : "—")"
        case .network: button.title = " ↓\(MetricFormat.speed(stats.networkDownload)) ↑\(MetricFormat.speed(stats.networkUpload))"
        }
        if monitor.isPaused { button.title = " Ⅱ" }
        let description = "Traffic Light Bar · \(monitor.isPaused ? "已暂停" : level.title)\nCPU \(MetricFormat.percent(stats.cpuUsage)) · 内存 \(stats.memoryTotal > 0 ? MetricFormat.percent(stats.memoryRatio * 100) : "—")\n\(stats.summary)"
        button.toolTip = description
        button.setAccessibilityLabel(description)
    }
    private func statusIcon(_ level: ResourceLevel) -> NSImage {
        let color: NSColor
        switch level {
        case .unknown: color = .secondaryLabelColor
        case .normal: color = .systemGreen
        case .busy: color = .systemOrange
        case .critical: color = .systemRed
        }
        let image = NSImage(size: NSSize(width: 14, height: 18), flipped: false) { rect in
            color.withAlphaComponent(0.16).setFill()
            NSBezierPath(ovalIn: NSRect(x: 0, y: rect.midY - 7, width: 14, height: 14)).fill()
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 3, y: rect.midY - 4, width: 8, height: 8)).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = level.title
        return image
    }

    private func handleSleep() {
        isSleeping = true
        popover?.performClose(nil)
        monitor.sleep()
        updateProcessSampling()
    }
    private func handleWake() {
        isSleeping = false
        monitor.wake()
        updateProcessSampling()
    }
    @objc private func togglePause() { monitor.togglePause() }
    @objc private func openActivityMonitor() { AppActions.openActivityMonitor() }
    @objc private func quitApp() { NSApp.terminate(nil) }
}
