import Foundation
import Combine

/// This reports CPU and resident memory, not a hardware energy-impact measurement.
@MainActor
final class EnergyMonitor: ObservableObject {
    @Published private(set) var topConsumers: [AppEnergyInfo] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?
    @Published var threshold: Double = 20
    var hasHighConsumer: Bool { errorMessage == nil && topConsumers.contains { $0.cpuPercent >= threshold } }

    private let queue = DispatchQueue(label: "TrafficLightBar.process-sampling", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var generation = 0
    private var isActive = false

    deinit { timer?.cancel() }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        generation += 1
        timer?.cancel()
        timer = nil
        guard active else { return }
        let currentGeneration = generation
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: 5, leeway: .milliseconds(500))
        source.setEventHandler { [weak self] in
            let result = ProcessSampler.fetch()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                switch result {
                case .success(let processes):
                    self.topConsumers = processes.sorted { $0.cpuPercent > $1.cpuPercent }
                    self.errorMessage = nil
                    self.lastUpdated = Date()
                case .failure:
                    self.topConsumers = []
                    self.errorMessage = "macOS 限制了进程访问。请在活动监视器中查看完整进程。"
                    self.lastUpdated = nil
                }
            }
        }
        timer = source
        source.resume()
    }
}

enum ProcessSampleError: Error { case unavailable }

enum ProcessSampler {
    static func fetch() -> Result<[AppEnergyInfo], ProcessSampleError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-A", "-o", "pid=,pcpu=,rss=,comm="]
        process.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .failure(.unavailable) }
        // Drain before waiting: a full pipe must never block ps and its parent indefinitely.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
            return .failure(.unavailable)
        }
        let rows = ProcessSnapshot.parse(text).filter { $0.id != process.processIdentifier }
        guard !rows.isEmpty else { return .failure(.unavailable) }
        return .success(rows)
    }
}
