import XCTest
import Darwin
@testable import MacToolKitCore

final class FanClientCoverageTests: XCTestCase {
    private final class UnixSocketServer: @unchecked Sendable {
        let path: String
        private let descriptor: Int32
        private let queue = DispatchQueue(label: "MacDashboardTests.UnixSocketServer")
        private let response: @Sendable ([String: Any]) -> [String: Any]?
        private let expectedConnections: Int

        init(
            expectedConnections: Int,
            response: @escaping @Sendable ([String: Any]) -> [String: Any]?
        ) throws {
            self.path = "/tmp/md-fan-\(getpid())-\(UUID().uuidString.prefix(6)).sock"
            self.expectedConnections = expectedConnections
            self.response = response
            unlink(path)
            descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0 else { throw POSIXError(.ENOTSOCK) }

            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let bytes = path.utf8CString
            withUnsafeMutablePointer(to: &address.sun_path) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: 104) { destination in
                    for index in 0..<min(bytes.count, 104) {
                        destination[index] = bytes[index]
                    }
                }
            }
            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    Darwin.bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bindResult == 0, listen(descriptor, 8) == 0 else {
                close(descriptor)
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            queue.async { [self] in serve() }
        }

        deinit {
            shutdown(descriptor, SHUT_RDWR)
            close(descriptor)
            unlink(path)
        }

        private func serve() {
            for _ in 0..<expectedConnections {
                let client = accept(descriptor, nil, nil)
                guard client >= 0 else { return }
                var buffer = [UInt8](repeating: 0, count: 4_096)
                let count = read(client, &buffer, buffer.count)
                if count > 0,
                   let object = try? JSONSerialization.jsonObject(with: Data(buffer[0..<count])) as? [String: Any],
                   let response = response(object),
                   var data = try? JSONSerialization.data(withJSONObject: response) {
                    data.append(0x0A)
                    data.withUnsafeBytes { raw in
                        if let base = raw.baseAddress {
                            _ = write(client, base, data.count)
                        }
                    }
                }
                shutdown(client, SHUT_RDWR)
                close(client)
            }
        }
    }

    private let fans: [[String: Any]] = [
        ["index": 0, "actualRPM": 2_000, "minRPM": 1_000, "maxRPM": 4_000, "targetRPM": 2_000, "isManual": false, "name": "Left"],
        ["index": 1, "actualRPM": 2_100, "minRPM": 1_000, "maxRPM": 4_000, "targetRPM": 2_100, "isManual": false, "name": "Right"]
    ]

    func testInjectedUnixSocketExercisesEverySuccessfulClientCommand() async throws {
        let fanRows = fans
        let server = try UnixSocketServer(expectedConnections: 13) { command in
            switch command["cmd"] as? String {
            case "ping":
                return ["success": true]
            case "get_fans":
                return ["success": true, "fans": fanRows]
            case "get_temperature_sensors":
                return ["success": true, "sensors": [["key": "Tp01", "value": 65.0]]]
            case "set_fan_target":
                return ["success": true, "targetReadback": command["rpm"] as? Int ?? 0]
            case "set_fan_auto":
                return ["success": true, "modeReadback": 3]
            default:
                return ["success": false]
            }
        }
        let client = FanHelperClient(socketPath: server.path, trustStatusProvider: { .trusted })
        XCTAssertEqual(client.socketTrustStatus(), .trusted)
        let ping = await client.ping()
        let capability = await client.probeCapability()
        let statuses = await client.getFanStatuses()
        let temperatures = await client.getTemperatureSamples()
        let speed = await client.setFanSpeed(fanIndex: 0, rpm: 2_500)
        let auto = await client.setFanAuto(fanIndex: 0)
        let allAuto = await client.setAllAuto()
        let allSpeeds = await client.setAllFanSpeeds(rpm: 2_600)
        XCTAssertTrue(ping)
        XCTAssertEqual(capability, .ready(fanCount: 2))
        XCTAssertEqual(statuses?.count, 2)
        XCTAssertEqual(temperatures?.first?.key, "Tp01")
        XCTAssertTrue(speed)
        XCTAssertTrue(auto)
        XCTAssertTrue(allAuto)
        XCTAssertTrue(allSpeeds)
    }

    func testInjectedUnixSocketCoversMalformedReadbackAndConnectionFailures() async throws {
        let server = try UnixSocketServer(expectedConnections: 6) { command in
            switch command["cmd"] as? String {
            case "ping": return ["success": false]
            case "get_fans": return ["success": false]
            case "get_temperature_sensors": return ["success": false]
            case "set_fan_target": return ["success": true, "targetReadback": 1]
            case "set_fan_auto": return ["success": true, "modeReadback": 2]
            default: return nil
            }
        }
        let client = FanHelperClient(socketPath: server.path, trustStatusProvider: { .trusted })
        let ping = await client.ping()
        let capability = await client.probeCapability()
        let statuses = await client.getFanStatuses()
        let temperatures = await client.getTemperatureSamples()
        let speed = await client.setFanSpeed(fanIndex: 0, rpm: 2_500)
        let auto = await client.setFanAuto(fanIndex: 0)
        XCTAssertFalse(ping)
        XCTAssertEqual(capability, .unreachable)
        XCTAssertNil(statuses)
        XCTAssertNil(temperatures)
        XCTAssertFalse(speed)
        XCTAssertFalse(auto)

        let untrusted = FanHelperClient(socketPath: "/tmp/absent-fan.sock", trustStatusProvider: { .missing })
        let untrustedPing = await untrusted.ping()
        let untrustedStatuses = await untrusted.getFanStatuses()
        let untrustedAuto = await untrusted.setAllAuto()
        let untrustedSpeeds = await untrusted.setAllFanSpeeds(rpm: 2_000)
        XCTAssertFalse(untrustedPing)
        XCTAssertNil(untrustedStatuses)
        XCTAssertFalse(untrustedAuto)
        XCTAssertFalse(untrustedSpeeds)

        let connectFailure = FanHelperClient(socketPath: "/tmp/absent-fan.sock", trustStatusProvider: { .trusted })
        let failedPing = await connectFailure.ping()
        XCTAssertFalse(failedPing)
        XCTAssertEqual(FanHelperClient(socketPath: "/tmp/absent-fan.sock").socketTrustStatus(), .missing)
    }
}
