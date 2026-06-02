import Foundation
import Combine

class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    @Published var showCPU: Bool {
        didSet { UserDefaults.standard.set(showCPU, forKey: "showCPU") }
    }
    @Published var showMemory: Bool {
        didSet { UserDefaults.standard.set(showMemory, forKey: "showMemory") }
    }
    @Published var showDisk: Bool {
        didSet { UserDefaults.standard.set(showDisk, forKey: "showDisk") }
    }
    @Published var showNetwork: Bool {
        didSet { UserDefaults.standard.set(showNetwork, forKey: "showNetwork") }
    }
    @Published var showBattery: Bool {
        didSet { UserDefaults.standard.set(showBattery, forKey: "showBattery") }
    }
    @Published var showEnergyWarning: Bool {
        didSet { UserDefaults.standard.set(showEnergyWarning, forKey: "showEnergyWarning") }
    }
    @Published var energyThreshold: Double {
        didSet { UserDefaults.standard.set(energyThreshold, forKey: "energyThreshold") }
    }

    private init() {
        let ud = UserDefaults.standard
        // 直接内联读取，避免局部函数捕获 self 导致编译错误
        showCPU           = ud.object(forKey: "showCPU")           as? Bool   ?? true
        showMemory        = ud.object(forKey: "showMemory")        as? Bool   ?? true
        showDisk          = ud.object(forKey: "showDisk")          as? Bool   ?? true
        showNetwork       = ud.object(forKey: "showNetwork")       as? Bool   ?? true
        showBattery       = ud.object(forKey: "showBattery")       as? Bool   ?? true
        showEnergyWarning = ud.object(forKey: "showEnergyWarning") as? Bool   ?? true
        energyThreshold   = ud.object(forKey: "energyThreshold")   as? Double ?? 20.0
    }
}
