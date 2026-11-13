import Foundation
import Combine

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var stats = SystemStats()
    @Published private(set) var history: [MetricSample] = []
    @Published private(set) var isPaused = false
    private let queue = DispatchQueue(label: "TrafficLightBar.system-sampling", qos: .utility)
    private let sampler = SystemSampler()
    private var timer: DispatchSourceTimer?
    private var generation = 0
    private var historySegment = 0
    private var interval: TimeInterval = 2
    private var isSleeping = false

    init(startImmediately: Bool = true) {
        if startImmediately { start() }
    }
    deinit { timer?.cancel() }

    func setInterval(_ seconds: TimeInterval) {
        let clamped = [1.0, 2.0, 5.0].contains(seconds) ? seconds : 2
        guard interval != clamped else { return }
        interval = clamped
        if !isPaused && !isSleeping { start() }
    }
    func togglePause() {
        isPaused.toggle()
        if isPaused { stop() } else if !isSleeping { start() }
    }
    func sleep() { isSleeping = true; stop() }
    func wake() { isSleeping = false; if !isPaused { start() } }

    private func stop() {
        generation += 1
        historySegment += 1
        timer?.cancel()
        timer = nil
    }
    private func start() {
        stop()
        let currentGeneration = generation
        let sampler = sampler
        queue.async { sampler.resetBaseline() }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(150))
        source.setEventHandler { [weak self] in
            let snapshot = sampler.collect()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == currentGeneration, !self.isPaused, !self.isSleeping else { return }
                self.stats = snapshot
                guard let date = snapshot.sampledAt else { return }
                self.history.removeAll { $0.id < date.addingTimeInterval(-300) }
                self.history.append(MetricSample(id: date, segment: self.historySegment, cpu: snapshot.cpuUsage,
                                                 memory: snapshot.memoryTotal > 0 ? snapshot.memoryRatio * 100 : nil,
                                                 download: snapshot.networkDownload, upload: snapshot.networkUpload))
            }
        }
        timer = source
        source.resume()
    }
}
