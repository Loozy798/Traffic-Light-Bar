import Foundation
import Darwin
import IOKit.ps

/// Only accessed on SystemMonitor's serial sampling queue.
final class SystemSampler: @unchecked Sendable {
    private let host = mach_host_self()
    private var previousCPU: CPUTicks?
    private var network = NetworkTracker()
    private var cachedDisk: (total: UInt64, used: UInt64) = (0, 0)
    private var lastDiskUpdate: TimeInterval = -60

    deinit { mach_port_deallocate(mach_task_self_, host) }

    func resetBaseline() {
        previousCPU = nil
        network.resetBaseline()
        lastDiskUpdate = -60
    }

    func collect() -> SystemStats {
        var stats = SystemStats()
        stats.sampledAt = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        if let ticks = cpuTicks() {
            stats.cpuUsage = ticks.usage(since: previousCPU)
            previousCPU = ticks
        } else {
            previousCPU = nil
            stats.unavailableMetrics.append("CPU")
        }
        collectMemory(into: &stats)
        if uptime - lastDiskUpdate >= 30 {
            cachedDisk = diskCapacity()
            lastDiskUpdate = uptime
        }
        stats.diskTotal = cachedDisk.total
        stats.diskUsed = cachedDisk.used
        if stats.diskTotal == 0 { stats.unavailableMetrics.append("磁盘") }
        collectNetwork(into: &stats, uptime: uptime)
        collectBattery(into: &stats)
        switch ProcessInfo.processInfo.thermalState {
        case .nominal, .fair: stats.thermalLevel = .normal
        case .serious: stats.thermalLevel = .busy
        case .critical: stats.thermalLevel = .critical
        @unknown default: stats.thermalLevel = .unknown
        }
        return stats
    }

    private func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1,
                        idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }

    private func collectMemory(into stats: inout SystemStats) {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            stats.memoryTotal = ProcessInfo.processInfo.physicalMemory
            let pageSize = UInt64(vm_kernel_page_size)
            let resident = UInt64(info.active_count) + UInt64(info.inactive_count)
                + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
            let reclaimable = UInt64(info.purgeable_count) + UInt64(info.external_page_count)
            stats.memoryUsed = min(stats.memoryTotal, (resident > reclaimable ? resident - reclaimable : 0) * pageSize)
            stats.memoryCompressed = UInt64(info.compressor_page_count) * pageSize
        } else {
            stats.unavailableMetrics.append("内存")
        }
        var pressure: Int32 = 0
        var size = MemoryLayout.size(ofValue: pressure)
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &size, nil, 0) == 0 {
            switch pressure {
            case 1: stats.memoryPressure = .normal
            case 2: stats.memoryPressure = .warning
            case 4: stats.memoryPressure = .critical
            default: stats.memoryPressure = .unknown
            }
        }
        var swap = xsw_usage()
        size = MemoryLayout.size(ofValue: swap)
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 { stats.swapUsed = swap.xsu_used }
    }

    private func diskCapacity() -> (UInt64, UInt64) {
        // The APFS data volume shares capacity with the startup volume.
        let url = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        if let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
           let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacityForImportantUsage, total > 0 {
            let capacity = UInt64(total)
            let free = min(capacity, UInt64(max(0, available)))
            return (capacity, capacity - free)
        }
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let total = (attrs[.systemSize] as? NSNumber)?.uint64Value,
              let free = (attrs[.systemFreeSize] as? NSNumber)?.uint64Value, total > 0 else { return (0, 0) }
        return (total, total - min(total, free))
    }

    private func collectNetwork(into stats: inout SystemStats, uptime: TimeInterval) {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else {
            stats.unavailableMetrics.append("网络")
            return
        }
        defer { freeifaddrs(first) }
        var addresses: [String: String] = [:]
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let item = pointer.pointee
            guard let addr = item.ifa_addr, let namePointer = item.ifa_name else { continue }
            let name = String(cString: namePointer)
            let flags = Int32(item.ifa_flags)
            // en interfaces are physical Ethernet / Wi-Fi, excluding VPN and peer-to-peer duplication.
            guard name.hasPrefix("en"), flags & IFF_UP != 0, flags & IFF_RUNNING != 0,
                  flags & IFF_LOOPBACK == 0 else { continue }
            if addr.pointee.sa_family == UInt8(AF_INET) || addr.pointee.sa_family == UInt8(AF_INET6) {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let address = String(cString: buffer)
                    // Prefer IPv4; IPv6-only links remain usable. Ignore link-local IPv6 addresses.
                    if !address.hasPrefix("fe80:"), addresses[name] == nil || addr.pointee.sa_family == UInt8(AF_INET) {
                        addresses[name] = address
                    }
                }
            }
        }
        // Keep only addressed links; a running but disconnected interface is not a live network.
        guard let allCounters = NetworkCounterReader.read() else {
            stats.unavailableMetrics.append("网络速率")
            network.resetBaseline()
            return
        }
        let counters = allCounters.filter { addresses[$0.key] != nil }
        let rate = network.sample(counters: counters, uptime: uptime)
        stats.networkDownload = rate.download
        stats.networkUpload = rate.upload
        stats.sessionDownload = rate.sessionDownload
        stats.sessionUpload = rate.sessionUpload
        if let name = addresses.keys.sorted().first {
            stats.interfaceName = name
            stats.localIP = addresses[name]
        }
    }

    private func collectBattery(into stats: inout SystemStats) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  description[kIOPSIsPresentKey] as? Bool == true else { continue }
            stats.batteryPresent = true
            if let current = description[kIOPSCurrentCapacityKey] as? NSNumber,
               let maximum = description[kIOPSMaxCapacityKey] as? NSNumber, maximum.doubleValue > 0 {
                stats.batteryLevel = min(100, max(0, current.doubleValue / maximum.doubleValue * 100))
            }
            stats.batteryCharging = description[kIOPSIsChargingKey] as? Bool
            stats.batteryOnAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let key = stats.batteryCharging == true ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            if let minutes = description[key] as? Int, minutes > 0 {
                stats.batteryTimeRemaining = "\(minutes / 60) 小时 \(minutes % 60) 分钟"
            }
            return
        }
    }
}
