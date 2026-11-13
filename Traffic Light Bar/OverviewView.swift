import SwiftUI

struct OverviewView: View {
    @ObservedObject var monitor: SystemMonitor
    private var stats: SystemStats { monitor.stats }
    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                StatusHeader(stats: stats, paused: monitor.isPaused)
                HStack(spacing: 6) {
                    Text("\(ProcessInfo.processInfo.activeProcessorCount) 核 CPU")
                    Text("·")
                    Text("\(MetricFormat.bytes(ProcessInfo.processInfo.physicalMemory)) 内存")
                    Spacer()
                    if let time = stats.sampledAt {
                        Text("更新于 \(time.formatted(date: .omitted, time: .standard))")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                if !stats.unavailableMetrics.isEmpty {
                    Label("部分数据暂不可用：\(stats.unavailableMetrics.joined(separator: "、"))", systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: columns, spacing: 16) {
                    MonitorCard {
                        resourceHeader("CPU", icon: "cpu", color: MonitorStyle.cpu,
                                       value: MetricFormat.percent(stats.cpuUsage), detail: "总处理能力占用")
                        HistoryChart(samples: monitor.history, keyPath: \.cpu, color: MonitorStyle.cpu)
                            .frame(height: 108).padding(.top, 14)
                    }
                    MonitorCard {
                        resourceHeader("内存", icon: "memorychip", color: MonitorStyle.memory,
                                       value: stats.memoryTotal > 0 ? MetricFormat.percent(stats.memoryRatio * 100) : "—",
                                       detail: stats.memoryTotal > 0 ? "\(MetricFormat.bytes(stats.memoryUsed)) / \(MetricFormat.bytes(stats.memoryTotal))" : "暂不可用")
                        HistoryChart(samples: monitor.history, keyPath: \.memory, color: MonitorStyle.memory)
                            .frame(height: 108).padding(.top, 14)
                    }
                }
                MonitorCard {
                    SectionCaption(title: "网络活动", detail: "最近 5 分钟")
                    HStack(alignment: .top) {
                        networkMetric("下载", symbol: "arrow.down", speed: stats.networkDownload,
                                      total: stats.sessionDownload, color: MonitorStyle.download)
                        Spacer()
                        networkMetric("上传", symbol: "arrow.up", speed: stats.networkUpload,
                                      total: stats.sessionUpload, color: MonitorStyle.upload)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 7) {
                            Label(stats.interfaceName.map { "\($0) · 已连接" } ?? "未连接", systemImage: "network")
                            if let ip = stats.localIP {
                                Button { AppActions.copy(ip) } label: { Label(ip, systemImage: "doc.on.doc") }
                                    .buttonStyle(.plain).help("复制本机 IP 地址")
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.top, 12)
                    HistoryChart(samples: monitor.history, keyPath: \.download, color: MonitorStyle.download,
                                 secondaryKeyPath: \.upload, percentage: false)
                        .frame(height: 116).padding(.top, 16)
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    MonitorCard {
                        SectionCaption(title: "内存详情", detail: stats.memoryPressure.title)
                        VStack(spacing: 12) {
                            detail("已压缩", value: stats.memoryTotal > 0 ? MetricFormat.bytes(stats.memoryCompressed) : "—")
                            detail("已用交换", value: stats.swapUsed.map(MetricFormat.bytes) ?? "—")
                            detail("内存压力", value: stats.memoryPressure.title, color: stats.memoryPressure.level.color)
                        }
                        .padding(.top, 14)
                    }
                    MonitorCard {
                        SectionCaption(title: "磁盘空间", detail: "启动磁盘")
                        Text(stats.diskTotal > 0 ? "\(MetricFormat.bytes(stats.diskTotal - stats.diskUsed)) 可用" : "暂不可用")
                            .font(.system(size: 21, weight: .semibold, design: .rounded)).padding(.top, 12)
                        UsageBar(ratio: stats.diskRatio, color: stats.diskRatio >= 0.9 ? .orange : .secondary)
                            .padding(.vertical, 9)
                        Text(stats.diskTotal > 0 ? "已用 \(MetricFormat.bytes(stats.diskUsed)) / \(MetricFormat.bytes(stats.diskTotal))" : "无法读取容量")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if stats.batteryPresent {
                    MonitorCard {
                        HStack(spacing: 16) {
                            BatteryIcon(percent: stats.batteryLevel ?? 0, charging: stats.batteryCharging == true)
                                .frame(width: 40, height: 20).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(stats.batteryStatus).font(.subheadline.weight(.medium))
                                if let time = stats.batteryTimeRemaining {
                                    Text("\(stats.batteryCharging == true ? "预计充满" : "预计可用") \(time)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(MetricFormat.percent(stats.batteryLevel))
                                .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                        }
                    }
                }
                Text("趋势保留最近 5 分钟，暂停期间留空。内存占用与系统内存压力分别显示；磁盘容量不参与负载判断。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(26)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("系统概览")
    }

    private func resourceHeader(_ title: String, icon: String, color: Color, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(color)
            Text(value).font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
    private func networkMetric(_ title: String, symbol: String, speed: Double?, total: UInt64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(color)
            Text(MetricFormat.speed(speed)).font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit()
            Text("本次累计 \(MetricFormat.bytes(total))").font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
    private func detail(_ title: String, value: String, color: Color = .primary) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(color).monospacedDigit()
        }
        .font(.caption)
    }
}
