import Foundation

@main
struct IntegrationTests {
    @MainActor
    static func main() async throws {
        let monitor = SystemMonitor(startImmediately: false)
        monitor.setInterval(1)
        try await Task.sleep(for: .milliseconds(2300))
        guard let cpu = monitor.stats.cpuUsage, cpu >= 0, cpu <= 100 else {
            fatalError("Live CPU sampling did not publish an interval")
        }
        precondition(monitor.stats.memoryTotal > 0, "Physical memory is available")
        precondition(monitor.stats.memoryUsed <= monitor.stats.memoryTotal, "Memory usage is bounded")
        precondition(monitor.stats.diskTotal > 0, "Disk capacity is available")
        precondition(NetworkCounterReader.read() != nil, "64-bit routing counter API is available")
        if monitor.stats.localIP != nil {
            precondition(monitor.stats.networkDownload.map { $0 >= 0 && $0.isFinite } == true,
                         "A connected interface publishes valid 64-bit network rates")
        }
        if monitor.stats.batteryPresent {
            precondition(monitor.stats.batteryLevel.map { (0...100).contains($0) } == true, "Internal battery capacity is valid")
        }
        monitor.togglePause()
        let pausedDate = monitor.stats.sampledAt
        let pausedCount = monitor.history.count
        try await Task.sleep(for: .milliseconds(1300))
        precondition(monitor.stats.sampledAt == pausedDate && monitor.history.count == pausedCount,
                     "Pause prevents stale queued results and fake history")
        monitor.togglePause()
        try await Task.sleep(for: .milliseconds(2300))
        precondition(monitor.stats.sampledAt != pausedDate && monitor.stats.cpuUsage != nil, "Resume takes fresh CPU baselines")
        let awakeSegment = monitor.history.last!.segment
        monitor.sleep()
        let sleepingDate = monitor.stats.sampledAt
        try await Task.sleep(for: .milliseconds(1300))
        precondition(monitor.stats.sampledAt == sleepingDate, "Sleep stops publication")
        monitor.wake()
        try await Task.sleep(for: .milliseconds(2300))
        precondition(monitor.stats.sampledAt != sleepingDate, "Wake resumes sampling")
        precondition(monitor.history.last!.segment != awakeSegment, "Trend segments do not bridge sleep gaps")
        monitor.togglePause()
        monitor.sleep()
        monitor.wake()
        try await Task.sleep(for: .milliseconds(1100))
        precondition(monitor.isPaused, "Wake preserves the user's paused state")
        let defaults = UserDefaults(suiteName: "TrafficLightBar.IntegrationTests")!
        defaults.removePersistentDomain(forName: "TrafficLightBar.IntegrationTests")
        defaults.set(0.01, forKey: "refreshInterval")
        defaults.set(-100, forKey: "energyThreshold")
        let preferences = AppPreferences(defaults: defaults)
        precondition(preferences.refreshInterval == 2 && preferences.energyThreshold == 5, "Persisted input is validated")
        preferences.statusDisplay = .network
        precondition(AppPreferences(defaults: defaults).statusDisplay == .network, "Preferences persist")
        defaults.removePersistentDomain(forName: "TrafficLightBar.IntegrationTests")
        switch ProcessSampler.fetch() {
        case .success(let processes):
            precondition(!processes.isEmpty && processes.allSatisfy { $0.cpuPercent.isFinite }, "Live process output parses")
            print("PASS: live process collection (\(processes.count) processes)")
        case .failure:
            print("INFO: process access restricted; UI must show the explicit unavailable state")
        }
        print("PASS: live system sampling, pause/resume, sleep/wake, history gaps, preference validation and persistence")
    }
}
