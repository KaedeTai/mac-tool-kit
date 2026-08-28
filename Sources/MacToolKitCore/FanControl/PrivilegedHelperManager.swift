import Foundation

public final class PrivilegedHelperManager: Sendable {
    public static let shared = PrivilegedHelperManager()

    public let helperIdentifier = "com.peterting.macdashboard.fanhelper"
    public let helperToolPath = "/Library/PrivilegedHelperTools/com.peterting.macdashboard.fanhelper"
    public let daemonPlistPath = "/Library/LaunchDaemons/com.peterting.macdashboard.fanhelper.plist"
    public let socketPath = "/var/run/macdashboard_fanhelper.sock"

    private init() {}

    public func isInstalled() -> Bool {
        return FileManager.default.fileExists(atPath: helperToolPath) &&
               FileManager.default.fileExists(atPath: daemonPlistPath)
    }

    public func isRunning() async -> Bool {
        return await FanHelperClient.shared.ping()
    }

    public func locateBundledHelper() -> URL? {
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

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let output = appleScript.executeAndReturnError(&error)
            if let err = error {
                let errMsg = err[NSAppleScript.errorMessage] as? String ?? "使用者取消授權或安裝失敗"
                return .failure(HelperError(errMsg))
            }
            _ = output

            // Wait a brief moment for socket to be ready
            for _ in 0..<15 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if await isRunning() {
                    return .success(())
                }
            }

            return .success(())
        } else {
            return .failure(HelperError("無法建立 AppleScript 執行環境"))
        }
    }

    public func uninstallHelper() async -> Result<Void, HelperError> {
        let script = """
        do shell script "
        launchctl unload -w '\(daemonPlistPath)' 2>/dev/null || true && \
        rm -f '\(daemonPlistPath)' '\(helperToolPath)' '\(socketPath)'
        " with administrator privileges
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let output = appleScript.executeAndReturnError(&error)
            if let err = error {
                let errMsg = err[NSAppleScript.errorMessage] as? String ?? "解除安裝失敗"
                return .failure(HelperError(errMsg))
            }
            _ = output
            return .success(())
        } else {
            return .failure(HelperError("無法建立 AppleScript 執行環境"))
        }
    }
}
