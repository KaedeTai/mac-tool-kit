import Foundation
import IOKit
import Darwin

public final class DiskMonitor: @unchecked Sendable {
    private var previousReadBytes: UInt64 = 0
    private var previousWriteBytes: UInt64 = 0
    private var previousTimestamp: Date?
    private var cachedVolumes: [DiskVolumeInfo] = []
    private var lastVolumeSampleTime: CFAbsoluteTime = 0
    private let lock = NSLock()

    public init() {}

    public func sampleVolumes() -> [DiskVolumeInfo] {
        lock.lock()
        defer { lock.unlock() }

        let now = CFAbsoluteTimeGetCurrent()
        if now - lastVolumeSampleTime < 5.0 && !cachedVolumes.isEmpty {
            return cachedVolumes
        }

        return autoreleasepool {
            let fileManager = FileManager.default
            let keys: [URLResourceKey] = [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeIsRemovableKey
            ]

            var results: [DiskVolumeInfo] = []
            var seenPaths = Set<String>()

            if let urls = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) {
                for url in urls {
                    guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                    let name = values.volumeName ?? url.lastPathComponent
                    let total = UInt64(values.volumeTotalCapacity ?? 0)
                    let free = UInt64(values.volumeAvailableCapacity ?? 0)
                    guard total > 0 else { continue }

                    seenPaths.insert(url.path)
                    results.append(DiskVolumeInfo(
                        name: name,
                        path: url.path,
                        totalBytes: total,
                        freeBytes: free
                    ))
                }
            }

            // Always ensure the root volume is present.
            if !seenPaths.contains("/") {
                let rootURL = URL(fileURLWithPath: "/")
                if let values = try? rootURL.resourceValues(forKeys: Set(keys)) {
                    let name = values.volumeName ?? "系統磁碟 (/)"
                    let total = UInt64(values.volumeTotalCapacity ?? 0)
                    let free = UInt64(values.volumeAvailableCapacity ?? 0)
                    if total > 0 {
                        results.insert(DiskVolumeInfo(
                            name: name,
                            path: "/",
                            totalBytes: total,
                            freeBytes: free
                        ), at: 0)
                    }
                }
            }

            self.cachedVolumes = results
            self.lastVolumeSampleTime = now
            return results
        }
    }

    public func sampleIO() -> DiskIOSnapshot {
        lock.lock()
        defer { lock.unlock() }

        return autoreleasepool {
            var totalRead: UInt64 = 0
            var totalWrite: UInt64 = 0

            // Query IOBlockStorageDriver statistics
            var iterator: io_iterator_t = 0
            if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS {
                var entry = IOIteratorNext(iterator)
                while entry != 0 {
                    var props: Unmanaged<CFMutableDictionary>?
                    if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                       let dict = props?.takeRetainedValue() as? [String: Any],
                       let stats = dict["Statistics"] as? [String: Any] {
                        if let r = stats["Bytes (Read)"] as? UInt64 {
                            totalRead += r
                        } else if let r = stats["Bytes (Read)"] as? NSNumber {
                            totalRead += r.uint64Value
                        }
                        if let w = stats["Bytes (Write)"] as? UInt64 {
                            totalWrite += w
                        } else if let w = stats["Bytes (Write)"] as? NSNumber {
                            totalWrite += w.uint64Value
                        }
                    }
                    IOObjectRelease(entry)
                    entry = IOIteratorNext(iterator)
                }
                IOObjectRelease(iterator)
            }

            let now = Date()
            var readPerSec: Double = 0
            var writePerSec: Double = 0

            if let prevTime = previousTimestamp {
                let deltaSec = now.timeIntervalSince(prevTime)
                if deltaSec > 0.05 {
                    let rDelta = totalRead >= previousReadBytes ? Double(totalRead - previousReadBytes) : 0
                    let wDelta = totalWrite >= previousWriteBytes ? Double(totalWrite - previousWriteBytes) : 0
                    readPerSec = rDelta / deltaSec
                    writePerSec = wDelta / deltaSec
                }
            }

            previousReadBytes = totalRead
            previousWriteBytes = totalWrite
            previousTimestamp = now

            return DiskIOSnapshot(
                readBytesPerSec: readPerSec,
                writeBytesPerSec: writePerSec,
                totalReadBytes: totalRead,
                totalWriteBytes: totalWrite,
                timestamp: now
            )
        }
    }
}
