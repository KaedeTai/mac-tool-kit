import Foundation
import IOKit
import MacToolKitHardwareABI

// MARK: - SMC Data Structures (Exact 80 bytes for Apple SMC)

final class SMCHardwareController: @unchecked Sendable {
    private var connection: io_connect_t = 0
    private let lock = NSLock()
    private var cachedTemperatureKeys: [String]?
    private let verboseProbe = CommandLine.arguments.contains("--probe-readonly")

    init() {
        openConnection()
    }

    deinit {
        closeConnection()
    }

    private func openConnection() {
        if connection != 0 { return }

        let matching = IOServiceMatching("AppleSMC")
        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else {
            print("[SMCHelper] IOServiceGetMatchingServices failed.")
            return
        }

        let service = IOIteratorNext(iterator)
        IOObjectRelease(iterator)

        guard service != 0 else {
            print("[SMCHelper] AppleSMC service not found.")
            return
        }

        var conn: io_connect_t = 0
        let openKr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        IOObjectRelease(service)

        if openKr == KERN_SUCCESS {
            self.connection = conn
            print("[SMCHelper] Successfully opened AppleSMC connection (conn: \(conn)).")
        } else {
            print("[SMCHelper] Failed to open AppleSMC. openKr = \(openKr)")
        }
    }

    private func closeConnection() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    private func fourCharCode(_ str: String) -> UInt32 {
        var res: UInt32 = 0
        for byte in str.utf8.prefix(4) {
            res = (res << 8) | UInt32(byte)
        }
        return res
    }

    private func stringFromFourCharCode(_ code: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    func readKey(_ keyStr: String) -> (type: String, bytes: [UInt8])? {
        lock.lock()
        defer { lock.unlock() }

        if connection == 0 { openConnection() }
        guard connection != 0 else { return nil }

        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = fourCharCode(keyStr)
        input.data8 = 9 // SMC_CMD_READ_KEYINFO

        let inSize = MemoryLayout<SMCKeyData>.size
        var outSize = MemoryLayout<SMCKeyData>.size

        var kr = IOConnectCallStructMethod(connection, 2, &input, inSize, &output, &outSize)
        guard kr == KERN_SUCCESS && output.result == 0 else {
            if verboseProbe {
                print("[SMCHelperProbe] keyInfo \(keyStr) failed: kr=\(kr) smc=\(output.result) size=\(inSize)/\(outSize)")
            }
            return nil
        }
        let keyInfo = output.keyInfo
        input.keyInfo.dataSize = keyInfo.dataSize
        input.data8 = 5 // SMC_CMD_READ_BYTES

        kr = IOConnectCallStructMethod(connection, 2, &input, inSize, &output, &outSize)
        guard kr == KERN_SUCCESS && output.result == 0 else {
            if verboseProbe {
                print("[SMCHelperProbe] read \(keyStr) failed: kr=\(kr) smc=\(output.result) size=\(inSize)/\(outSize)")
            }
            return nil
        }

        var typeChars = [CChar](repeating: 0, count: 5)
        var typeBE = keyInfo.dataType.bigEndian
        memcpy(&typeChars, &typeBE, 4)
        let typeStr = String(cString: typeChars)

        let dataSize = Int(keyInfo.dataSize)
        var byteArr = [UInt8]()
        withUnsafeBytes(of: output.bytes) { raw in
            for i in 0..<min(dataSize, 32) {
                byteArr.append(raw[i])
            }
        }
        return (typeStr, byteArr)
    }

    func writeKey(_ keyStr: String, bytes: [UInt8]) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if connection == 0 { openConnection() }
        guard connection != 0 else { return false }

        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = fourCharCode(keyStr)
        input.data8 = 9 // SMC_CMD_READ_KEYINFO

        let inSize = MemoryLayout<SMCKeyData>.size
        var outSize = MemoryLayout<SMCKeyData>.size

        var kr = IOConnectCallStructMethod(connection, 2, &input, inSize, &output, &outSize)
        guard kr == KERN_SUCCESS && output.result == 0 else { return false }

        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = 6 // SMC_CMD_WRITE_BYTES

        var copyBytes = output.bytes
        withUnsafeMutableBytes(of: &copyBytes) { raw in
            for i in 0..<min(bytes.count, 32) {
                raw[i] = bytes[i]
            }
        }
        input.bytes = copyBytes

        kr = IOConnectCallStructMethod(connection, 2, &input, inSize, &output, &outSize)
        return kr == KERN_SUCCESS && output.result == 0
    }

