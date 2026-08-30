import Foundation

public final class PrivilegedHelperManager: Sendable {
    public static let shared = PrivilegedHelperManager()

    public let helperIdentifier: String
    public let helperToolPath: String
    public let daemonPlistPath: String
    public let socketPath: String

    private let bundledHelperLocator: (@Sendable () -> URL?)?
    private let scriptExecutor: (@Sendable (String) -> String?)?
    private let pingProvider: @Sendable () async -> Bool
    private let capabilityProvider: @Sendable () async -> FanHelperCapability
    private let sleepProvider: @Sendable (UInt64) async -> Void

    init(
        helperIdentifier: String = "com.peterting.macdashboard.fanhelper",
        helperToolPath: String = "/Library/PrivilegedHelperTools/com.peterting.macdashboard.fanhelper",
        daemonPlistPath: String = "/Library/LaunchDaemons/com.peterting.macdashboard.fanhelper.plist",
        socketPath: String = "/var/run/macdashboard_fanhelper.sock",
        bundledHelperLocator: (@Sendable () -> URL?)? = nil,
        scriptExecutor: (@Sendable (String) -> String?)? = nil,
        pingProvider: @escaping @Sendable () async -> Bool = { await FanHelperClient.shared.ping() },
        capabilityProvider: @escaping @Sendable () async -> FanHelperCapability = {
            await FanHelperClient.shared.probeCapability()
        },
        sleepProvider: @escaping @Sendable (UInt64) async -> Void = {
            try? await Task.sleep(nanoseconds: $0)
        }
    ) {
        self.helperIdentifier = helperIdentifier
        self.helperToolPath = helperToolPath
        self.daemonPlistPath = daemonPlistPath
        self.socketPath = socketPath
        self.bundledHelperLocator = bundledHelperLocator
        self.scriptExecutor = scriptExecutor
        self.pingProvider = pingProvider
        self.capabilityProvider = capabilityProvider
        self.sleepProvider = sleepProvider
    }

    public func isInstalled() -> Bool {
        return FileManager.default.fileExists(atPath: helperToolPath) &&
               FileManager.default.fileExists(atPath: daemonPlistPath)
    }

    public func isRunning() async -> Bool {
        return await pingProvider()
    }

    public func capability() async -> FanHelperCapability {
        await capabilityProvider()
    }

    public func locateBundledHelper() -> URL? {
        if let bundledHelperLocator {
            return bundledHelperLocator()
        }

        // 1. Check in Bundle.main.resourceURL
        if let resURL = Bundle.main.resourceURL {
            let helperURL = resURL.appendingPathComponent("MacDashboardFanHelper")
            if FileManager.default.fileExists(atPath: helperURL.path) {
                return helperURL
            }
        }

        // 2. Check in Bundle.main.bundleURL/Contents/MacOS
        let macosURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/MacDashboardFanHelper")
        if FileManager.default.fileExists(atPath: macosURL.path) {
            return macosURL
        }

        // 3. Check in current executable directory
        let execURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("MacDashboardFanHelper")
        if FileManager.default.fileExists(atPath: execURL.path) {
            return execURL
        }

        // 4. Check relative development build directories
        let devPaths = [
            "/Applications/MacDashboard.app/Contents/Resources/MacDashboardFanHelper",
            "/Applications/MacDashboard.app/Contents/MacOS/MacDashboardFanHelper",
            ".build/arm64-apple-macosx/release/MacDashboardFanHelper",
            ".build/release/MacDashboardFanHelper",
            ".build/arm64-apple-macosx/debug/MacDashboardFanHelper",
            ".build/debug/MacDashboardFanHelper"
        ]

        for p in devPaths {
            if FileManager.default.fileExists(atPath: p) {
                return URL(fileURLWithPath: p)
            }
        }

        return nil
    }

    public struct HelperError: LocalizedError, Sendable {
        public let message: String
        public init(_ message: String) { self.message = message }
        public var errorDescription: String? { message }
    }

    public func installHelper() async -> Result<Void, HelperError> {
        guard let sourceURL = locateBundledHelper() else {
            return .failure(HelperError("找不到 MacDashboardFanHelper 二進位檔案，請先確認已建置 Helper。"))
        }

        let srcPath = sourceURL.path

        let script = """
        do shell script "
        mkdir -p /Library/PrivilegedHelperTools /Library/LaunchDaemons && \
        cp '\(srcPath)' '\(helperToolPath)' && \
        chown root:wheel '\(helperToolPath)' && \
        chmod 755 '\(helperToolPath)' && \
        cat << 'EOF' > '\(daemonPlistPath)'
        <?xml version=\\"1.0\\" encoding=\\"UTF-8\\"?>
        <!DOCTYPE plist PUBLIC \\"-//Apple//DTD PLIST 1.0//EN\\" \\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\\">
        <plist version=\\"1.0\\">
        <dict>
            <key>Label</key>
            <string>\(helperIdentifier)</string>
            <key>Program</key>
            <string>\(helperToolPath)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(helperToolPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
        </dict>
        </plist>
        EOF
        chown root:wheel '\(daemonPlistPath)' && \
        chmod 644 '\(daemonPlistPath)' && \
        launchctl unload -w '\(daemonPlistPath)' 2>/dev/null || true && \
        launchctl load -w '\(daemonPlistPath)'
        " with administrator privileges
        """

        if let errorMessage = executeAdministratorScript(script) {
            return .failure(HelperError(errorMessage))
        }

        // Installation is successful only after measured fan readback is
        // available. A ping alone merely proves that the daemon launched.
        var lastCapability: FanHelperCapability = .unreachable
        for _ in 0..<15 {
            await sleepProvider(200_000_000)
            lastCapability = await capability()
            if lastCapability.hasVerifiedFanReadback {
                return .success(())
            }
        }

        return .failure(HelperError("助手已安裝，但未通過硬體讀回驗證（\(lastCapability.localizedDescription)）；未宣告啟用成功。"))
    }

    public func uninstallHelper() async -> Result<Void, HelperError> {
        let script = """
        do shell script "
        launchctl unload -w '\(daemonPlistPath)' 2>/dev/null || true && \
        rm -f '\(daemonPlistPath)' '\(helperToolPath)' '\(socketPath)'
        " with administrator privileges
        """

        if let errorMessage = executeAdministratorScript(script) {
            return .failure(HelperError(errorMessage))
        }
        return .success(())
    }

    private func executeAdministratorScript(_ script: String) -> String? {
        if let scriptExecutor {
            return scriptExecutor(script)
        }

        guard let appleScript = NSAppleScript(source: script) else {
            return "無法建立 AppleScript 執行環境"
        }

        var error: NSDictionary?
        _ = appleScript.executeAndReturnError(&error)
        guard let error else { return nil }
        return error[NSAppleScript.errorMessage] as? String ?? "使用者取消授權或執行失敗"
    }
}
