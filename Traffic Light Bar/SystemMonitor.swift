import Foundation
import SwiftUI
import Combine
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
    
    /// 取消并重新启动监控循环（唤醒后调用）
    func restart() {
        updateTask?.cancel()
        // 重置网络差值，避免唤醒后出现离谱的速率峰值
        lastNetworkDownload   = 0
        lastNetworkUpload     = 0
        lastNetworkUpdateTime = 0
        startMonitoring()
    }

    private func startMonitoring() {
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                // ✅ 关键修复：所有采样都在 global 队列执行
                // 避免 Mach 端口调用在唤醒瞬间阻塞 Swift 协作线程池
                let newStats = await withCheckedContinuation {
                    (cont: CheckedContinuation<SystemStats, Never>) in
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        cont.resume(returning: self?.collectStats() ?? SystemStats())
                    }
                }
                guard !Task.isCancelled else { break }
                await MainActor.run { [weak self] in
                    self?.stats = newStats
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 秒
            }
        }
    }

    // MARK: - 全部采集（在 global 队列上运行，不阻塞协作池）

    private func collectStats() -> SystemStats {
        var s = SystemStats()
        s.cpuUsage        = getCPUUsage()
        s.cpuTemperature  = nil

        let (memT, memU) = getMemoryInfo()
        s.memoryTotal = memT; s.memoryUsed = memU

        let (diskT, diskU) = getDiskInfo()
        s.diskTotal = diskT; s.diskUsed = diskU

        let (down, up) = getNetworkUsage()
        s.networkDownload = down; s.networkUpload = up
        s.localIP = getLocalIP()

        let (bp, bl, bc, br) = getBatteryInfo()
        s.batteryPresent = bp; s.batteryLevel = bl
        s.batteryCharging = bc; s.batteryTimeRemaining = br

        return s
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
            // 唤醒后 timeDiff 可能很大，跳过第一次差值
            if timeDiff > 0 && timeDiff < 10 {
                downPerSec = Double(totalDownload &- lastNetworkDownload) / timeDiff
                upPerSec = Double(totalUpload &- lastNetworkUpload) / timeDiff
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
        let timeRemaining = ps[kIOPSTimeToEmptyKey] as? Int ?? 0
        
        var remainingStr: String?
        if timeRemaining > 0 {
            let hours = timeRemaining / 60
            let minutes = timeRemaining % 60
            remainingStr = String(format: "%d:%02d", hours, minutes)
        }
        
        return (true, level, isCharging, remainingStr)
    }
}
