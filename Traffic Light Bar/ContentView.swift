//
//  ContentView.swift
//  Traffic Light Bar
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TrafficMonitor")
                .font(.headline)
                .padding(.top, 8)

            Group {
                // CPU
                RowView(title: "CPU", value: monitor.stats.cpuUsage, format: "%.1f%%", color: colorFor(monitor.stats.cpuUsage, low: 30, high: 70))
                if let temp = monitor.stats.cpuTemperature {
                    Text("Temperature: \(temp, specifier: "%.0f") °C")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Memory
                let memPercent = monitor.stats.memoryTotal > 0
                    ? Double(monitor.stats.memoryUsed) / Double(monitor.stats.memoryTotal) * 100
                    : 0
                RowView(title: "Memory",
                        value: memPercent,
                        format: "%.1f%%",
                        color: colorFor(memPercent, low: 60, high: 85),
                        detail: "\(formatBytes(monitor.stats.memoryUsed)) / \(formatBytes(monitor.stats.memoryTotal))")

                // Disk
                let diskPercent = monitor.stats.diskTotal > 0
                    ? Double(monitor.stats.diskUsed) / Double(monitor.stats.diskTotal) * 100
                    : 0
                RowView(title: "Disk",
                        value: diskPercent,
                        format: "%.1f%%",
                        color: colorFor(diskPercent, low: 70, high: 90),
                        detail: "\(formatBytes(monitor.stats.diskUsed)) / \(formatBytes(monitor.stats.diskTotal))")

                // Network
                VStack(alignment: .leading, spacing: 4) {
                    Text("Network")
                        .font(.subheadline)
                    HStack {
                        Text("↓ \(formatSpeed(monitor.stats.networkDownload))")
                        Spacer()
                        Text("↑ \(formatSpeed(monitor.stats.networkUpload))")
                    }
                    .font(.system(.caption, design: .monospaced))
                    Text("IP: \(monitor.stats.localIP)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Battery
                if monitor.stats.batteryPresent {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Battery")
                            .font(.subheadline)
                        if let level = monitor.stats.batteryLevel {
                            HStack {
                                Text("\(level, specifier: "%.0f")%")
                                    .bold()
                                if let charging = monitor.stats.batteryCharging {
                                    Image(systemName: charging ? "bolt.fill" : "bolt.slash")
                                        .foregroundColor(charging ? .green : .secondary)
                                }
                            }
                            if let remaining = monitor.stats.batteryTimeRemaining {
                                Text("Remaining: \(remaining)")
                                    .font(.caption2)
                            }
                        } else {
                            Text("Calculating…")
                        }
                    }
                } else {
                    Text("Power: AC Adapter")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 0)
        }
        .frame(width: 260)
        .padding(.bottom, 12)
    }

    private func colorFor(_ percent: Double, low: Double, high: Double) -> Color {
        if percent > high { return .red }
        if percent > low { return .yellow }
        return .green
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let form = ByteCountFormatter()
        form.countStyle = .file
        return form.string(fromByteCount: Int64(bytes))
    }

    private func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_000_000)
        } else if bytesPerSec >= 1_000 {
            return String(format: "%.0f KB/s", bytesPerSec / 1_000)
        } else {
            return String(format: "%.0f B/s", bytesPerSec)
        }
    }
}

struct RowView: View {
    let title: String
    let value: Double
    let format: String
    let color: Color
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(String(format: format, value))
                    .bold()
            }
            ProgressView(value: value, total: 100)
                .tint(color)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