    func readNumericKey(_ keyStr: String) -> Double? {
        guard let res = readKey(keyStr) else { return nil }
        let type = res.type
        let bytes = res.bytes

        if type == "flt " && bytes.count == 4 {
            var fVal: Float32 = 0
            _ = bytes.withUnsafeBytes { memcpy(&fVal, $0.baseAddress!, 4) }
            return Double(fVal)
        } else if type == "fpe2" && bytes.count == 2 {
            let raw = (Int(bytes[0]) << 8) | Int(bytes[1])
            return Double(raw) / 4.0
        } else if type == "ui8 " && bytes.count >= 1 {
            return Double(bytes[0])
        } else if type == "ui16" && bytes.count >= 2 {
            let raw = (Int(bytes[0]) << 8) | Int(bytes[1])
            return Double(raw)
        } else if type == "ui32" && bytes.count >= 4 {
            let raw = (UInt32(bytes[0]) << 24) |
                (UInt32(bytes[1]) << 16) |
                (UInt32(bytes[2]) << 8) |
                UInt32(bytes[3])
            return Double(raw)
        } else if type == "sp78" && bytes.count >= 2 {
            let raw = (Int(Int8(bitPattern: bytes[0])) << 8) | Int(bytes[1])
            return Double(raw) / 256.0
        }
        return nil
    }

    private func keyAtIndex(_ index: UInt32) -> String? {
        lock.lock()
        defer { lock.unlock() }

        if connection == 0 { openConnection() }
        guard connection != 0 else { return nil }

        var input = SMCKeyData()
        var output = SMCKeyData()
        input.data8 = 8 // SMC_CMD_READ_INDEX
        input.data32 = index

        let inSize = MemoryLayout<SMCKeyData>.size
        var outSize = MemoryLayout<SMCKeyData>.size
        let result = IOConnectCallStructMethod(connection, 2, &input, inSize, &output, &outSize)
        guard result == KERN_SUCCESS, output.result == 0 else { return nil }
        let key = stringFromFourCharCode(output.key)
        return key.utf8.count == 4 ? key : nil
    }

    private func temperatureKeys() -> [String] {
        if let cachedTemperatureKeys { return cachedTemperatureKeys }
        guard let countValue = readNumericKey("#KEY") else { return [] }
        let count = min(max(0, Int(countValue)), 20_000)
        var keys: [String] = []
        keys.reserveCapacity(min(count, 512))
        for index in 0..<count {
            guard let key = keyAtIndex(UInt32(index)) else { continue }
            let prefix = String(key.prefix(2))
            if prefix == "Tp" || prefix == "Tg" || prefix == "Tm" {
                keys.append(key)
                if keys.count == 512 { break }
            }
        }
        cachedTemperatureKeys = keys
        return keys
    }

    func getTemperatureSamples() -> [[String: Any]] {
        temperatureKeys().compactMap { key in
            guard let value = readNumericKey(key),
                  value.isFinite, value > 0, value <= 110 else { return nil }
            return ["key": key, "value": value]
        }
    }

    func writeFloatKey(_ keyStr: String, value: Float32) -> Bool {
        guard let res = readKey(keyStr) else { return false }
        if res.type == "flt " {
            var val = value
            var bytes = [UInt8](repeating: 0, count: 4)
            withUnsafeBytes(of: &val) { raw in
                for i in 0..<4 { bytes[i] = raw[i] }
            }
            return writeKey(keyStr, bytes: bytes)
        } else if res.type == "fpe2" {
            let raw = UInt16(min(max(0, Double(value) * 4.0), 65535.0))
            let bytes: [UInt8] = [UInt8(raw >> 8), UInt8(raw & 0xFF)]
            return writeKey(keyStr, bytes: bytes)
        }
        return false
    }

    func getFanCount() -> Int {
        if let count = readNumericKey("FNum") {
            let parsed = Int(count)
            return (1...16).contains(parsed) ? parsed : 0
        }
        return 0
    }

    private func fanModeKey(index: Int) -> String? {
        let lower = "F\(index)md"
        if readKey(lower) != nil { return lower }
        let upper = "F\(index)Md"
        return readKey(upper) != nil ? upper : nil
    }

