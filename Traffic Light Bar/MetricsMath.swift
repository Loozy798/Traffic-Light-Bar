import Foundation

struct CPUTicks: Sendable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32

    func usage(since previous: CPUTicks?) -> Double? {
        guard let previous, user >= previous.user, system >= previous.system,
              idle >= previous.idle, nice >= previous.nice else { return nil }
        let busy = UInt64(user - previous.user) + UInt64(system - previous.system) + UInt64(nice - previous.nice)
        let total = busy + UInt64(idle - previous.idle)
        guard total > 0 else { return nil }
        return min(100, max(0, Double(busy) / Double(total) * 100))
    }
}

struct NetworkCounters: Sendable {
    let received: UInt64
    let sent: UInt64
}

struct NetworkRate: Sendable {
    var download: Double?
    var upload: Double?
    var sessionDownload: UInt64 = 0
    var sessionUpload: UInt64 = 0
}

struct NetworkTracker {
    private var previous: [String: NetworkCounters] = [:]
    private var previousUptime: TimeInterval?
    private var received: UInt64 = 0
    private var sent: UInt64 = 0

    mutating func resetBaseline() {
        previous = [:]
        previousUptime = nil
    }

    mutating func sample(counters: [String: NetworkCounters], uptime: TimeInterval) -> NetworkRate {
        defer { previous = counters; previousUptime = uptime }
        var result = NetworkRate(sessionDownload: received, sessionUpload: sent)
        guard let previousUptime else { return result }
        let elapsed = uptime - previousUptime
        guard elapsed > 0, elapsed <= 30 else { return result }
        var deltaIn: UInt64 = 0
        var deltaOut: UInt64 = 0
        var matched = false
        for (name, current) in counters {
            guard let old = previous[name], current.received >= old.received,
                  current.sent >= old.sent else { continue }
            matched = true
            deltaIn += current.received - old.received
            deltaOut += current.sent - old.sent
        }
        guard matched else { return result }
        received += deltaIn
        sent += deltaOut
        result.download = Double(deltaIn) / elapsed
        result.upload = Double(deltaOut) / elapsed
        result.sessionDownload = received
        result.sessionUpload = sent
        return result
    }
}

enum MetricFormat {
    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.0f%%", value)
    }
    static func bytes(_ value: UInt64) -> String {
        let units = ["B", "KiB", "MiB", "GiB", "TiB"]
        var number = Double(value)
        var index = 0
        while number >= 1024 && index < units.count - 1 { number /= 1024; index += 1 }
        return String(format: index >= 3 ? "%.1f %@" : "%.0f %@", number, units[index])
    }
    static func speed(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        if value >= 1_000_000 { return String(format: "%.1f MB/s", value / 1_000_000) }
        return String(format: "%.0f KB/s", value / 1000)
    }
}
