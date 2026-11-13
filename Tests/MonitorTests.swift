import Foundation
import Darwin

@main
struct MonitorTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        guard condition() else { fatalError("FAIL: \(message)") }
    }

    static func main() {
        // A lifetime-average implementation returns 30%, rather than 75%.
        let previous = CPUTicks(user: 100, system: 100, idle: 800, nice: 0)
        let current = CPUTicks(user: 150, system: 125, idle: 825, nice: 0)
        expect(current.usage(since: previous) == 75, "CPU reflects this interval, not uptime")
        expect(current.usage(since: nil) == nil, "first CPU sample waits for a baseline")
        expect(previous.usage(since: current) == nil, "reset counters cannot produce negative CPU")
        expect(current.usage(since: current) == nil, "zero tick delta is unavailable")
        expect(CPUTicks(user: 0, system: 0, idle: 50, nice: 50)
            .usage(since: CPUTicks(user: 0, system: 0, idle: 0, nice: 0)) == 50,
               "nice ticks count as busy")

        var tracker = NetworkTracker()
        expect(tracker.sample(counters: ["en0": .init(received: 1000, sent: 500)], uptime: 10).download == nil,
               "network baseline has no made-up rate")
        let rate = tracker.sample(counters: ["en0": .init(received: 3048, sent: 1524)], uptime: 12)
        expect(rate.download == 1024 && rate.upload == 512, "network rate uses actual elapsed seconds")
        expect(tracker.sample(counters: ["en1": .init(received: 9, sent: 1)], uptime: 14).download == nil,
               "new interface does not subtract another interface")
        expect(tracker.sample(counters: ["en1": .init(received: 3, sent: 0)], uptime: 16).download == nil,
               "counter rollover or reset cannot overflow")
        expect(tracker.sample(counters: ["en1": .init(received: 100000, sent: 100000)], uptime: 100).download == nil,
               "wake interval does not create misleading rates")
        expect(tracker.sample(counters: [:], uptime: 102).download == nil,
               "disconnection is unavailable, not a successful zero")

        let processes = ProcessSnapshot.parse("""
            12 125.5 2048 /Applications/My Test App.app/Contents/MacOS/My Test App
            24 2.0 4096 /usr/bin/WindowServer
            malformed line
            30 invalid 80 /bin/nope
        """)
        expect(processes.count == 2, "invalid ps rows are rejected")
        expect(processes.first?.id == 12, "PID is stable identity")
        expect(processes.first?.name == "My Test App", "spaces in process names survive parsing")
        expect(processes.first?.cpuPercent == 125.5, "per-process CPU can exceed one core")
        expect(processes.first?.memoryBytes == 2_097_152, "ps RSS KiB converts to bytes")

        var stats = SystemStats()
        expect(stats.level == .unknown, "no sample is not healthy")
        stats.memoryPressure = .normal
        expect(stats.level == .unknown, "a missing CPU sample must not claim the whole system is healthy")
        stats.cpuUsage = 90
        stats.memoryPressure = .normal
        expect(stats.level == .critical, "one overloaded resource cannot be hidden by averaging")
        stats.cpuUsage = 10
        stats.memoryPressure = .warning
        expect(stats.level == .busy, "memory pressure affects unified status")
        stats.memoryPressure = .normal
        stats.thermalLevel = .critical
        expect(stats.level == .critical, "thermal throttling affects unified status")
        expect(MetricFormat.speed(nil) == "—", "unavailable rate is distinct from zero")
        expect(MetricFormat.speed(0) == "0 KB/s", "a valid idle link shows zero")

        var interface = if_msghdr2()
        interface.ifm_msglen = UInt16(MemoryLayout<if_msghdr2>.size)
        interface.ifm_type = UInt8(RTM_IFINFO2)
        interface.ifm_index = 42
        interface.ifm_data.ifi_ibytes = 9_000_000_000
        interface.ifm_data.ifi_obytes = 5_000_000_000
        let message = Data(bytes: &interface, count: MemoryLayout<if_msghdr2>.size)
        let counters = NetworkCounterReader.decodeMessages(message)
        expect(counters?[42]?.received == 9_000_000_000, "network byte counters remain 64-bit beyond 4 GiB")
        expect(counters?[42]?.sent == 5_000_000_000, "64-bit upload counters survive decoding")
        expect(NetworkCounterReader.decodeMessages(message.prefix(8)) == nil, "truncated routing messages are rejected")
        expect(NetworkCounterReader.decodeMessages(Data(repeating: 0, count: 4)) == nil, "zero-length routing messages cannot loop forever")

        let start = Date(timeIntervalSince1970: 100)
        let samples = [
            MetricSample(id: start, cpu: 10, memory: nil, download: nil, upload: nil),
            MetricSample(id: start.addingTimeInterval(1), cpu: nil, memory: nil, download: nil, upload: nil),
            MetricSample(id: start.addingTimeInterval(2), cpu: 20, memory: nil, download: nil, upload: nil),
            MetricSample(id: start.addingTimeInterval(3), segment: 5, cpu: 30, memory: nil, download: nil, upload: nil)
        ]
        let points = TrendSeries.points(in: samples, value: \.cpu)
        expect(points.count == 3, "unavailable samples do not invent values")
        expect(points[0].segment != points[1].segment, "missing samples break chart lines")
        expect(points[1].segment != points[2].segment, "pause and sleep segments break chart lines")
        print("PASS: \(assertions) regression assertions")
    }
}
