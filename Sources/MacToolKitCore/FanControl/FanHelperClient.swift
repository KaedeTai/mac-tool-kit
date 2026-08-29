import Foundation

public enum FanWriteOutcome {
    public static func allSucceeded(_ results: [Bool]) -> Bool {
        !results.isEmpty && results.allSatisfy { $0 }
    }
}

public enum FanHelperSocketTrust: Equatable, Sendable {
    case trusted
    case missing
    case unsafe(String)

    public static func evaluate(
        mode: UInt32,
        ownerUID: UInt32,
        groupGID: UInt32
    ) -> FanHelperSocketTrust {
        guard mode & 0o170000 == 0o140000 else {
            return .unsafe("Helper endpoint is not a UNIX socket")
        }
        guard ownerUID == 0 else {
            return .unsafe("Socket owner must be root")
        }
        guard groupGID == 80 else {
            return .unsafe("Socket group must be admin")
        }
        guard mode & 0o777 == 0o660 else {
            return .unsafe("Socket permissions must be exactly 0660")
        }
        return .trusted
    }
}

public enum FanHelperCapability: Equatable, Sendable {
    case unreachable
    case reachableWithoutReadback
    case ready(fanCount: Int)

    public var hasVerifiedFanReadback: Bool {
        if case .ready = self { return true }
        return false
    }

    public var localizedDescription: String {
        switch self {
        case .unreachable:
            return "讀回助手未連線"
        case .reachableWithoutReadback:
            return "讀回助手已啟動，但無法取得風扇硬體資料"
        case .ready(let fanCount):
            return "已驗證 \(fanCount) 個風扇的實際 RPM 與硬體範圍"
        }
    }
}

public enum FanHelperProtocolParser {
    public static func capability(
        pingSucceeded: Bool,
        fanResponse: [String: Any]?
    ) -> FanHelperCapability {
        guard pingSucceeded else { return .unreachable }
        guard let fans = fanStatuses(from: fanResponse) else {
            return .reachableWithoutReadback
        }
        return .ready(fanCount: fans.count)
    }

    public static func fanStatuses(
        from response: [String: Any]?,
        currentMode: FanMode = .automatic
    ) -> [FanStatus]? {
        guard let response,
              response["success"] as? Bool == true,
              let rawFans = response["fans"] as? [[String: Any]],
              (1...16).contains(rawFans.count) else {
            return nil
        }

        var seenIndexes = Set<Int>()
        var fans: [FanStatus] = []
        for raw in rawFans {
            guard let index = integer(raw["index"]), (0..<16).contains(index),
                  seenIndexes.insert(index).inserted,
                  let actualRPM = integer(raw["actualRPM"]), (0...100_000).contains(actualRPM),
                  let minRPM = integer(raw["minRPM"]), (1...100_000).contains(minRPM),
                  let maxRPM = integer(raw["maxRPM"]), (minRPM...100_000).contains(maxRPM),
                  let targetRPM = integer(raw["targetRPM"]), (0...100_000).contains(targetRPM),
                  let isManual = raw["isManual"] as? Bool else {
                return nil
            }

            let rawName = raw["name"] as? String
            let name = sanitizedFanName(rawName, fallbackIndex: index)
            let mode: FanMode = isManual
                ? (currentMode == .automatic ? .custom(rpm: targetRPM) : currentMode)
                : .automatic
            fans.append(FanStatus(
                fanIndex: index,
                name: name,
                currentRPM: actualRPM,
                minRPM: minRPM,
                maxRPM: maxRPM,
                targetRPM: targetRPM,
                mode: mode
            ))
        }
        return fans.sorted { $0.fanIndex < $1.fanIndex }
    }

    public static func temperatureSamples(from response: [String: Any]?) -> [SMCTemperatureSample]? {
        guard let response,
              response["success"] as? Bool == true,
              let rawSensors = response["sensors"] as? [[String: Any]],
              (1...512).contains(rawSensors.count) else {
            return nil
        }

        var seenKeys = Set<String>()
        var samples: [SMCTemperatureSample] = []
        for raw in rawSensors {
            guard let key = raw["key"] as? String,
                  key.utf8.count == 4,
                  ["Tp", "Tg", "Tm"].contains(String(key.prefix(2))),
                  seenKeys.insert(key).inserted,
                  let value = finiteNumber(raw["value"]),
                  value > 0, value <= 110 else {
                return nil
            }
            samples.append(SMCTemperatureSample(key: key, valueCelsius: value))
        }
        return samples
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double,
              double >= Double(Int.min), double <= Double(Int.max) else { return nil }
        return Int(double)
    }

    private static func finiteNumber(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    private static func sanitizedFanName(_ raw: String?, fallbackIndex: Int) -> String {
        guard let raw else { return "風扇 \(fallbackIndex + 1)" }
        let cleaned = raw.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
            .prefix(64)
            .map(String.init)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "風扇 \(fallbackIndex + 1)" : cleaned
    }
}

public final class FanHelperClient: Sendable {
    public static let shared = FanHelperClient()
    private let socketPath = "/var/run/macdashboard_fanhelper.sock"

