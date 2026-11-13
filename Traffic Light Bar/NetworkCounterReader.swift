import Foundation
import Darwin

/// NET_RT_IFLIST2 provides if_data64; getifaddrs' if_data counters wrap at 4 GiB.
enum NetworkCounterReader {
    static func read() -> [String: NetworkCounters]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        // Interfaces may change between the size query and the copy. Retry once.
        for _ in 0..<2 {
            var size = 0
            guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
            var bytes = Data(count: size)
            let result = bytes.withUnsafeMutableBytes { buffer in
                sysctl(&mib, u_int(mib.count), buffer.baseAddress, &size, nil, 0)
            }
            if result != 0 { continue }
            bytes.count = size
            guard let decoded = decodeMessages(bytes) else { return nil }
            var counters: [String: NetworkCounters] = [:]
            for (index, values) in decoded {
                var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                if if_indextoname(index, &name) != nil { counters[String(cString: name)] = values }
            }
            return counters
        }
        return nil
    }

    static func decodeMessages(_ bytes: Data) -> [UInt32: NetworkCounters]? {
        bytes.withUnsafeBytes { buffer in
            var offset = 0
            var counters: [UInt32: NetworkCounters] = [:]
            while offset < buffer.count {
                guard buffer.count - offset >= 4 else { return nil }
                let length = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard length >= 4, length <= buffer.count - offset else { return nil }
                let type = buffer.load(fromByteOffset: offset + 3, as: UInt8.self)
                if type == UInt8(RTM_IFINFO2) {
                    guard length >= MemoryLayout<if_msghdr2>.size else { return nil }
                    let message = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    counters[UInt32(message.ifm_index)] = NetworkCounters(received: message.ifm_data.ifi_ibytes,
                                                                        sent: message.ifm_data.ifi_obytes)
                }
                offset += length
            }
            return counters
        }
    }
}
