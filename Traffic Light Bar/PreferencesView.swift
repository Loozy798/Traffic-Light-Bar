import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var loginItem: LoginItemManager
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section("常规") {
                Picker("状态栏显示", selection: $preferences.statusDisplay) {
                    ForEach(StatusDisplay.allCases) { Text($0.title).tag($0) }
                }
                Picker("刷新间隔", selection: $preferences.refreshInterval) {
                    Text("1 秒 · 更实时").tag(1.0)
                    Text("2 秒 · 均衡").tag(2.0)
                    Text("5 秒 · 更省电").tag(5.0)
                }
                Toggle("登录时启动", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
                if loginItem.needsApproval {
                    HStack {
                        Text("需要在系统设置中允许登录启动").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("前往系统设置") { loginItem.openSystemSettings() }
                    }
                }
                if let error = loginItem.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                Toggle("CPU 使用率", isOn: $preferences.showCPU)
                Toggle("内存使用", isOn: $preferences.showMemory)
                Toggle("磁盘空间", isOn: $preferences.showDisk)
                Toggle("网络速度与 IP", isOn: $preferences.showNetwork)
                Toggle("电池状态", isOn: $preferences.showBattery)
                Toggle("高占用进程摘要", isOn: $preferences.showProcesses)
            } header: { Text("弹窗显示项目") }
            footer: { Text("电池仅在内置电池存在时显示；详细仪表盘始终保留完整指标。") }
            Section {
                Toggle("标记高 CPU 占用进程", isOn: $preferences.showEnergyWarning)
                HStack {
                    Text("提醒阈值")
                    Slider(value: $preferences.energyThreshold, in: 5...80, step: 5)
                        .disabled(!preferences.showEnergyWarning)
                    Text("\(Int(preferences.energyThreshold))%")
                        .monospacedDigit().foregroundStyle(.secondary).frame(width: 42)
                }
            } header: { Text("进程提醒") }
            footer: { Text("提醒显示在应用内。进程以单核心 100% 计，按需每 5 秒读取；系统权限受限时会明确提示。") }
            Section("关于") {
                LabeledContent("Traffic Light Bar", value: "2.0")
                Text("绿灯：CPU 低于 50%，内存压力正常。黄灯：CPU 达到 50% 或内存 / 温控压力较高。红灯：CPU 达到 80% 或系统压力严重。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("数据留在本机，趋势只保存在内存中，退出即清除。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 510, height: 650)
        .navigationTitle("偏好设置")
        .onAppear { loginItem.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { loginItem.refresh() } }
    }
}
