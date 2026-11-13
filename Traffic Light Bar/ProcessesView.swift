import SwiftUI

struct ProcessesView: View {
    @ObservedObject var monitor: EnergyMonitor
    @ObservedObject var preferences: AppPreferences
    var isPaused: Bool
    @State private var query = ""
    @State private var sort: Sort = .cpu
    enum Sort: String, CaseIterable, Identifiable {
        case cpu = "CPU", memory = "内存"
        var id: String { rawValue }
    }
    private var processes: [AppEnergyInfo] {
        monitor.topConsumers
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || String($0.id).contains(query) }
            .sorted {
                let left = sort == .cpu ? $0.cpuPercent : Double($0.memoryBytes)
                let right = sort == .cpu ? $1.cpuPercent : Double($1.memoryBytes)
                return left == right ? $0.id < $1.id : left > right
            }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("找到资源占用的来源").font(.title2.weight(.semibold))
                    Text(isPaused ? "已暂停 · 显示最后一次采样" : "CPU 与驻留内存 · 每 5 秒更新")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { AppActions.openActivityMonitor() } label: { Label("活动监视器", systemImage: "arrow.up.right.square") }
            }
            if preferences.showEnergyWarning && monitor.hasHighConsumer {
                Label("有进程的 CPU 超过 \(Int(preferences.energyThreshold))%，可能影响响应与续航。", systemImage: "exclamationmark.circle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.08), in: .rect(cornerRadius: 10))
            }
            HStack(spacing: 12) {
                TextField("搜索进程名称或 PID", text: $query)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("搜索进程名称或 PID")
                Picker("排序", selection: $sort) {
                    ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 150)
            }
            if let error = monitor.errorMessage {
                ContentUnavailableView {
                    Label("无法读取进程", systemImage: "lock.shield")
                } description: {
                    Text(error)
                } actions: {
                    Button("打开活动监视器") { AppActions.openActivityMonitor() }
                }
            } else if monitor.lastUpdated == nil {
                VStack(spacing: 12) { ProgressView(); Text("正在采样进程…").foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if processes.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                HStack {
                    Text("进程").frame(maxWidth: .infinity, alignment: .leading)
                    Text("CPU").frame(width: 84, alignment: .trailing)
                    Text("内存").frame(width: 100, alignment: .trailing)
                }
                .font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.horizontal, 12)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(processes) { process in
                            ProcessRow(process: process, threshold: preferences.showEnergyWarning ? preferences.energyThreshold : .infinity)
                            Divider().padding(.leading, 46)
                        }
                    }
                }
                .background(.primary.opacity(0.025), in: .rect(cornerRadius: 12))
            }
            HStack {
                Text("CPU 以单核心 100% 计，多线程进程可超过 100%；这些数值不等同于能耗。")
                Spacer(minLength: 8)
                if monitor.lastUpdated != nil { Text("\(monitor.topConsumers.count) 个进程") }
            }
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(26)
        .navigationTitle("进程排行")
    }
}

private struct ProcessRow: View {
    let process: AppEnergyInfo
    let threshold: Double
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "app.dashed").font(.title3).foregroundStyle(.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(process.name).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Text("PID \(String(process.id))").font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "%.1f%%", process.cpuPercent))
                .foregroundStyle(process.cpuPercent >= threshold ? .orange : .primary)
                .frame(width: 84, alignment: .trailing)
            Text(MetricFormat.bytes(process.memoryBytes)).frame(width: 100, alignment: .trailing)
        }
        .font(.callout).monospacedDigit()
        .padding(12)
        .help(process.executablePath)
        .contextMenu {
            Button("复制进程名称") { AppActions.copy(process.name) }
            Button("复制 PID") { AppActions.copy(String(process.id)) }
            Button("打开活动监视器") { AppActions.openActivityMonitor() }
        }
        .accessibilityElement(children: .combine)
    }
}
