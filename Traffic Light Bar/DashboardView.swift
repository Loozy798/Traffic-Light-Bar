import SwiftUI

struct DashboardView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var energyMonitor: EnergyMonitor
    @ObservedObject var preferences: AppPreferences
    var onOpenSettings: () -> Void
    @State private var selectedTab: Tab? = .overview

    enum Tab: String, CaseIterable, Identifiable {
        case overview = "系统概览", processes = "进程排行"
        var id: String { rawValue }
        var icon: String { self == .overview ? "square.grid.2x2" : "list.bullet.rectangle" }
    }
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(Tab.allCases, selection: $selectedTab) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab).padding(.vertical, 3)
                }
                .listStyle(.sidebar)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: onOpenSettings) { Label("偏好设置", systemImage: "slider.horizontal.3") }
                        .buttonStyle(.plain).font(.callout)
                    Divider()
                    Text("TRAFFIC LIGHT BAR").font(.system(size: 9, weight: .semibold)).tracking(1)
                    Text("轻量监测 · 一目了然").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(18)
            }
            .navigationSplitViewColumnWidth(min: 165, ideal: 180, max: 210)
        } detail: {
            Group {
                switch selectedTab ?? .overview {
                case .overview: OverviewView(monitor: monitor)
                case .processes: ProcessesView(monitor: energyMonitor, preferences: preferences, isPaused: monitor.isPaused)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItemGroup {
                    Button { monitor.togglePause() } label: {
                        Label(monitor.isPaused ? "恢复监控" : "暂停监控", systemImage: monitor.isPaused ? "play" : "pause")
                    }
                    .help(monitor.isPaused ? "恢复监控" : "暂停监控")
                    Button(action: onOpenSettings) { Label("偏好设置", systemImage: "slider.horizontal.3") }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 820, minHeight: 580)
    }
}
