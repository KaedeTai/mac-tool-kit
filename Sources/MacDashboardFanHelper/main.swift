import Foundation
import IOKit

// MARK: - SMC Data Structures (Exact 80 bytes for Apple SMC)

public struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

public struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

public struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

public struct SMCKeyData_t {
    var key: UInt32 = 0
    var vers: SMCVersion = SMCVersion()
    var pLimitData: SMCPLimitData = SMCPLimitData()
    var keyInfo: SMCKeyInfoData = SMCKeyInfoData()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

final class SMCHardwareController: @unchecked Sendable {
    private var connection: io_connect_t = 0
    private let lock = NSLock()

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

    func readKey(_ keyStr: String) -> (type: String, bytes: [UInt8])? {
        lock.lock()
        defer { lock.unlock() }

        if connection == 0 { openConnection() }
        guard connection != 0 else { return nil }

        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        input.key = fourCharCode(keyStr)
        input.data8 = 9 // SMC_CMD_READ_KEYINFO

        let inSize = MemoryLayout<SMCKeyData_t>.size
        var outSize = MemoryLayout<SMCKeyData_t>.size

        var kr = IOConnectCallStructMethod(connection, 2, &input, inSize, &output, &outSize)
        guard kr == KERN_SUCCESS && output.result == 0 else { return nil }

        input.keyInfo = output.keyInfo
        input.data8 = 5 // SMC_CMD_READ_BYTES

        kr = IOConnectCallStructMethod(connection, 2, &input, inSize, &output, &outSize)
        guard kr == KERN_SUCCESS && output.result == 0 else { return nil }

        var typeChars = [CChar](repeating: 0, count: 5)
        var typeBE = output.keyInfo.dataType.bigEndian
        memcpy(&typeChars, &typeBE, 4)
        let typeStr = String(cString: typeChars)

        let dataSize = Int(output.keyInfo.dataSize)
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

        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        input.key = fourCharCode(keyStr)
        input.data8 = 9 // SMC_CMD_READ_KEYINFO

        let inSize = MemoryLayout<SMCKeyData_t>.size
        var outSize = MemoryLayout<SMCKeyData_t>.size

        var kr = IOConnectCallStructMethod(connection, 2, &input, inSize, &output, &outSize)
        guard kr == KERN_SUCCESS && output.result == 0 else { return false }

        input.keyInfo = output.keyInfo
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
        } else if type == "sp78" && bytes.count >= 2 {
            let raw = (Int(Int8(bitPattern: bytes[0])) << 8) | Int(bytes[1])
            return Double(raw) / 256.0
        }
        return nil
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
            return max(1, Int(count))
        }
        return 2
    }

    func getFanStatus(index: Int) -> [String: Any] {
        let actualRPM = readNumericKey("F\(index)Ac") ?? 0
        let minRPM = readNumericKey("F\(index)Mn") ?? 1200
        let maxRPM = readNumericKey("F\(index)Mx") ?? 6200
        let targetRPM = readNumericKey("F\(index)Tg") ?? actualRPM
        let modeVal = readNumericKey("F\(index)md") ?? readNumericKey("F\(index)Md") ?? 0

        let name = index == 0 ? "左側風扇 (Fan 1)" : "右側風扇 (Fan 2)"
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

    func setFanTarget(index: Int, rpm: Int) -> Bool {
        // Set manual mode on F0md / F0Md
        _ = writeKey("F\(index)md", bytes: [1])
        _ = writeKey("F\(index)Md", bytes: [1])

        // Write target RPM
        var success = writeFloatKey("F\(index)Tg", value: Float32(rpm))
        if !success {
            var val = Float32(rpm)
            var bytes = [UInt8](repeating: 0, count: 4)
            withUnsafeBytes(of: &val) { raw in
                for i in 0..<4 { bytes[i] = raw[i] }
            }
            success = writeKey("F\(index)Tg", bytes: bytes)
        }
        return success
    }

    func setFanAuto(index: Int) -> Bool {
        let ok1 = writeKey("F\(index)md", bytes: [0])
        let ok2 = writeKey("F\(index)Md", bytes: [0])
        return ok1 || ok2
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

        chmod(socketPath, 0o666)

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
                _ = respData.withUnsafeBytes { raw in
                    write(clientFd, raw.baseAddress, respData.count)
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
            return "{\"success\":true,\"message\":\"pong\",\"version\":\"1.0.0\"}\n"

        case "get_fans":
            let count = controller.getFanCount()
            var fanList = [[String: Any]]()
            for i in 0..<count {
                fanList.append(controller.getFanStatus(index: i))
            }
            let resp: [String: Any] = ["success": true, "fans": fanList]
            if let d = try? JSONSerialization.data(withJSONObject: resp), let s = String(data: d, encoding: .utf8) {
                return s + "\n"
            }
            return "{\"success\":false,\"error\":\"Serialization error\"}\n"

        case "set_fan_target":
            let index = json["fan"] as? Int ?? 0
            let rpm = json["rpm"] as? Int ?? 2000
            let ok = controller.setFanTarget(index: index, rpm: rpm)
            return "{\"success\":\(ok),\"fan\":\(index),\"target\":\(rpm)}\n"

        case "set_fan_auto":
            let index = json["fan"] as? Int ?? 0
            let ok = controller.setFanAuto(index: index)
            return "{\"success\":\(ok),\"fan\":\(index),\"mode\":\"auto\"}\n"

        case "set_all_auto":
            let count = controller.getFanCount()
            var allOk = true
            for i in 0..<count {
                if !controller.setFanAuto(index: i) {
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

let server = FanHelperServer()
server.start()