    func getFanStatus(index: Int) -> [String: Any]? {
        guard (0..<getFanCount()).contains(index),
              let actualRPM = readNumericKey("F\(index)Ac"), actualRPM >= 0,
              let minRPM = readNumericKey("F\(index)Mn"), minRPM > 0,
              let maxRPM = readNumericKey("F\(index)Mx"), maxRPM >= minRPM,
              let targetRPM = readNumericKey("F\(index)Tg"), targetRPM >= 0,
              let modeKey = fanModeKey(index: index),
              let modeVal = readNumericKey(modeKey) else { return nil }

        let name: String
        if getFanCount() == 2 {
            name = index == 0 ? "左側風扇 (Left)" : "右側風扇 (Right)"
        } else {
            name = "風扇 \(index + 1) (Fan \(index + 1))"
        }
        return [
            "index": index,
            "name": name,
            "actualRPM": Int(actualRPM),
            "minRPM": Int(minRPM),
            "maxRPM": Int(maxRPM),
            "targetRPM": Int(targetRPM),
            "isManual": modeVal > 0
        ]
    }

    func setFanTarget(index: Int, rpm: Int) -> (success: Bool, targetReadback: Int, modeReadback: Int) {
        let fanCount = getFanCount()
        guard (0..<fanCount).contains(index),
              let minRPM = readNumericKey("F\(index)Mn"),
              let maxRPM = readNumericKey("F\(index)Mx"),
              FanCommandSafety.allows(
                index: index,
                rpm: rpm,
                fanCount: fanCount,
                minRPM: Int(minRPM),
                maxRPM: Int(maxRPM)
              ),
              let modeKey = fanModeKey(index: index),
              writeKey(modeKey, bytes: [1]),
              writeFloatKey("F\(index)Tg", value: Float32(rpm)) else {
            return (false, -1, -1)
        }

        usleep(50_000)
        let target = Int(readNumericKey("F\(index)Tg") ?? -1)
        let mode = Int(readNumericKey(modeKey) ?? -1)
        return (abs(target - rpm) <= 1 && mode == 1, target, mode)
    }

    func setFanAuto(index: Int) -> (success: Bool, modeReadback: Int) {
        guard (0..<getFanCount()).contains(index),
              let modeKey = fanModeKey(index: index),
              writeKey(modeKey, bytes: [0]) else {
            return (false, -1)
        }
        usleep(50_000)
        let mode = Int(readNumericKey(modeKey) ?? -1)
        return (mode == 0 || mode == 3, mode)
    }
}

// MARK: - UNIX Domain Socket Server

final class FanHelperServer {
    private let socketPath = "/var/run/macdashboard_fanhelper.sock"
    private let controller = SMCHardwareController()
    private var serverFd: Int32 = -1

    func start() {
        print("[SMCHelper] Starting MacDashboardFanHelper Daemon...")

        unlink(socketPath)

        serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            fatalError("[SMCHelper] Failed to create socket: \(errno)")
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                for i in 0..<min(pathBytes.count, 104) {
                    dest[i] = pathBytes[i]
                }
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        var bindAddr = sockaddr()
        memcpy(&bindAddr, &addr, Int(addrLen))

        let bindRes = withUnsafePointer(to: &bindAddr) { ptr in
            bind(serverFd, ptr, addrLen)
        }

        guard bindRes == 0 else {
            fatalError("[SMCHelper] Failed to bind socket to \(socketPath): \(errno)")
        }

        // Restrict write-capable IPC to local administrators instead of every user.
        guard chown(socketPath, 0, 80) == 0 else { // root:admin on macOS
            fatalError("[SMCHelper] Failed to set socket ownership: \(errno)")
        }
        guard chmod(socketPath, 0o660) == 0 else {
            fatalError("[SMCHelper] Failed to restrict socket permissions: \(errno)")
        }

        guard listen(serverFd, 16) == 0 else {
            fatalError("[SMCHelper] Failed to listen on socket: \(errno)")
        }

        print("[SMCHelper] Listening on \(socketPath)...")

        while true {
            var clientAddr = sockaddr()
            var clientLen: socklen_t = socklen_t(MemoryLayout<sockaddr>.size)
            let clientFd = accept(serverFd, &clientAddr, &clientLen)
            if clientFd >= 0 {
                handleClient(clientFd)
            }
        }
    }

    private func handleClient(_ clientFd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(clientFd, &buffer, buffer.count - 1)
        if bytesRead > 0 {
            let data = Data(buffer[0..<bytesRead])
            let response = processRequest(data)
            if let respData = response.data(using: .utf8) {
                _ = respData.withUnsafeBytes { raw -> Bool in
                    guard let base = raw.baseAddress else { return false }
                    var written = 0
                    while written < respData.count {
                        let result = write(clientFd, base.advanced(by: written), respData.count - written)
                        guard result > 0 else { return false }
                        written += result
                    }
                    return true
                }
            }
        }
        close(clientFd)
    }

