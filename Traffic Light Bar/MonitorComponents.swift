import SwiftUI
import Charts

extension ResourceLevel {
    var color: Color {
        switch self {
        case .unknown: return .secondary
        case .normal: return .green
        case .busy: return .orange
        case .critical: return .red
        }
    }
}

enum MonitorStyle {
    static let cpu = Color.teal
    static let memory = Color.indigo
    static let download = Color.blue
    static let upload = Color.orange
}

struct MonitorCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.035), in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.06)) }
    }
}

struct StatusHeader: View {
    let stats: SystemStats
    let paused: Bool
    var compact = false
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: compact ? 36 : 46, height: compact ? 36 : 46)
                Image(systemName: paused ? "pause.fill" : stats.level == .critical ? "exclamationmark" : "waveform.path.ecg")
                    .font(.system(size: compact ? 15 : 20, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(paused ? "监控已暂停" : stats.level.title)
                    .font(.system(size: compact ? 17 : 25, weight: .semibold, design: .rounded))
                Text(paused ? "当前显示暂停前的数据" : stats.summary)
                    .font(compact ? .caption : .callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if !compact {
                Label(paused ? "已暂停" : "实时监测", systemImage: paused ? "pause.circle" : "circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(color)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(color.opacity(0.1), in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
    }
    private var color: Color { paused ? .secondary : stats.level.color }
}

struct UsageBar: View {
    let ratio: Double
    let color: Color
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.12))
                Capsule().fill(color).frame(width: geometry.size.width * min(1, max(0, ratio)))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

struct SectionCaption: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct CompactMetric: View {
    let title: String
    let icon: String
    let value: String
    let detail: String
    let ratio: Double
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
            UsageBar(ratio: ratio, color: color)
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.065), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

struct HistoryChart: View {
    let samples: [MetricSample]
    let keyPath: KeyPath<MetricSample, Double?>
    let color: Color
    var secondaryKeyPath: KeyPath<MetricSample, Double?>? = nil
    var percentage = true
    var compact = false

    private var end: Date { samples.last?.id ?? Date() }
    private var hasValues: Bool { samples.contains { $0[keyPath: keyPath] != nil } }
    var body: some View {
        Chart {
            ForEach(TrendSeries.points(in: samples, value: keyPath)) { point in
                LineMark(x: .value("时间", point.id), y: .value("数值", point.value), series: .value("分段", "primary-\(point.segment)"))
                    .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: compact ? 1.5 : 2))
            }
            if let secondaryKeyPath {
                ForEach(TrendSeries.points(in: samples, value: secondaryKeyPath)) { point in
                    LineMark(x: .value("时间", point.id), y: .value("数值", point.value), series: .value("分段", "secondary-\(point.segment)"))
                        .foregroundStyle(MonitorStyle.upload).lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
        }
        .chartXScale(domain: end.addingTimeInterval(-300)...end)
        .chartYScale(domain: 0...(percentage ? 100 : max(1024, maximumRate * 1.15)))
        .chartXAxis {
            if !compact {
                AxisMarks(values: .stride(by: .minute)) { _ in
                    AxisValueLabel(format: .dateTime.hour().minute())
                    AxisGridLine().foregroundStyle(.primary.opacity(0.05))
                }
            }
        }
        .chartYAxis {
            if !compact {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(.primary.opacity(0.06))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(percentage ? "\(Int(number))%" : MetricFormat.speed(number)).font(.system(size: 9))
                        }
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .overlay {
            if !hasValues {
                Text("正在收集趋势…").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(percentage ? "最近五分钟使用率趋势" : "最近五分钟网络速度趋势")
        .accessibilityValue(samples.last?[keyPath: keyPath].map { percentage ? MetricFormat.percent($0) : MetricFormat.speed($0) } ?? "等待采样")
    }
    private var maximumRate: Double {
        samples.reduce(0) { current, sample in
            max(current, sample[keyPath: keyPath] ?? 0, secondaryKeyPath.flatMap { sample[keyPath: $0] } ?? 0)
        }
    }
}

struct ProcessSummaryRow: View {
    let process: AppEnergyInfo
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "app.dashed").foregroundStyle(.secondary).frame(width: 20)
            Text(process.name).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Text(String(format: "%.1f%%", process.cpuPercent)).monospacedDigit()
                .foregroundStyle(process.cpuPercent >= 80 ? .orange : .secondary)
        }
        .font(.caption)
        .padding(.vertical, 3)
        .help("\(process.name) · PID \(process.id) · \(MetricFormat.bytes(process.memoryBytes))")
        .accessibilityElement(children: .combine)
    }
}
