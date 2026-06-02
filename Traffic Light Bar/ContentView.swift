import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var monitor: SystemMonitor

    // 格式化字节单位
    private func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        let mb = Double(bytes) / 1_048_576
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        if mb >= 1 { return String(format: "%.0f MB", mb) }
        return "\(bytes) B"
    }

    // 格式化网速
    private func formatSpeed(_ bps: Double) -> String {
        let mbps = bps / 1_048_576
        let kbps = bps / 1024
        if mbps >= 1 { return String(format: "%.1f MB/s", mbps) }
        return String(format: "%.0f KB/s", kbps)
    }

    // 综合负载
    private var combinedLoad: Double {
        let cpu = monitor.stats.cpuUsage
        let mem = monitor.stats.memoryTotal > 0
            ? (Double(monitor.stats.memoryUsed) / Double(monitor.stats.memoryTotal)) * 100 : 0
        let disk = monitor.stats.diskTotal > 0
            ? (Double(monitor.stats.diskUsed) / Double(monitor.stats.diskTotal)) * 100 : 0
        return cpu * 0.4 + mem * 0.35 + disk * 0.25
    }

    private var loadColor: Color {
        switch combinedLoad {
        case ..<30:   return Color(red: 0.18, green: 0.80, blue: 0.44)
        case 30..<70: return Color(red: 0.95, green: 0.76, blue: 0.06)
        default:      return Color(red: 0.91, green: 0.30, blue: 0.24)
        }
    }

    private var loadLabel: String {
        switch combinedLoad {
        case ..<30:   return "空闲"
        case 30..<70: return "中等"
        default:      return "高负载"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── 顶部综合负载指示 ──
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    // 三色灯预览
                    HStack(spacing: 4) {
                        Circle()
                            .fill(combinedLoad < 30
                                  ? Color(red: 0.18, green: 0.80, blue: 0.44)
                                  : Color.gray.opacity(0.25))
                            .frame(width: 10, height: 10)
                        Circle()
                            .fill(combinedLoad >= 30 && combinedLoad < 70
                                  ? Color(red: 0.95, green: 0.76, blue: 0.06)
                                  : Color.gray.opacity(0.25))
                            .frame(width: 10, height: 10)
                        Circle()
                            .fill(combinedLoad >= 70
                                  ? Color(red: 0.91, green: 0.30, blue: 0.24)
                                  : Color.gray.opacity(0.25))
                            .frame(width: 10, height: 10)
                    }
                    Text("Traffic Light Bar")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(loadLabel)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(loadColor.opacity(0.18))
                        .foregroundColor(loadColor)
                        .clipShape(Capsule())
                }

                // 综合负载进度条
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(loadColor)
                            .frame(width: geo.size.width * min(combinedLoad / 100, 1), height: 6)
                            .animation(.easeOut(duration: 0.4), value: combinedLoad)
                    }
                }
                .frame(height: 6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().opacity(0.5)

            // ── 详细指标 ──
            VStack(spacing: 0) {
                metricRow(
                    icon: "cpu",
                    label: "CPU",
                    value: String(format: "%.1f%%", monitor.stats.cpuUsage),
                    ratio: monitor.stats.cpuUsage / 100,
                    color: colorFor(monitor.stats.cpuUsage)
                )
                Divider().opacity(0.3).padding(.leading, 36)

                let memRatio = monitor.stats.memoryTotal > 0
                    ? Double(monitor.stats.memoryUsed) / Double(monitor.stats.memoryTotal) : 0
                metricRow(
                    icon: "memorychip",
                    label: "内存",
                    value: "\(formatBytes(monitor.stats.memoryUsed)) / \(formatBytes(monitor.stats.memoryTotal))",
                    ratio: memRatio,
                    color: colorFor(memRatio * 100)
                )
                Divider().opacity(0.3).padding(.leading, 36)

                let diskRatio = monitor.stats.diskTotal > 0
                    ? Double(monitor.stats.diskUsed) / Double(monitor.stats.diskTotal) : 0
                metricRow(
                    icon: "internaldrive",
                    label: "磁盘",
                    value: "\(formatBytes(monitor.stats.diskUsed)) / \(formatBytes(monitor.stats.diskTotal))",
                    ratio: diskRatio,
                    color: colorFor(diskRatio * 100)
                )
                Divider().opacity(0.3).padding(.leading, 36)

                networkRow()
            }

            // ── 电池（仅 MacBook）──
            if monitor.stats.batteryPresent {
                Divider().opacity(0.5)
                batterySection()
            }

            Divider().opacity(0.5)

            // ── 底部操作栏 ──
            HStack(spacing: 0) {
                actionButton(icon: "network", label: monitor.stats.localIP)
                Spacer()
                actionButton(icon: "arrow.clockwise.circle", label: "活动监视器") {
                    NSWorkspace.shared.launchApplication("Activity Monitor")
                }
                Spacer()
                actionButton(icon: "power", label: "退出") {
                    NSApp.terminate(nil)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 300)
        .background(.ultraThinMaterial)
    }

    // MARK: - 子视图

    @ViewBuilder
    private func metricRow(icon: String, label: String, value: String, ratio: Double, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(value)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.07))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color.opacity(0.8))
                            .frame(width: geo.size.width * min(ratio, 1), height: 4)
                            .animation(.easeOut(duration: 0.5), value: ratio)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func networkRow() -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 13))
                .foregroundColor(.blue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("网络")
                    .font(.system(size: 12, weight: .medium))
                HStack(spacing: 12) {
                    Label(formatSpeed(monitor.stats.networkDownload), systemImage: "arrow.down")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    Label(formatSpeed(monitor.stats.networkUpload), systemImage: "arrow.up")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func batterySection() -> some View {
        HStack(spacing: 10) {
            Image(systemName: monitor.stats.batteryCharging == true
                  ? "bolt.fill" : "battery.75")
                .font(.system(size: 13))
                .foregroundColor(.green)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("电池")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(String(format: "%.0f%%", monitor.stats.batteryLevel ?? 0))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    if monitor.stats.batteryCharging == true {
                        Text("充电中")
                            .font(.system(size: 10))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                }
                if let remaining = monitor.stats.batteryTimeRemaining {
                    Text("剩余 \(remaining)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func actionButton(icon: String, label: String, action: (() -> Void)? = nil) -> some View {
        Button {
            action?()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(label)
                    .font(.system(size: 9))
                    .lineLimit(1)
            }
            .foregroundColor(.secondary)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
    }

    private func colorFor(_ percent: Double) -> Color {
        switch percent {
        case ..<50:   return .green
        case 50..<80: return Color(red: 0.95, green: 0.76, blue: 0.06)
        default:      return Color(red: 0.91, green: 0.30, blue: 0.24)
        }
    }
}

#Preview {
    ContentView(monitor: SystemMonitor())
        .frame(width: 300)
}
