import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var energyMonitor: EnergyMonitor
    @ObservedObject var preferences: AppPreferences
    var onOpenDashboard: () -> Void

    // ✅ 压力值 = CPU 60% + 内存 40%
    private var combinedLoad: Double {
        let cpu = monitor.stats.cpuUsage
        let mem = monitor.stats.memoryTotal > 0
            ? Double(monitor.stats.memoryUsed) / Double(monitor.stats.memoryTotal) * 100 : 0
        return cpu * 0.6 + mem * 0.4
    }

    // 下拉面板统一用离散三色
    private var loadColor: Color {
        discreteColor(combinedLoad)
    }

    private func discreteColor(_ pct: Double) -> Color {
        pct < 50 ? Color(red: 0.18, green: 0.80, blue: 0.44)
            : pct < 80 ? Color(red: 0.95, green: 0.76, blue: 0.06)
            : Color(red: 0.91, green: 0.30, blue: 0.24)
    }

    private var loadLabel: String {
        combinedLoad < 30 ? "空闲" : combinedLoad < 60 ? "中等" : "高负载"
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        let mb = Double(bytes) / 1_048_576
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", mb)
    }
    private func formatSpeed(_ bps: Double) -> String {
        bps / 1_048_576 >= 1
            ? String(format: "%.1f MB/s", bps / 1_048_576)
            : String(format: "%.0f KB/s", bps / 1024)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── 顶部：综合压力 ──
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    // 下拉面板指示灯：经典三色实心圆
                    Circle()
                        .fill(loadColor)
                        .frame(width: 9, height: 9)
                    Text("Traffic Light Bar")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(loadLabel)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(loadColor.opacity(0.18))
                        .foregroundColor(loadColor)
                        .clipShape(Capsule())
                }
                // 进度条：经典三色
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.primary.opacity(0.08)).frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(loadColor)
                            .frame(width: geo.size.width * min(combinedLoad / 100, 1), height: 6)
                            .animation(.easeOut(duration: 0.4), value: combinedLoad)
                    }
                }
                .frame(height: 6)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)

            // ── 能耗警告 Banner ──
            if preferences.showEnergyWarning && energyMonitor.hasHighConsumer {
                Divider().opacity(0.5)
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill").font(.system(size: 11)).foregroundColor(.orange)
                    Text("检测到高能耗应用").font(.system(size: 11, weight: .medium))
                    Spacer()
                    Button("查看") { onOpenDashboard() }
                        .font(.system(size: 11)).foregroundColor(.orange).buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            }

            Divider().opacity(0.5)

            // ── 指标列表 ──
            VStack(spacing: 0) {
                if preferences.showCPU {
                    metricRow(icon: "cpu", label: "CPU",
                              value: String(format: "%.1f%%", monitor.stats.cpuUsage),
                              ratio: monitor.stats.cpuUsage / 100)
                    Divider().opacity(0.3).padding(.leading, 36)
                }
                if preferences.showMemory {
                    let r = monitor.stats.memoryTotal > 0
                        ? Double(monitor.stats.memoryUsed) / Double(monitor.stats.memoryTotal) : 0
                    metricRow(icon: "memorychip", label: "内存",
                              value: "\(formatBytes(monitor.stats.memoryUsed)) / \(formatBytes(monitor.stats.memoryTotal))",
                              ratio: r)
                    Divider().opacity(0.3).padding(.leading, 36)
                }
                if preferences.showDisk {
                    let r = monitor.stats.diskTotal > 0
                        ? Double(monitor.stats.diskUsed) / Double(monitor.stats.diskTotal) : 0
                    metricRow(icon: "internaldrive", label: "磁盘",
                              value: "\(formatBytes(monitor.stats.diskUsed)) / \(formatBytes(monitor.stats.diskTotal))",
                              ratio: r)
                    Divider().opacity(0.3).padding(.leading, 36)
                }
                if preferences.showNetwork { networkRow() }
                if preferences.showBattery && monitor.stats.batteryPresent {
                    Divider().opacity(0.3).padding(.leading, 36)
                    batteryRow()
                }
            }

            Divider().opacity(0.5)

            // ── 底部操作栏 ──
            HStack {
                Button { onOpenDashboard() } label: {
                    Label("仪表盘", systemImage: "gauge.medium")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()

                actionButton(icon: "arrow.clockwise.circle", label: "活动监视器") {
                    NSWorkspace.shared.launchApplication("Activity Monitor")
                }
                actionButton(icon: "power", label: "退出") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(width: 300)
        .background(.ultraThinMaterial)
    }

    // MARK: - 子视图

    @ViewBuilder
    private func metricRow(icon: String, label: String, value: String, ratio: Double) -> some View {
        let color = discreteColor(ratio * 100)
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13)).foregroundColor(color).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(label).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(value).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.07)).frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color.opacity(0.85))
                            .frame(width: geo.size.width * min(ratio, 1), height: 4)
                            .animation(.easeOut(duration: 0.5), value: ratio)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    @ViewBuilder
    private func networkRow() -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.arrow.down").font(.system(size: 13)).foregroundColor(.blue).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("网络").font(.system(size: 12, weight: .medium))
                HStack(spacing: 12) {
                    Label(formatSpeed(monitor.stats.networkDownload), systemImage: "arrow.down")
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                    Label(formatSpeed(monitor.stats.networkUpload), systemImage: "arrow.up")
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    @ViewBuilder
    private func batteryRow() -> some View {
        HStack(spacing: 10) {
            Image(systemName: monitor.stats.batteryCharging == true ? "bolt.fill" : "battery.75")
                .font(.system(size: 13)).foregroundColor(.green).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("电池").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(String(format: "%.0f%%", monitor.stats.batteryLevel ?? 0))
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                    if monitor.stats.batteryCharging == true {
                        Text("充电中").font(.system(size: 10))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.green.opacity(0.15)).foregroundColor(.green).clipShape(Capsule())
                    }
                }
                if let r = monitor.stats.batteryTimeRemaining {
                    Text("剩余 \(r)").font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    @ViewBuilder
    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 13))
                Text(label).font(.system(size: 9)).lineLimit(1)
            }
            .foregroundColor(.secondary).padding(.vertical, 4).padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView(monitor: SystemMonitor(), energyMonitor: EnergyMonitor(),
                preferences: .shared, onOpenDashboard: {})
        .frame(width: 300)
}
