import Foundation
import Combine

struct AppEnergyInfo: Identifiable {
    let id = UUID()
    let name: String
    let cpuPercent: Double

    enum Level { case low, medium, high }
    var level: Level {
        if cpuPercent >= 30 { return .high }
        if cpuPercent >= 10 { return .medium }
        return .low
    }
}

class EnergyMonitor: ObservableObject {
    @Published var topConsumers: [AppEnergyInfo] = []
    @Published var hasHighConsumer: Bool = false

    private var updateTask: Task<Void, Never>?
    var threshold: Double = 20.0

    init() { startMonitoring() }
    deinit { updateTask?.cancel() }

    func startMonitoring() {
        updateTask?.cancel()
        updateTask = Task {
            while !Task.isCancelled {
                let consumers = Self.fetchTopConsumers()
                await MainActor.run {
                    self.topConsumers = consumers
                    self.hasHighConsumer = consumers.contains { $0.cpuPercent >= self.threshold }
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    // MARK: - ps 采样

    private static func fetchTopConsumers() -> [AppEnergyInfo] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        // pid= comm= %cpu= — 无表头，空格分隔
        proc.arguments = ["-eo", "pid=,comm=,%cpu=", "-r"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return [] }
        proc.waitUntilExit()

        let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var results: [AppEnergyInfo] = []

        for line in raw.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3,
                  let cpu = Double(parts[2]),
                  cpu >= 0.5 else { continue }

            // comm 最多显示 16 字符，取最后路径段
            let rawName = String(parts[1])
            let name = rawName.components(separatedBy: "/").last ?? rawName

            // 过滤内核和自身
            guard name != "ps", !name.hasPrefix("kernel_task"),
                  name != "Traffic Light Ba" else { continue }

            results.append(AppEnergyInfo(name: name, cpuPercent: cpu))
            if results.count >= 10 { break }
        }
        return results
    }
}
