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
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                // ✅ 关键修复：ps 是阻塞调用，必须放到独立线程
                // 直接在 Task（协作线程池）里调 waitUntilExit 会阻塞整个线程池导致 App 无响应
                let consumers = await withCheckedContinuation {
                    (cont: CheckedContinuation<[AppEnergyInfo], Never>) in
                    DispatchQueue.global(qos: .utility).async {
                        cont.resume(returning: Self.fetchTopConsumers())
                    }
                }

                guard let self, !Task.isCancelled else { break }
                let thresh = self.threshold
                await MainActor.run {
                    self.topConsumers    = consumers
                    self.hasHighConsumer = consumers.contains { $0.cpuPercent >= thresh }
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    // MARK: - ps 采样（在 DispatchQueue.global 上运行）

    private static func fetchTopConsumers() -> [AppEnergyInfo] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-eo", "pid=,comm=,%cpu=", "-r"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = Pipe()
        guard (try? proc.run()) != nil else { return [] }
        proc.waitUntilExit()      // 阻塞调用，已确保在 global 队列上

        let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                         encoding: .utf8) ?? ""
        var results: [AppEnergyInfo] = []

        for line in raw.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3,
                  let cpu = Double(parts[2]),
                  cpu >= 0.5 else { continue }

            let rawName = String(parts[1])
            let name    = rawName.components(separatedBy: "/").last ?? rawName
            guard name != "ps", !name.hasPrefix("kernel_task"),
                  name != "Traffic Light Ba" else { continue }

            results.append(AppEnergyInfo(name: name, cpuPercent: cpu))
            if results.count >= 10 { break }
        }
        return results
    }
}
