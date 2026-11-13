import Foundation
import Combine

enum StatusDisplay: String, CaseIterable, Identifiable {
    case light, cpu, memory, network
    var id: String { rawValue }
    var title: String {
        switch self {
        case .light: return "仅红绿灯"
        case .cpu: return "红绿灯 + CPU"
        case .memory: return "红绿灯 + 内存"
        case .network: return "红绿灯 + 网速"
        }
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()
    private let defaults: UserDefaults
    @Published var showCPU: Bool { didSet { defaults.set(showCPU, forKey: "showCPU") } }
    @Published var showMemory: Bool { didSet { defaults.set(showMemory, forKey: "showMemory") } }
    @Published var showDisk: Bool { didSet { defaults.set(showDisk, forKey: "showDisk") } }
    @Published var showNetwork: Bool { didSet { defaults.set(showNetwork, forKey: "showNetwork") } }
    @Published var showBattery: Bool { didSet { defaults.set(showBattery, forKey: "showBattery") } }
    @Published var showProcesses: Bool { didSet { defaults.set(showProcesses, forKey: "showProcesses") } }
    @Published var showEnergyWarning: Bool { didSet { defaults.set(showEnergyWarning, forKey: "showEnergyWarning") } }
    @Published var energyThreshold: Double { didSet { defaults.set(energyThreshold, forKey: "energyThreshold") } }
    @Published var refreshInterval: Double { didSet { defaults.set(refreshInterval, forKey: "refreshInterval") } }
    @Published var statusDisplay: StatusDisplay { didSet { defaults.set(statusDisplay.rawValue, forKey: "statusDisplay") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showCPU = defaults.object(forKey: "showCPU") as? Bool ?? true
        showMemory = defaults.object(forKey: "showMemory") as? Bool ?? true
        showDisk = defaults.object(forKey: "showDisk") as? Bool ?? true
        showNetwork = defaults.object(forKey: "showNetwork") as? Bool ?? true
        showBattery = defaults.object(forKey: "showBattery") as? Bool ?? true
        showProcesses = defaults.object(forKey: "showProcesses") as? Bool ?? true
        showEnergyWarning = defaults.object(forKey: "showEnergyWarning") as? Bool ?? true
        let threshold = defaults.object(forKey: "energyThreshold") as? Double ?? 20
        energyThreshold = threshold.isFinite ? min(80, max(5, threshold)) : 20
        let interval = defaults.double(forKey: "refreshInterval")
        refreshInterval = [1.0, 2.0, 5.0].contains(interval) ? interval : 2
        statusDisplay = StatusDisplay(rawValue: defaults.string(forKey: "statusDisplay") ?? "") ?? .cpu
    }
}
