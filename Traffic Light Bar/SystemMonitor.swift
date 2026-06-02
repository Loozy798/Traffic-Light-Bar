import Foundation
import SwiftUI
import IOKit
import IOKit.ps

class SystemMonitor: ObservableObject {
    @Published var stats = SystemStats()
    private var updateTask: Task<Void, Never>?
    
    // 网络统计临时变量
    private var lastNetworkDownload: UInt64 = 0
    private var lastNetworkUpload: UInt64 = 0
    private var lastNetworkUpdateTime: TimeInterval = 0
    
    init() {
        startMonitoring()
    }
    
    deinit {
        updateTask?.cancel()
    }
    
    private func startMonitoring() {
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.updateAllStats()
                try? await Task.sleep(nanoseconds: 1 * 1_000_000_000) // 每秒更新一次
            }
        }
    }
    
    private func updateAllStats() async {
        var newStats = SystemStats()
        
        // 采集CPU使用率
        newStats.cpuUsage = getCPUUsage()
        // 采集CPU温度（需要SMC访问权限，示例默认返回nil）
        newStats.cpuTemperature = nil
        
        // 采集内存
        let (memTotal, memUsed) = getMemoryInfo()
        newStats.memoryTotal = memTotal
        newStats.memoryUsed = memUsed
        
        // 采集磁盘
        let (diskTotal, diskUsed) = getDiskInfo()
        newStats.diskTotal = diskTotal
        newStats.diskUsed = diskUsed
        
        // 采集网络
        let (down, up) = getNetworkUsage()
        newStats.networkDownload = down
        newStats.networkUpload = up
        newStats.localIP = getLocalIP()
        
        // 采集电池
        let (batteryPresent, level, charging, remaining) = getBatteryInfo()
        newStats.batteryPresent = batteryPresent
        newStats.batteryLevel = level
        newStats.batteryCharging = charging
        newStats.batteryTimeRemaining = remaining
        
        await MainActor.run {
            self.stats = newStats
        }
    }
    
    // MARK: - 各数据采集实现
    private func getCPUUsage() -> Double {
        var cpuLoad = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        
        let kr = withUnsafeMutablePointer(to: &cpuLoad) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        
        guard kr == KERN_SUCCESS else { return 0 }
        
        let user = Double(cpuLoad.cpu_ticks.0)
        let system = Double(cpuLoad.cpu_ticks.1)
        let idle = Double(cpuLoad.cpu_ticks.2)
        let total = user + system + idle
        
        return total > 0 ? ((user + system) / total) * 100 : 0
    }
    
    private func getMemoryInfo() -> (total: UInt64, used: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        
        var vmStats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        
        let kr = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        guard kr == KERN_SUCCESS else { return (total, 0) }
        
        let pageSize = UInt64(vm_kernel_page_size)
        let used = UInt64(vmStats.active_count + vmStats.wire_count + vmStats.compressor_page_count) * pageSize
        
        return (total, used)
    }
    
    private func getDiskInfo() -> (total: UInt64, used: UInt64) {
        let fileManager = FileManager.default
        guard let attrs = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()) else { return (0, 0) }
        
        let total = attrs[.systemSize] as? UInt64 ?? 0
        let free = attrs[.systemFreeSize] as? UInt64 ?? 0
        return (total, total - free)
    }
    
    private func getNetworkUsage() -> (down: Double, up: Double) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }
        
        var totalDownload: UInt64 = 0
        var totalUpload: UInt64 = 0
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING),
                  ptr.pointee.ifa_addr.pointee.sa_family == AF_LINK else { continue }
            
            let data = unsafeBitCast(ptr.pointee.ifa_data, to: UnsafeMutablePointer<if_data>.self)
            totalDownload += UInt64(data.pointee.ifi_ibytes)
            totalUpload += UInt64(data.pointee.ifi_obytes)
        }
        
        let now = Date.timeIntervalSinceReferenceDate
        var downPerSec: Double = 0
        var upPerSec: Double = 0
        
        if lastNetworkUpdateTime > 0 {
            let timeDiff = now - lastNetworkUpdateTime
            if timeDiff > 0 {
                downPerSec = Double(totalDownload - lastNetworkDownload) / timeDiff
                upPerSec = Double(totalUpload - lastNetworkUpload) / timeDiff
            }
        }
        
        lastNetworkDownload = totalDownload
        lastNetworkUpload = totalUpload
        lastNetworkUpdateTime = now
        
        return (downPerSec, upPerSec)
    }
    
    private func getLocalIP() -> String {
        var address: String = "0.0.0.0"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return address }
        defer { freeifaddrs(ifaddr) }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addrFamily = ptr.pointee.ifa_addr.pointee.sa_family
            
            guard (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING),
                  addrFamily == UInt8(AF_INET) else { continue }
            
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                           &hostname, socklen_t(hostname.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                address = String(cString: hostname)
                break
            }
        }
        return address
    }
    
    private func getBatteryInfo() -> (present: Bool, level: Double?, charging: Bool?, remaining: String?) {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
        
        guard let ps = sources.first as? [String: Any] else { return (false, nil, nil, nil) }
        
        let present = ps[kIOPSIsPresentKey] as? Bool ?? false
        guard present else { return (false, nil, nil, nil) }
        
        let level = ps[kIOPSCurrentCapacityKey] as? Double
        let isCharging = ps[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        let timeRemaining = ps[kIOPSTimeRemainingKey] as? Int ?? 0
        
        var remainingStr: String?
        if timeRemaining > 0 {
            let hours = timeRemaining / 60
            let minutes = timeRemaining % 60
            remainingStr = String(format: "%d:%02d", hours, minutes)
        }
        
        return (true, level, isCharging, remainingStr)
    }
}
