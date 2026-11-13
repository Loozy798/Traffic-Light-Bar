import Foundation

enum ResourceLevel: Int, Comparable, Sendable {
    case unknown, normal, busy, critical
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    var title: String {
        switch self {
        case .unknown: return "正在采样"
        case .normal: return "运行流畅"
        case .busy: return "负载较高"
        case .critical: return "资源紧张"
        }
    }
    static func cpu(_ percent: Double) -> Self {
        percent >= 80 ? .critical : percent >= 50 ? .busy : .normal
    }
}

enum MemoryPressure: Sendable {
    case unknown, normal, warning, critical
    var title: String {
        switch self {
        case .unknown: return "压力未知"
        case .normal: return "压力正常"
        case .warning: return "压力较高"
        case .critical: return "压力严重"
        }
    }
    var level: ResourceLevel {
        switch self {
        case .unknown: return .unknown
        case .normal: return .normal
        case .warning: return .busy
        case .critical: return .critical
        }
    }
}

struct SystemStats: Sendable {
    var sampledAt: Date?
    var cpuUsage: Double?
    var memoryTotal: UInt64 = 0
    var memoryUsed: UInt64 = 0
    var memoryCompressed: UInt64 = 0
    var swapUsed: UInt64?
    var memoryPressure: MemoryPressure = .unknown
    var thermalLevel: ResourceLevel = .normal
    var diskTotal: UInt64 = 0
    var diskUsed: UInt64 = 0
    var networkDownload: Double?
    var networkUpload: Double?
    var sessionDownload: UInt64 = 0
    var sessionUpload: UInt64 = 0
    var localIP: String?
    var interfaceName: String?
    var batteryPresent = false
    var batteryLevel: Double?
    var batteryCharging: Bool?
    var batteryOnAC = false
    var batteryTimeRemaining: String?
    var unavailableMetrics: [String] = []

    var memoryRatio: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }
    var diskRatio: Double { diskTotal > 0 ? Double(diskUsed) / Double(diskTotal) : 0 }
    var level: ResourceLevel {
        // Capacity is not pressure. A nearly full disk does not imply a busy CPU.
        let signal = max(cpuUsage.map(ResourceLevel.cpu) ?? .unknown, memoryPressure.level, thermalLevel)
        return cpuUsage == nil && signal <= .normal ? .unknown : signal
    }
    var summary: String {
        if thermalLevel >= .busy { return "系统温度较高，正在限制性能" }
        if memoryPressure.level >= .busy { return "内存压力较高，建议关闭暂不用的应用" }
        if let cpuUsage, cpuUsage >= 80 { return "CPU 持续忙碌，可查看高占用进程" }
        if let cpuUsage, cpuUsage >= 50 { return "CPU 正在处理较多任务" }
        if level == .unknown { return "等待有效采样，数据将在片刻后显示" }
        if diskRatio >= 0.9 { return "磁盘剩余空间不足 10%，建议整理文件" }
        return memoryPressure == .unknown ? "CPU 负载正常 · 内存压力暂不可用" : "CPU 与内存压力正常"
    }
    var batteryStatus: String {
        if batteryCharging == true { return "正在充电" }
        if batteryOnAC { return (batteryLevel ?? 0) >= 99 ? "已充满 · 电源供电" : "电源供电 · 未充电" }
        return "电池供电"
    }
}

struct MetricSample: Identifiable, Sendable {
    let id: Date
    var segment: Int = 0
    let cpu: Double?
    let memory: Double?
    let download: Double?
    let upload: Double?
}
