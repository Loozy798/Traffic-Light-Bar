import SwiftUI
import AppKit

// MARK: - 仪表盘主视图

struct DashboardView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var energyMonitor: EnergyMonitor
    @ObservedObject var preferences: AppPreferences

    enum Tab: String, CaseIterable, Identifiable {
        case overview = "概览"
        case energy   = "能耗"
        case settings = "设置"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .overview: return "gauge.medium"
            case .energy:   return "bolt.circle.fill"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    @State private var selectedTab: Tab = .overview

    var body: some View {
        NavigationSplitView {
            // 侧边栏
            List(Tab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
                    .padding(.vertical, 4)
            }
            .navigationTitle("Traffic Light Bar")
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch selectedTab {
                case .overview: OverviewTab(monitor: monitor)
                case .energy:   EnergyTab(energyMonitor: energyMonitor, preferences: preferences)
                case .settings: SettingsTab(preferences: preferences)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // ✅ prominentDetail: 侧边栏收起时右侧面板位置不变
        .navigationSplitViewStyle(.prominentDetail)
        .frame(minWidth: 680, minHeight: 460)
    }
}

// MARK: - 概览 Tab

private struct OverviewTab: View {
    @ObservedObject var monitor: SystemMonitor

    private var cpuRatio:  Double { monitor.stats.cpuUsage / 100 }
    private var memRatio:  Double {
        guard monitor.stats.memoryTotal > 0 else { return 0 }
        return Double(monitor.stats.memoryUsed) / Double(monitor.stats.memoryTotal)
    }
    private var diskRatio: Double {
        guard monitor.stats.diskTotal > 0 else { return 0 }
        return Double(monitor.stats.diskUsed) / Double(monitor.stats.diskTotal)
    }

    private func bytes(_ b: UInt64) -> String {
        let gb = Double(b) / 1_073_741_824
        let mb = Double(b) / 1_048_576
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", mb)
    }
    private func speed(_ bps: Double) -> String {
        let mbps = bps / 1_048_576
        if mbps >= 1 { return String(format: "%.1f MB/s", mbps) }
        return String(format: "%.0f KB/s", bps / 1024)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 环形仪表盘行
                HStack(spacing: 32) {
                    RingGauge(
                        ratio: cpuRatio,
                        label: "CPU",
                        valueText: String(format: "%.1f%%", monitor.stats.cpuUsage),
                        color: gaugeColor(cpuRatio)
                    )
                    RingGauge(
                        ratio: memRatio,
                        label: "内存",
                        valueText: String(format: "%.0f%%", memRatio * 100),
                        color: gaugeColor(memRatio)
                    )
                    RingGauge(
                        ratio: diskRatio,
                        label: "磁盘",
                        valueText: String(format: "%.0f%%", diskRatio * 100),
                        color: gaugeColor(diskRatio)
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 16)

                Divider()

                // 详细数据
                VStack(spacing: 0) {
                    DetailRow(icon: "memorychip", label: "内存",
                              value: "\(bytes(monitor.stats.memoryUsed)) / \(bytes(monitor.stats.memoryTotal))")
                    DetailRow(icon: "internaldrive", label: "磁盘",
                              value: "\(bytes(monitor.stats.diskUsed)) / \(bytes(monitor.stats.diskTotal))")
                    DetailRow(icon: "arrow.down.circle", label: "下载速度",
                              value: speed(monitor.stats.networkDownload))
                    DetailRow(icon: "arrow.up.circle",   label: "上传速度",
                              value: speed(monitor.stats.networkUpload))
                    DetailRow(icon: "network", label: "本机 IP",
                              value: monitor.stats.localIP)
                    if monitor.stats.batteryPresent {
                        DetailRow(icon: "battery.75", label: "电池",
                                  value: String(format: "%.0f%%", monitor.stats.batteryLevel ?? 0)
                                    + (monitor.stats.batteryCharging == true ? "  充电中 ⚡" : ""))
                    }
                }
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(24)
        }
        .navigationTitle("系统概览")
    }

    private func gaugeColor(_ ratio: Double) -> Color {
        TrafficLightIconView.color(for: ratio)
    }
}

// MARK: - 能耗 Tab

private struct EnergyTab: View {
    @ObservedObject var energyMonitor: EnergyMonitor
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 警告 banner
            if energyMonitor.hasHighConsumer {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("检测到高能耗应用，可能影响电池续航")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .padding(12)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // 标题行
            HStack {
                Text("应用名称")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 200, alignment: .leading)
                Spacer()
                Text("CPU 占用")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)

            // App 列表
            VStack(spacing: 0) {
                if energyMonitor.topConsumers.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.green)
                        Text("系统能耗正常")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                } else {
                    ForEach(Array(energyMonitor.topConsumers.enumerated()), id: \.element.id) { i, app in
                        EnergyRow(app: app, rank: i + 1)
                        if i < energyMonitor.topConsumers.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
            }
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // 说明
            Text("* CPU 占用率是能耗的主要指标，占用越高耗电越多")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            // 阈值设置
            HStack {
                Text("高能耗警告阈值：")
                    .font(.system(size: 13))
                Slider(value: $preferences.energyThreshold, in: 5...80, step: 5)
                    .frame(width: 160)
                Text("\(Int(preferences.energyThreshold))% CPU")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 70, alignment: .leading)
            }
            .padding(.bottom, 4)
        }
        .padding(24)
        .navigationTitle("能耗监控")
    }
}

