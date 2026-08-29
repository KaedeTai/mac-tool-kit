import Foundation
import Darwin

public enum NetworkCounterDelta {
    public static func bytes(current: UInt64, previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }
}

public final class NetworkMonitor: @unchecked Sendable {
    private var previousInBytes: UInt64 = 0
    private var previousOutBytes: UInt64 = 0
    private var previousTimestamp: Date?
    private let lock = NSLock()

    public init() {}

    public func sample() -> NetworkIOSnapshot {
        lock.lock()
        defer { lock.unlock() }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        (totalIn, totalOut) = readInterfaceCounters64()

        let now = Date()
        var downPerSec: Double = 0
        var upPerSec: Double = 0

        if let prevTime = previousTimestamp {
            let deltaSec = now.timeIntervalSince(prevTime)
            if deltaSec > 0.05 {
                let inDelta = Double(NetworkCounterDelta.bytes(current: totalIn, previous: previousInBytes))
                let outDelta = Double(NetworkCounterDelta.bytes(current: totalOut, previous: previousOutBytes))
                downPerSec = inDelta / deltaSec
                upPerSec = outDelta / deltaSec
            }
        }

        previousInBytes = totalIn
        previousOutBytes = totalOut
        previousTimestamp = now

        return NetworkIOSnapshot(
            uploadBytesPerSec: upPerSec,
            downloadBytesPerSec: downPerSec,
            totalUploadBytes: totalOut,
            totalDownloadBytes: totalIn,
            timestamp: now
        )
    }

    private func readInterfaceCounters64() -> (UInt64, UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            return (0, 0)
        }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else {
            return (0, 0)
        }

        var input: UInt64 = 0
        var output: UInt64 = 0
        var offset = 0
        while offset + MemoryLayout<if_msghdr>.size <= length {
            let messageLength: Int = buffer.withUnsafeBytes { raw in
                Int(raw.baseAddress!.advanced(by: offset).assumingMemoryBound(to: if_msghdr.self).pointee.ifm_msglen)
            }
            guard messageLength > 0, offset + messageLength <= length else { break }
            buffer.withUnsafeBytes { raw in
                let base = raw.baseAddress!.advanced(by: offset)
                let header = base.assumingMemoryBound(to: if_msghdr.self).pointee
                if header.ifm_type == UInt8(RTM_IFINFO2), messageLength >= MemoryLayout<if_msghdr2>.size {
                    let info = base.assumingMemoryBound(to: if_msghdr2.self).pointee
                    if (info.ifm_flags & IFF_LOOPBACK) == 0 {
                        input += info.ifm_data.ifi_ibytes
                        output += info.ifm_data.ifi_obytes
                    }
                }
            }
            offset += messageLength
        }
        return (input, output)
    }
}
