import Foundation
import Darwin

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

        var ifaddrsPtr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddrsPtr) == 0, let firstAddr = ifaddrsPtr {
            var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
            while let cur = ptr {
                let name = String(cString: cur.pointee.ifa_name)
                // Exclude loopback
                if !name.hasPrefix("lo"), let data = cur.pointee.ifa_data {
                    let ifData = data.assumingMemoryBound(to: if_data.self)
                    totalIn += UInt64(ifData.pointee.ifi_ibytes)
                    totalOut += UInt64(ifData.pointee.ifi_obytes)
                }
                ptr = cur.pointee.ifa_next
            }
            freeifaddrs(firstAddr)
        }

        let now = Date()
        var downPerSec: Double = 0
        var upPerSec: Double = 0

        if let prevTime = previousTimestamp {
            let deltaSec = now.timeIntervalSince(prevTime)
            if deltaSec > 0.05 {
                let inDelta = totalIn >= previousInBytes ? Double(totalIn - previousInBytes) : 0
                let outDelta = totalOut >= previousOutBytes ? Double(totalOut - previousOutBytes) : 0
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
}