    private init() {}

    public func socketTrustStatus() -> FanHelperSocketTrust {
        var metadata = stat()
        guard lstat(socketPath, &metadata) == 0 else {
            return errno == ENOENT
                ? .missing
                : .unsafe("Unable to inspect helper socket metadata")
        }
        return FanHelperSocketTrust.evaluate(
            mode: UInt32(metadata.st_mode),
            ownerUID: metadata.st_uid,
            groupGID: metadata.st_gid
        )
    }

    // MARK: - UNIX Domain Socket Server Integration

    private func sendSocketCommand(_ dict: [String: Any]) async -> [String: Any]? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard self.socketTrustStatus() == .trusted else {
                    continuation.resume(returning: nil)
                    return
                }

                let fd = socket(AF_UNIX, SOCK_STREAM, 0)
                guard fd >= 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                defer { close(fd) }

                var tv = timeval(tv_sec: 1, tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                var addr = sockaddr_un()
                addr.sun_family = sa_family_t(AF_UNIX)
                let pathBytes = self.socketPath.utf8CString
                withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                    ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                        for i in 0..<min(pathBytes.count, 104) {
                            dest[i] = pathBytes[i]
                        }
                    }
                }

                let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
                let connectRes = withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        connect(fd, sa, addrLen)
                    }
                }

                guard connectRes == 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                guard let jsonData = try? JSONSerialization.data(withJSONObject: dict) else {
                    continuation.resume(returning: nil)
                    return
                }

                var bytesWritten = 0
                let writeSucceeded = jsonData.withUnsafeBytes { raw -> Bool in
                    guard let base = raw.baseAddress else { return false }
                    while bytesWritten < jsonData.count {
                        let result = write(fd, base.advanced(by: bytesWritten), jsonData.count - bytesWritten)
                        guard result > 0 else { return false }
                        bytesWritten += result
                    }
                    return true
                }

                guard writeSucceeded else {
                    continuation.resume(returning: nil)
                    return
                }

                var responseData = Data()
                var buffer = [UInt8](repeating: 0, count: 4_096)
                while responseData.count < 65_536 {
                    let bytesRead = read(fd, &buffer, buffer.count)
                    guard bytesRead > 0 else { break }
                    responseData.append(contentsOf: buffer[0..<bytesRead])
                    if buffer[0..<bytesRead].contains(0x0A) { break }
                }
                guard !responseData.isEmpty, responseData.count <= 65_536 else {
                    continuation.resume(returning: nil)
                    return
                }

                let resJson = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
                continuation.resume(returning: resJson)
            }
        }
    }

    public func ping() async -> Bool {
        guard let resp = await sendSocketCommand(["cmd": "ping"]),
              let success = resp["success"] as? Bool, success else {
            return false
        }
        return true
    }

    public func probeCapability() async -> FanHelperCapability {
        let pingSucceeded = await ping()
        let fanResponse = pingSucceeded ? await sendSocketCommand(["cmd": "get_fans"]) : nil
        return FanHelperProtocolParser.capability(
            pingSucceeded: pingSucceeded,
            fanResponse: fanResponse
        )
    }

    public func getFanStatuses(currentMode: FanMode = .automatic) async -> [FanStatus]? {
        FanHelperProtocolParser.fanStatuses(
            from: await sendSocketCommand(["cmd": "get_fans"]),
            currentMode: currentMode
        )
    }

    public func getTemperatureSamples() async -> [SMCTemperatureSample]? {
        FanHelperProtocolParser.temperatureSamples(
            from: await sendSocketCommand(["cmd": "get_temperature_sensors"])
        )
    }

    public func setFanSpeed(fanIndex: Int, rpm: Int) async -> Bool {
        guard let resp = await sendSocketCommand(["cmd": "set_fan_target", "fan": fanIndex, "rpm": rpm]),
              resp["success"] as? Bool == true,
              let targetReadback = resp["targetReadback"] as? Int else {
            return false
        }
        return abs(targetReadback - rpm) <= 1
    }

    public func setFanAuto(fanIndex: Int) async -> Bool {
        guard let resp = await sendSocketCommand(["cmd": "set_fan_auto", "fan": fanIndex]),
              resp["success"] as? Bool == true,
              let modeReadback = resp["modeReadback"] as? Int else {
            return false
        }
        return modeReadback == 0 || modeReadback == 3
    }

    public func setAllAuto() async -> Bool {
        guard let fans = await getFanStatuses(), !fans.isEmpty else { return false }
        var results: [Bool] = []
        for fan in fans {
            results.append(await setFanAuto(fanIndex: fan.fanIndex))
        }
        return FanWriteOutcome.allSucceeded(results)
    }

    public func setAllFanSpeeds(rpm: Int) async -> Bool {
        guard let fans = await getFanStatuses(), !fans.isEmpty else { return false }
        var results: [Bool] = []
        for fan in fans {
            results.append(await setFanSpeed(fanIndex: fan.fanIndex, rpm: rpm))
        }
        return FanWriteOutcome.allSucceeded(results)
    }
}