private struct EnergyRow: View {
    let app: AppEnergyInfo
    let rank: Int

    private var levelColor: Color {
        switch app.level {
        case .low:    return .green
        case .medium: return Color(red: 0.95, green: 0.76, blue: 0.06)
        case .high:   return Color(red: 0.91, green: 0.30, blue: 0.24)
        }
    }
    private var levelLabel: String {
        switch app.level {
        case .low:    return "低"
        case .medium: return "中"
        case .high:   return "高"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // 排名
            Text("\(rank)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 20, alignment: .center)

            // App 名
            Text(app.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .frame(width: 200, alignment: .leading)

            Spacer()

            // 进度条
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.07))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(levelColor.opacity(0.8))
                        .frame(width: geo.size.width * min(app.cpuPercent / 100, 1))
                        .animation(.easeOut(duration: 0.5), value: app.cpuPercent)
                }
            }
            .frame(width: 120, height: 6)

            // 百分比 + 级别
            Text(String(format: "%.1f%%", app.cpuPercent))
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 48, alignment: .trailing)

            Text(levelLabel)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(levelColor.opacity(0.15))
                .foregroundColor(levelColor)
                .clipShape(Capsule())
                .frame(width: 36)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

// MARK: - 设置 Tab

private struct SettingsTab: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        Form {
            Section {
                Toggle("CPU 使用率", isOn: $preferences.showCPU)
                Toggle("内存使用",   isOn: $preferences.showMemory)
                Toggle("磁盘使用",   isOn: $preferences.showDisk)
                Toggle("网络速度",   isOn: $preferences.showNetwork)
                Toggle("电池状态",   isOn: $preferences.showBattery)
            } header: {
                Label("状态栏下拉菜单显示项目", systemImage: "checklist")
                    .font(.system(size: 13, weight: .semibold))
            }

            Section {
                Toggle("启用高能耗应用警告", isOn: $preferences.showEnergyWarning)
                if preferences.showEnergyWarning {
                    HStack {
                        Text("警告阈值")
                        Slider(value: $preferences.energyThreshold, in: 5...80, step: 5)
                        Text("\(Int(preferences.energyThreshold))%")
                            .foregroundColor(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            } header: {
                Label("能耗提醒", systemImage: "bolt.circle")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .formStyle(.grouped)
        .navigationTitle("偏好设置")
    }
}

// MARK: - 共用组件

struct RingGauge: View {
    let ratio: Double
    let label: String
    let valueText: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: min(ratio, 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: ratio)
                VStack(spacing: 2) {
                    Text(valueText)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(label)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 100, height: 100)
        }
    }
}

private struct DetailRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 13))
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
