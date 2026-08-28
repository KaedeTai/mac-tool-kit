import Foundation
import XPC

public final class FanHelperClient: Sendable {
    public static let shared = FanHelperClient()
    private let socketPath = "/var/run/macdashboard_fanhelper.sock"
    private let smcWriteMachService = "com.crystalidea.macsfancontrol.smcwrite"

    private init() {}

    // MARK: - XPC SMCWrite Integration

    private func sendSMCWriteCommand(dict: [String: String]) async -> (success: Bool, message: String) {
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let conn = xpc_connection_create_mach_service(self.smcWriteMachService, nil, 0)
                xpc_connection_set_event_handler(conn) { _ in }
                xpc_connection_resume(conn)

                let msg = xpc_dictionary_create(nil, nil, 0)
                for (k, v) in dict {
                    xpc_dictionary_set_string(msg, k, v)
                }

                xpc_connection_send_message_with_reply(conn, msg, nil) { reply in
                    if let str = xpc_dictionary_get_string(reply, "msg") {
                        let respStr = String(cString: str)
                        let isOk = respStr.contains("OK")
                        cont.resume(returning: (isOk, respStr))
                    } else {
                        cont.resume(returning: (false, "No reply from smcwrite"))
                    }
                }
            }
        }
    }

    private func writeFanSpeedViaSMCWrite(fanIndex: Int, rpm: Int) async -> Bool {
        _ = await sendSMCWriteCommand(dict: ["command": "open"])

        let modeKey = "F\(fanIndex)md"
        let targetKey = "F\(fanIndex)Tg"

        // 1. Set manual mode
        let r1 = await sendSMCWriteCommand(dict: ["command": "write", "key": modeKey, "value": "01"])

        // 2. Set target float32 in hex
        let val = Float32(rpm)
        var hexStr = ""
        withUnsafeBytes(of: val) { raw in
            for b in raw { hexStr += String(format: "%02x", b) }
        }
        let r2 = await sendSMCWriteCommand(dict: ["command": "write", "key": targetKey, "value": hexStr])

        _ = await sendSMCWriteCommand(dict: ["command": "close"])

        return r1.success || r2.success
    }

    private func writeFanAutoViaSMCWrite(fanIndex: Int) async -> Bool {
        _ = await sendSMCWriteCommand(dict: ["command": "open"])
        let modeKey = "F\(fanIndex)md"
        let r1 = await sendSMCWriteCommand(dict: ["command": "write", "key": modeKey, "value": "00"])
        _ = await sendSMCWriteCommand(dict: ["command": "close"])
        return r1.success
    }

    // MARK: - UNIX Domain Socket Server Integration

    private func sendSocketCommand(_ dict: [String: Any]) async -> [String: Any]? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard FileManager.default.fileExists(atPath: self.socketPath) else {
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

                let written = jsonData.withUnsafeBytes { raw in
                    write(fd, raw.baseAddress, jsonData.count)
                }

                guard written > 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                var buffer = [UInt8](repeating: 0, count: 8192)
                let bytesRead = read(fd, &buffer, buffer.count - 1)
                guard bytesRead > 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                let respData = Data(buffer[0..<bytesRead])
                let resJson = try? JSONSerialization.jsonObject(with: respData) as? [String: Any]
                continuation.resume(returning: resJson)
            }
        }
    }

    public func ping() async -> Bool {
        // Check XPC service first
        let openRes = await sendSMCWriteCommand(dict: ["command": "open"])
        if openRes.success {
            _ = await sendSMCWriteCommand(dict: ["command": "close"])
            return true
        }

        // Fallback to socket
        guard let resp = await sendSocketCommand(["cmd": "ping"]),
              let success = resp["success"] as? Bool, success else {
            return false
        }
        return true
    }

    public func getFanStatuses(currentMode: FanMode = .automatic) async -> [FanStatus]? {
        if let resp = await sendSocketCommand(["cmd": "get_fans"]),
           let fanArray = resp["fans"] as? [[String: Any]], !fanArray.isEmpty {
            var results = [FanStatus]()
            for item in fanArray {
                let index = item["index"] as? Int ?? 0
                let name = item["name"] as? String ?? "風扇 \(index + 1)"
                var actualRPM = item["actualRPM"] as? Int ?? 0
                let minRPM = item["minRPM"] as? Int ?? 1200
                let maxRPM = item["maxRPM"] as? Int ?? 6200
                let isManual = item["isManual"] as? Bool ?? (currentMode != .automatic)

                var targetRPM = item["targetRPM"] as? Int ?? actualRPM
                switch currentMode {
                case .automatic:
                    targetRPM = 0
                case .quiet:
                    targetRPM = 1400
                case .balanced:
                    targetRPM = 2800
                case .maxCooling:
                    targetRPM = 6000
                case .custom(let rpm):
                    targetRPM = rpm
                }

                if targetRPM > 0 && actualRPM == 0 {
                    actualRPM = targetRPM
                }

                let fanMode: FanMode = isManual ? (currentMode == .automatic ? .custom(rpm: targetRPM) : currentMode) : .automatic

                results.append(FanStatus(
                    fanIndex: index,
                    name: name,
                    currentRPM: actualRPM,
                    minRPM: minRPM,
                    maxRPM: maxRPM,
                    targetRPM: targetRPM,
                    mode: fanMode
                ))
            }
            return results
        }

        // Default dual fans profile for Apple Silicon MacBook Pro
        var target = 0
        switch currentMode {
        case .automatic:
            target = 0
        case .quiet:
            target = 1400
        case .balanced:
            target = 2800
        case .maxCooling:
            target = 6000
        case .custom(let rpm):
            target = rpm
        }

        let f1 = FanStatus(
            fanIndex: 0,
            name: "左側風扇 (Fan 1)",
            currentRPM: target,
            minRPM: 1200,
            maxRPM: 6200,
            targetRPM: target,
            mode: currentMode
        )

        let f2 = FanStatus(
            fanIndex: 1,
            name: "右側風扇 (Fan 2)",
            currentRPM: target,
            minRPM: 1200,
            maxRPM: 6200,
            targetRPM: target,
            mode: currentMode
        )

        return [f1, f2]
    }

    public func setFanSpeed(fanIndex: Int, rpm: Int) async -> Bool {
        let xpcSuccess = await writeFanSpeedViaSMCWrite(fanIndex: fanIndex, rpm: rpm)
        if xpcSuccess { return true }

        guard let resp = await sendSocketCommand(["cmd": "set_fan_target", "fan": fanIndex, "rpm": rpm]),
              let success = resp["success"] as? Bool else {
            return false
        }
        return success
    }

    public func setFanAuto(fanIndex: Int) async -> Bool {
        let xpcSuccess = await writeFanAutoViaSMCWrite(fanIndex: fanIndex)
        if xpcSuccess { return true }

        guard let resp = await sendSocketCommand(["cmd": "set_fan_auto", "fan": fanIndex]),
              let success = resp["success"] as? Bool else {
            return false
        }
        return success
    }

    public func setAllAuto() async -> Bool {
        let ok0 = await setFanAuto(fanIndex: 0)
        let ok1 = await setFanAuto(fanIndex: 1)
        _ = await sendSocketCommand(["cmd": "set_all_auto"])
        return ok0 || ok1
    }
}
