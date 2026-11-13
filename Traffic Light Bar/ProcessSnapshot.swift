import Foundation

struct AppEnergyInfo: Identifiable, Sendable {
    let id: Int32
    let name: String
    let executablePath: String
    let cpuPercent: Double
    let memoryBytes: UInt64
}

enum ProcessSnapshot {
    static func parse(_ output: String) -> [AppEnergyInfo] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(maxSplits: 3, whereSeparator: \.isWhitespace)
            guard fields.count == 4, let pid = Int32(fields[0]), pid > 0,
                  let cpu = Double(fields[1]), cpu.isFinite, cpu >= 0,
                  let rss = UInt64(fields[2]), rss <= UInt64.max / 1024 else { return nil }
            let path = String(fields[3]).trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { return nil }
            return AppEnergyInfo(id: pid, name: URL(fileURLWithPath: path).lastPathComponent,
                                 executablePath: path, cpuPercent: cpu, memoryBytes: rss * 1024)
        }
    }
}