    private func processRequest(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cmd = json["cmd"] as? String else {
            return "{\"success\":false,\"error\":\"Invalid JSON or missing cmd\"}\n"
        }

        switch cmd {
        case "ping":
            return "{\"success\":true,\"message\":\"pong\",\"version\":\"1.1.0\"}\n"

        case "get_fans":
            let count = controller.getFanCount()
            guard count > 0 else {
                return "{\"success\":false,\"error\":\"FNum unavailable or no fans reported\"}\n"
            }
            var fanList = [[String: Any]]()
            for i in 0..<count {
                guard let status = controller.getFanStatus(index: i) else {
                    return "{\"success\":false,\"error\":\"Fan telemetry incomplete\"}\n"
                }
                fanList.append(status)
            }
            let resp: [String: Any] = ["success": true, "fans": fanList]
            if let d = try? JSONSerialization.data(withJSONObject: resp), let s = String(data: d, encoding: .utf8) {
                return s + "\n"
            }
            return "{\"success\":false,\"error\":\"Serialization error\"}\n"

        case "get_temperature_sensors":
            let sensors = controller.getTemperatureSamples()
            guard !sensors.isEmpty else {
                return "{\"success\":false,\"error\":\"No attributable SMC temperature sensors\"}\n"
            }
            let response: [String: Any] = ["success": true, "sensors": sensors]
            if let data = try? JSONSerialization.data(withJSONObject: response),
               let string = String(data: data, encoding: .utf8) {
                return string + "\n"
            }
            return "{\"success\":false,\"error\":\"Serialization error\"}\n"

        case "set_fan_target":
            guard let index = json["fan"] as? Int,
                  let rpm = json["rpm"] as? Int,
                  index >= 0, rpm > 0 else {
                return "{\"success\":false,\"error\":\"fan and positive rpm are required\"}\n"
            }
            let result = controller.setFanTarget(index: index, rpm: rpm)
            return "{\"success\":\(result.success),\"fan\":\(index),\"target\":\(rpm),\"targetReadback\":\(result.targetReadback),\"modeReadback\":\(result.modeReadback)}\n"

        case "set_fan_auto":
            guard let index = json["fan"] as? Int, index >= 0 else {
                return "{\"success\":false,\"error\":\"fan is required\"}\n"
            }
            let result = controller.setFanAuto(index: index)
            return "{\"success\":\(result.success),\"fan\":\(index),\"mode\":\"auto\",\"modeReadback\":\(result.modeReadback)}\n"

        case "set_all_auto":
            let count = controller.getFanCount()
            guard count > 0 else {
                return "{\"success\":false,\"error\":\"FNum unavailable or no fans reported\"}\n"
            }
            var allOk = true
            for i in 0..<count {
                if !controller.setFanAuto(index: i).success {
                    allOk = false
                }
            }
            return "{\"success\":\(allOk),\"mode\":\"auto_all\"}\n"

        default:
            return "{\"success\":false,\"error\":\"Unknown command: \(cmd)\"}\n"
        }
    }
}

// MARK: - Main Entry Point

if CommandLine.arguments.contains("--probe-readonly") {
    let controller = SMCHardwareController()
    let rawFNum = controller.readKey("FNum")
    let count = controller.getFanCount()
    let fans = (0..<count).compactMap { controller.getFanStatus(index: $0) }
    let temperatures = controller.getTemperatureSamples()
    let payload: [String: Any] = [
        "success": !fans.isEmpty,
        "smcPayloadBytes": MemoryLayout<SMCKeyData>.size,
        "offsetKeyInfo": MemoryLayout<SMCKeyData>.offset(of: \.keyInfo) ?? -1,
        "offsetResult": MemoryLayout<SMCKeyData>.offset(of: \.result) ?? -1,
        "offsetData8": MemoryLayout<SMCKeyData>.offset(of: \.data8) ?? -1,
        "offsetData32": MemoryLayout<SMCKeyData>.offset(of: \.data32) ?? -1,
        "offsetBytes": MemoryLayout<SMCKeyData>.offset(of: \.bytes) ?? -1,
        "fNumType": rawFNum?.type ?? "unavailable",
        "fNumBytes": rawFNum?.bytes ?? [],
        "fans": fans,
        "temperatureSensors": temperatures
    ]
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
       let string = String(data: data, encoding: .utf8) {
        print(string)
    }
    exit(fans.isEmpty ? 1 : 0)
} else {
    let server = FanHelperServer()
    server.start()
}
