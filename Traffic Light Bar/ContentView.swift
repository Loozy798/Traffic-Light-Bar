import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var energyMonitor: EnergyMonitor
    @ObservedObject var preferences: AppPreferences
    var onOpenDashboard: () -> Void
    var onOpenSettings: () -> Void

    private var stats: SystemStats { monitor.stats }
    private var contentHeight: CGFloat {
        var height: CGFloat = 80
        if preferences.showCPU || preferences.showMemory { height += 146 }
        if preferences.showNetwork { height += 114 }
        if preferences.showDisk { height += 59 }
        if preferences.showBattery && stats.batteryPresent { height += 62 }
        if preferences.showProcesses { height += 150 }
        if preferences.showEnergyWarning && energyMonitor.hasHighConsumer { height += 40 }
        return min(530, height)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TRAFFIC LIGHT BAR").font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(1.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onOpenSettings) { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.plain).help("偏好设置").accessibilityLabel("偏好设置")
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    StatusHeader(stats: stats, paused: monitor.isPaused, compact: true)
                    if !stats.unavailableMetrics.isEmpty {
                        Label("暂不可用：\(stats.unavailableMetrics.joined(separator: "、"))", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if preferences.showCPU || preferences.showMemory {
                        HStack(spacing: 10) {
                            if preferences.showCPU {
                                CompactMetric(title: "CPU", icon: "cpu", value: MetricFormat.percent(stats.cpuUsage),
                                              detail: "\(ProcessInfo.processInfo.activeProcessorCount) 核心 · 实时占用",
                                              ratio: (stats.cpuUsage ?? 0) / 100, color: MonitorStyle.cpu)
                            }
                            if preferences.showMemory {
                                CompactMetric(title: "内存", icon: "memorychip", value: stats.memoryTotal > 0 ? MetricFormat.percent(stats.memoryRatio * 100) : "—",
                                              detail: stats.memoryTotal > 0 ? "\(MetricFormat.bytes(stats.memoryUsed)) / \(MetricFormat.bytes(stats.memoryTotal))" : "等待采样",
                                              ratio: stats.memoryRatio, color: MonitorStyle.memory)
                            }
                        }
                    }
                    if preferences.showNetwork {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionCaption(title: "网络", detail: stats.interfaceName ?? "未连接")
                            HStack {
                                networkValue("下载", symbol: "arrow.down", value: stats.networkDownload, color: MonitorStyle.download)
                                Spacer()
                                networkValue("上传", symbol: "arrow.up", value: stats.networkUpload, color: MonitorStyle.upload)
                            }
                            if let ip = stats.localIP {
                                Button { AppActions.copy(ip) } label: {
                                    HStack { Text(ip).lineLimit(1); Image(systemName: "doc.on.doc") }
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain).help("复制本机 IP 地址")
                            }
                        }
                    }
                    if preferences.showDisk {
                        VStack(spacing: 8) {
                            HStack {
                                Label("磁盘空间", systemImage: "internaldrive").font(.caption)
                                Spacer()
                                Text(stats.diskTotal > 0 ? "剩余 \(MetricFormat.bytes(stats.diskTotal - stats.diskUsed))" : "暂不可用")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            UsageBar(ratio: stats.diskRatio, color: stats.diskRatio >= 0.9 ? .orange : .secondary)
                        }
                    }
                    if preferences.showBattery && stats.batteryPresent {
                        HStack(spacing: 10) {
                            BatteryIcon(percent: stats.batteryLevel ?? 0, charging: stats.batteryCharging == true)
                                .frame(width: 26, height: 13).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stats.batteryStatus).font(.caption)
                                if let time = stats.batteryTimeRemaining {
                                    Text("\(stats.batteryCharging == true ? "充满还需" : "预计可用") \(time)")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(MetricFormat.percent(stats.batteryLevel)).font(.callout.weight(.medium)).monospacedDigit()
                        }
                    }
                    if preferences.showProcesses {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            SectionCaption(title: "CPU 占用较高", detail: "每 5 秒更新")
                            if energyMonitor.errorMessage != nil {
                                Text("进程访问受限，可打开活动监视器查看。")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else if energyMonitor.lastUpdated == nil {
                                Text("正在读取进程…").font(.caption).foregroundStyle(.secondary)
                            } else {
                                ForEach(Array(energyMonitor.topConsumers.prefix(3))) { process in
                                    ProcessSummaryRow(process: process)
                                }
                            }
                        }
                    }
                    if preferences.showEnergyWarning && energyMonitor.hasHighConsumer {
                        Label("有进程超过 \(Int(preferences.energyThreshold))% CPU", systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)
            .frame(height: contentHeight)
            Divider()
            HStack(spacing: 12) {
                Button(action: onOpenDashboard) { Label("详细仪表盘", systemImage: "square.grid.2x2") }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Spacer()
                Button { monitor.togglePause() } label: { Image(systemName: monitor.isPaused ? "play.fill" : "pause.fill") }
                    .help(monitor.isPaused ? "恢复监控" : "暂停监控")
                    .accessibilityLabel(monitor.isPaused ? "恢复监控" : "暂停监控")
                Button { AppActions.openActivityMonitor() } label: { Image(systemName: "waveform.path.ecg.rectangle") }
                    .help("打开活动监视器").accessibilityLabel("打开活动监视器")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18).padding(.vertical, 13)
        }
        .frame(width: 360)
        .background(.regularMaterial)
    }

    private func networkValue(_ title: String, symbol: String, value: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.caption2).foregroundStyle(color)
            Text(MetricFormat.speed(value)).font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
