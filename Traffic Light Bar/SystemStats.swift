import Foundation

struct SystemStats {
    // CPU
    var cpuUsage: Double = 0
    var cpuTemperature: Double?
    
    // 内存
    var memoryTotal: UInt64 = 0
    var memoryUsed: UInt64 = 0
    
    // 磁盘
    var diskTotal: UInt64 = 0
    var diskUsed: UInt64 = 0
    
    // 网络
    var networkDownload: Double = 0
    var networkUpload: Double = 0
    var localIP: String = "0.0.0.0"
    
    // 电池
    var batteryPresent: Bool = false
    var batteryLevel: Double?
    var batteryCharging: Bool?
    var batteryTimeRemaining: String?
}
