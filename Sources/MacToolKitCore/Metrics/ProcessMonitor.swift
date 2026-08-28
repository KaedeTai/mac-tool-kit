import Foundation
import Darwin
import AppKit

public final class ProcessMonitor: @unchecked Sendable {
    private struct PreviousProcessTimes {
        let cpuTime: UInt64
        let timestamp: CFAbsoluteTime
    }

    private var previousTimes: [pid_t: PreviousProcessTimes] = [:]
    private var timebase = mach_timebase_info_data_t()
    private var guiAppsCache: [pid_t: (name: String, bundleId: String?)] = [:]
    private var lastGuiCacheTime: CFAbsoluteTime = 0
    private var processMetadataCache: [pid_t: ProcessMetadata] = [:]
    private var cachedDockerContainers: [DockerContainerInfo] = []
    private var lastDockerSampleTime: CFAbsoluteTime = 0
    private let lock = NSLock()

    private struct ProcessMetadata: Sendable {
        let friendlyName: String
        let category: ProcessCategory
        let commandLine: String?
        let workingDirectory: String?
        let projectName: String?
        let triggerAppName: String?
        let triggerChain: [String]
        let startedAt: Date?
        let uptimeSeconds: TimeInterval
        let impact: String
        let parentAppName: String?
        let aiContext: AIContextInfo?
    }

    public init() {
        mach_timebase_info(&timebase)
        if timebase.denom == 0 {
            timebase.numer = 1
            timebase.denom = 1
        }
    }

    private func getAntigravityActiveModelName() -> String {
        let stateUrl = URL(fileURLWithPath: NSHomeDirectory() + "/.gemini/antigravity/antigravity_state.pbtxt")
        guard let content = try? String(contentsOf: stateUrl, encoding: .utf8) else { return "Gemini" }
        for line in content.components(separatedBy: .newlines) {
            if line.contains("last_selected_agent_model:") {
                if line.contains("M132") { return "Gemini 3.7 Flash High" }
                if line.contains("M16") { return "Gemini 3.1 Pro High" }
                if line.contains("M131") { return "Gemini 3.7 Flash" }
                if line.contains("M15") { return "Gemini 3.1 Pro" }
                if line.contains("M11") { return "Gemini 2.5 Pro" }
            }
        }
        return "Gemini"
    }

    public func sampleProcesses(limit: Int = 80) -> [ProcessItem] {
        lock.lock()
        defer { lock.unlock() }

        return autoreleasepool {
            let totalPhysicalRAM = ProcessInfo.processInfo.physicalMemory
            let now = CFAbsoluteTimeGetCurrent()

            // Refresh GUI apps cache every 5 seconds to reduce LaunchServices overhead
            if now - lastGuiCacheTime > 5.0 || guiAppsCache.isEmpty {
                var freshGuiApps: [pid_t: (name: String, bundleId: String?)] = [:]
                for app in NSWorkspace.shared.runningApplications {
                    let pid = app.processIdentifier
                    if pid > 0 {
                        freshGuiApps[pid] = (
                            name: app.localizedName ?? "",
                            bundleId: app.bundleIdentifier
                        )
                    }
                }
                self.guiAppsCache = freshGuiApps
                self.lastGuiCacheTime = now
            }

            var pids = [pid_t](repeating: 0, count: 4096)
            let bytesUsed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(MemoryLayout<pid_t>.stride * pids.count))
            guard bytesUsed > 0 else { return [] }

            let pidCount = Int(bytesUsed) / MemoryLayout<pid_t>.stride
            var results: [ProcessItem] = []
            results.reserveCapacity(min(limit * 2, pidCount))
            var currentPids = Set<pid_t>()

            for i in 0..<pidCount {
                let pid = pids[i]
                if pid <= 0 { continue }
                currentPids.insert(pid)

                var taskInfo = proc_taskinfo()
                let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.stride)
                let res = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskInfoSize)
                guard res == taskInfoSize else { continue }

                let memBytes = taskInfo.pti_resident_size
                let ramPct = totalPhysicalRAM > 0 ? (Double(memBytes) / Double(totalPhysicalRAM)) * 100.0 : 0.0
                let threadCount = Int(taskInfo.pti_threadnum)
                let totalCpuTicks = taskInfo.pti_total_user + taskInfo.pti_total_system
                var cpuPct: Double = 0

                if let prev = previousTimes[pid] {
                    let deltaTicks = totalCpuTicks >= prev.cpuTime ? Double(totalCpuTicks - prev.cpuTime) : 0
                    let deltaSec = now - prev.timestamp
                    if deltaSec > 0.05 {
                        let nano = deltaTicks * Double(timebase.numer) / Double(timebase.denom)
                        let cpuSeconds = nano / 1_000_000_000.0
                        cpuPct = (cpuSeconds / deltaSec) * 100.0
                    }
                }
                previousTimes[pid] = PreviousProcessTimes(cpuTime: totalCpuTicks, timestamp: now)

                var rawName = ""
                var bundleId: String?
                var isUserApp = false

                if let appInfo = guiAppsCache[pid] {
                    rawName = appInfo.name
                    bundleId = appInfo.bundleId
                    isUserApp = true
                }

                if rawName.isEmpty {
                    var nameBuffer = [CChar](repeating: 0, count: 256)
                    proc_name(pid, &nameBuffer, 256)
                    rawName = String(cString: nameBuffer)
                }

                if rawName.isEmpty {
                    rawName = "PID \(pid)"
                }

                // Resolve rich metadata, ancestry, project & friendly name
                let meta = resolveMetadata(pid: pid, rawName: rawName, isGuiApp: isUserApp, bundleId: bundleId)
                let liveUptime = meta.startedAt != nil ? max(0, Date().timeIntervalSince(meta.startedAt!)) : 0

                results.append(ProcessItem(
                    pid: pid,
                    name: meta.friendlyName,
                    rawName: rawName,
                    category: meta.category,
                    commandLine: meta.commandLine,
                    workingDirectory: meta.workingDirectory,
                    projectName: meta.projectName,
                    triggerAppName: meta.triggerAppName,
                    triggerChain: meta.triggerChain,
                    startedAt: meta.startedAt,
                    uptimeSeconds: liveUptime,
                    bundleIdentifier: bundleId,
                    cpuPercentage: max(0.0, cpuPct),
                    memoryBytes: memBytes,
                    memoryPercentage: ramPct,
                    threadCount: threadCount,
                    isUserApp: isUserApp,
                    terminationImpact: meta.impact,
                    parentAppName: meta.parentAppName,
                    aiContext: meta.aiContext
                ))
            }

            // Cleanup stale PIDs
            let stalePids = Set(previousTimes.keys).subtracting(currentPids)
            for sPid in stalePids {
                previousTimes.removeValue(forKey: sPid)
                processMetadataCache.removeValue(forKey: sPid)
            }

            results.sort {
                if abs($0.cpuPercentage - $1.cpuPercentage) > 0.5 {
                    return $0.cpuPercentage > $1.cpuPercentage
                }
                return $0.memoryBytes > $1.memoryBytes
            }

            return Array(results.prefix(limit))
        }
    }

    private func resolveMetadata(pid: pid_t, rawName: String, isGuiApp: Bool, bundleId: String?) -> ProcessMetadata {
        if let cached = processMetadataCache[pid] {
            return cached
        }

        let details = getProcessDetails(pid: pid)
        let execPath = details.path
        let args = details.args
        let cmdSummary = args.isEmpty ? (execPath.isEmpty ? nil : execPath) : args.joined(separator: " ")

        let cwdInfo = getCWD(pid: pid, isGuiApp: isGuiApp)
        let triggerInfo = resolveTriggerApp(pid: pid)

        var friendly = rawName
        var category: ProcessCategory = isGuiApp ? .generalApp : .backgroundService
        var impact = "結束該行程以釋放系統資源"
        var parentApp: String? = triggerInfo.app

        let lowerRaw = rawName.lowercased()
        let lowerPath = execPath.lowercased()
        let fullCmd = (cmdSummary ?? "").lowercased()
        var projName = cwdInfo.project
        var projSuffix = projName != nil ? " [\(projName!)]" : ""
        let triggerPrefix = triggerInfo.app != nil ? "由 \(triggerInfo.app!) 執行的 " : ""

        // 1. Docker
        if lowerRaw.contains("docker") || lowerPath.contains("docker") || lowerRaw.contains("krun") || lowerRaw.contains("containerd") {
            friendly = "Docker Desktop (容器核心)"
            category = .container
            impact = "⚠️ 結束將會中止所有正在運行的 Docker 容器與虛擬環境"
            parentApp = "Docker"
            projName = nil
            projSuffix = ""
        }
        // 2. Claude Code
        else if lowerRaw.contains("claude") || lowerPath.contains("claude") || lowerPath.contains(".local/share/claude") {
            let pName = projName != nil ? " (\(projName!))" : ""
            friendly = "Claude Code\(pName)"
            category = .developer
            impact = "中止目前正在進行的 Claude Code 終端任務\(projSuffix)"
            parentApp = "Claude"
        }
        // 3. Python
        else if lowerRaw.hasPrefix("python") {
            category = .developer
            if fullCmd.contains("pytest") {
                friendly = "Python pytest\(projSuffix)"
                impact = "中止正在執行的單元測試作業\(projSuffix)（\(triggerPrefix)）"
            } else if let script = args.first(where: { $0.hasSuffix(".py") }) {
                let scriptName = URL(fileURLWithPath: script).lastPathComponent
                friendly = "Python (\(scriptName))\(projSuffix)"
                impact = "中止正在執行的 Python 腳本：\(scriptName)\(projSuffix)"
            } else {
                friendly = "Python 執行環境\(projSuffix)"
                impact = "中止正在執行的 Python 運算\(projSuffix)"
            }
        }
        // 4. Node / Bun / Deno
        else if lowerRaw == "node" || lowerRaw == "bun" || lowerRaw == "deno" || lowerRaw == "npm" || lowerRaw == "npx" {
            category = .developer
            if fullCmd.contains("vite") {
                friendly = "Node.js (Vite 前端)\(projSuffix)"
                impact = "關閉 Vite 本地開發伺服器\(projSuffix)"
            } else if fullCmd.contains("next") {
                friendly = "Node.js (Next.js)\(projSuffix)"
                impact = "關閉 Next.js 伺服器\(projSuffix)"
            } else if fullCmd.contains("mcp") {
                friendly = "Node.js (MCP 擴充)\(projSuffix)"
                impact = "關閉 MCP 工具連線服務\(projSuffix)"
            } else if let script = args.first(where: { $0.hasSuffix(".js") || $0.hasSuffix(".ts") }) {
                let scriptName = URL(fileURLWithPath: script).lastPathComponent
                friendly = "Node.js (\(scriptName))\(projSuffix)"
                impact = "中止正在執行的腳本：\(scriptName)\(projSuffix)"
            } else {
                friendly = "Node.js 服務\(projSuffix)"
                impact = "中止 Node.js 執行的開發伺服器或工具\(projSuffix)"
            }
        }
        // 5. Browser Renderers / Helpers
        else if lowerRaw.contains("helper") || lowerRaw.contains("renderer") || lowerRaw.contains("service") {
            category = .browser
            if lowerPath.contains("dia.app") {
                friendly = "Dia 瀏覽器分頁 (Renderer)"
                parentApp = "Dia"
                impact = "關閉該網頁分頁（可重新整理恢復，不影響主瀏覽器）"
            } else if lowerPath.contains("arc.app") || lowerPath.contains("arccore") {
                friendly = "Arc 瀏覽器分頁 (Renderer)"
                parentApp = "Arc"
                impact = "關閉該網頁分頁（可重新整理恢復，不影響主瀏覽器）"
            } else if lowerPath.contains("google chrome") || lowerPath.contains("chrome") {
                friendly = "Chrome 瀏覽器分頁"
                parentApp = "Google Chrome"
                impact = "關閉該網頁分頁（可重新整理恢復，不影響主瀏覽器）"
            } else if lowerPath.contains("chatgpt.app") || lowerRaw.contains("codex") {
                friendly = "ChatGPT 桌面應用 (視窗進程)"
                parentApp = "ChatGPT"
                impact = "關閉 ChatGPT 桌面應用視窗"
            } else if lowerPath.contains("antigravity.app") {
                friendly = "Antigravity AI 編輯器 (輔助進程)"
                parentApp = "Antigravity"
                impact = "結束 Antigravity 編輯器進程"
            } else {
                friendly = "\(rawName) (輔助進程)"
                impact = "關閉該輔助進程"
            }
        }
        // 6. System Services
        else if lowerRaw == "windowserver" {
            friendly = "macOS 視窗管理系統 (WindowServer)"
            category = .system
            impact = "⚠️ 系統核心視窗管理器，結束會強制登出當前使用者並關閉所有視窗！"
        } else if lowerRaw == "coreaudiod" {
            friendly = "macOS 音訊核心服務 (CoreAudio)"
            category = .system
            impact = "⚠️ 系統音訊服務，結束可能導致聲音暫時中斷"
        } else if lowerRaw == "launchd" || lowerRaw == "kernel_task" || lowerRaw == "loginwindow" {
            friendly = "\(rawName) (系統核心)"
            category = .system
            impact = "⚠️ 系統最核心進程，嚴禁強制關閉"
        }
        // 7. Standard Apps
        else if isGuiApp {
            category = .generalApp
            friendly = rawName
            impact = "關閉「\(rawName)」應用程式，未儲存的檔案內容可能遺失"
        }

        let aiCtx = resolveAIContext(
            pid: pid,
            rawName: rawName,
            args: args,
            cmdSummary: cmdSummary,
            cwdInfo: cwdInfo,
            triggerInfo: triggerInfo
        )

        let meta = ProcessMetadata(
            friendlyName: friendly,
            category: category,
            commandLine: cmdSummary,
            workingDirectory: cwdInfo.cwd,
            projectName: projName,
            triggerAppName: triggerInfo.app,
            triggerChain: triggerInfo.chain,
            startedAt: details.startedAt,
            uptimeSeconds: details.uptime,
            impact: impact,
            parentAppName: parentApp,
            aiContext: aiCtx
        )

        processMetadataCache[pid] = meta
        return meta
    }

    private func resolveAIContext(
        pid: pid_t,
        rawName: String,
        args: [String],
        cmdSummary: String?,
        cwdInfo: (cwd: String?, project: String?),
        triggerInfo: (app: String?, chain: [String])
    ) -> AIContextInfo? {
        let fullCmd = (cmdSummary ?? "").lowercased()
        let cwd = (cwdInfo.cwd ?? "").lowercased()
        let chainStr = triggerInfo.chain.joined(separator: " ").lowercased()

        var tool: String? = nil
        var model: String? = nil
        var sessionId: String? = nil
        var taskDesc: String? = nil

        // 1. Antigravity Agent
        if cwd.contains(".gemini/antigravity") || fullCmd.contains("antigravity") || chainStr.contains("antigravity") {
            tool = "Antigravity Agent"
            model = getAntigravityActiveModelName()
            if let brainRange = cwd.range(of: "brain/") {
                let sub = String(cwd[brainRange.upperBound...])
                let comp = sub.components(separatedBy: "/")
                if let uuid = comp.first, uuid.count >= 8 {
                    sessionId = uuid
                }
            }
        }
        // 2. Claude Code
        else if fullCmd.contains("claude") || chainStr.contains("claude") || rawName.lowercased().contains("claude") {
            tool = "Claude Code"
            if let mIdx = args.firstIndex(where: { $0 == "--model" || $0 == "-m" }), mIdx + 1 < args.count {
                model = args[mIdx + 1]
            } else {
                model = "claude-3-7-sonnet"
            }
            if let sIdx = args.firstIndex(where: { $0 == "--session-id" || $0 == "--session" }), sIdx + 1 < args.count {
                sessionId = args[sIdx + 1]
            } else if let sIdx = args.firstIndex(where: { $0.hasPrefix("wf_") }) {
                sessionId = args[sIdx]
            } else if let proj = cwdInfo.project, proj.contains("工作區") {
                sessionId = proj.replacingOccurrences(of: "工作區 ", with: "")
            }
        }
        // 3. Ollama / Local LLM
        else if rawName.lowercased() == "ollama" || fullCmd.contains("ollama run") || fullCmd.contains("llama-server") {
            tool = "Ollama / Local LLM"
            if let rIdx = args.firstIndex(of: "run"), rIdx + 1 < args.count {
                model = args[rIdx + 1]
            } else if let mIdx = args.firstIndex(where: { $0 == "-m" || $0 == "--model" }), mIdx + 1 < args.count {
                model = URL(fileURLWithPath: args[mIdx + 1]).lastPathComponent
            } else {
                model = "Local LLM"
            }
        }
        // 4. Cursor AI
        else if chainStr.contains("cursor") || fullCmd.contains("cursor") {
            tool = "Cursor AI"
            if let mIdx = args.firstIndex(where: { $0 == "--model" }), mIdx + 1 < args.count {
                model = args[mIdx + 1]
            } else {
                model = "Claude 3.5 Sonnet"
            }
        }
        // 5. Parent trigger contains AI
        else if let trigger = triggerInfo.app, trigger.contains("Claude") || trigger.contains("Antigravity") || trigger.contains("Cursor") {
            if trigger.contains("Claude") {
                tool = "Claude Code"
                model = "claude-3-7-sonnet"
            } else if trigger.contains("Antigravity") {
                tool = "Antigravity Agent"
                model = getAntigravityActiveModelName()
            } else {
                tool = "Cursor AI"
                model = "Claude 3.5 Sonnet"
            }
            if let proj = cwdInfo.project, proj.contains("工作區") {
                sessionId = proj.replacingOccurrences(of: "工作區 ", with: "")
            }
        }

        if let validTool = tool {
            if fullCmd.contains("pytest") {
                taskDesc = "pytest 單元測試"
            } else if fullCmd.contains("swift") || fullCmd.contains("cargo") {
                taskDesc = "編譯建構 (Build)"
            } else if fullCmd.contains("npm") || fullCmd.contains("yarn") || fullCmd.contains("bun") {
                taskDesc = "Node 套件執行"
            }
            return AIContextInfo(
                toolName: validTool,
                modelName: model,
                sessionId: sessionId,
                workspaceName: cwdInfo.project,
                taskSummary: taskDesc
            )
        }
        return nil
    }

    private func getProcessDetails(pid: pid_t) -> (path: String, args: [String], startedAt: Date?, uptime: TimeInterval) {
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        let execPath = pathLen > 0 ? String(cString: pathBuffer) : ""

        var startedAt: Date = Date()
        var bsdInfo = proc_bsdinfo()
        let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, bsdSize) == bsdSize {
            if bsdInfo.pbi_start_tvsec > 0 {
                startedAt = Date(timeIntervalSince1970: TimeInterval(bsdInfo.pbi_start_tvsec))
            }
        }
        let uptime = max(0, Date().timeIntervalSince(startedAt))

        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0
        if sysctl(&mib, 3, nil, &size, nil, 0) != 0 || size <= 0 {
            return (execPath, [], startedAt, uptime)
        }

        var buffer = [CChar](repeating: 0, count: size)
        if sysctl(&mib, 3, &buffer, &size, nil, 0) != 0 {
            return (execPath, [], startedAt, uptime)
        }

        var argc: Int32 = 0
        memcpy(&argc, buffer, MemoryLayout<Int32>.size)

        var offset = MemoryLayout<Int32>.size
        while offset < size && buffer[offset] != 0 { offset += 1 }
        while offset < size && buffer[offset] == 0 { offset += 1 }

        var args: [String] = []
        for _ in 0..<min(Int(argc), 16) {
            if offset >= size { break }
            let start = offset
            while offset < size && buffer[offset] != 0 { offset += 1 }
            if start < offset {
                let data = buffer[start..<offset].map { UInt8(bitPattern: $0) }
                if let str = String(bytes: data, encoding: .utf8) {
                    args.append(str)
                }
            }
            offset += 1
        }

        return (execPath, args, startedAt, uptime)
    }

    private func getCWD(pid: pid_t, isGuiApp: Bool) -> (cwd: String?, project: String?) {
        var vnodeInfo = proc_vnodepathinfo()
        let vnodeSize = Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        if proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnodeInfo, vnodeSize) == vnodeSize {
            var cwdStr: String?
            withUnsafePointer(to: &vnodeInfo.pvi_cdir.vip_path) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cStr in
                    let s = String(cString: cStr)
                    if !s.isEmpty && s != "/" {
                        cwdStr = s
                    }
                }
            }
            if let cwd = cwdStr {
                let homeDir = NSHomeDirectory()
                let currentUserName = NSUserName()
                let genericNames: Set<String> = [
                    "data", "containers", "library", "application support", "caches",
                    "preferences", "frameworks", "saved application state", "system",
                    "volumes", "users", "private", "var", "tmp", "applications",
                    currentUserName.lowercased(), "root"
                ]

                // If CWD is user home, generic system directory, or a top-level GUI app, do not treat as a project workspace
                if cwd == homeDir || cwd == "/Users/\(currentUserName)" || isGuiApp {
                    return (cwd, nil)
                }

                var proj: String? = URL(fileURLWithPath: cwd).lastPathComponent
                if let p = proj, genericNames.contains(p.lowercased()) {
                    proj = nil
                }

                // If it is a worktree folder (e.g. wf_fbda0cb8-24c-1), resolve the meaningful context
                if let p = proj, (p.hasPrefix("wf_") || p.hasPrefix("tmp") || p.hasPrefix("scratch")) {
                    let parent = URL(fileURLWithPath: cwd).deletingLastPathComponent().lastPathComponent
                    if !parent.isEmpty && !genericNames.contains(parent.lowercased()) && !parent.hasPrefix("wf_") {
                        proj = "\(parent) [工作區 \(p.prefix(10))]"
                    } else {
                        proj = "工作區 \(p.prefix(10))"
                    }
                }
                return (cwd, proj)
            }
        }
        return (nil, nil)
    }

    private func resolveTriggerApp(pid: pid_t) -> (app: String?, chain: [String]) {
        var current = pid
        var chain: [String] = []
        var visited = Set<pid_t>()
        var aiToolName: String?
        var runnerToolName: String?
        var terminalAppName: String?

        while current > 1 && !visited.contains(current) {
            visited.insert(current)

            // Check if current is a GUI App
            if let appInfo = guiAppsCache[current] {
                let aName = appInfo.name
                terminalAppName = aName
                chain.append("\(aName) (App)")
                break
            }

            var bsdInfo = proc_bsdinfo()
            let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
            if proc_pidinfo(current, PROC_PIDTBSDINFO, 0, &bsdInfo, bsdSize) == bsdSize {
                var nameBuf = [CChar](repeating: 0, count: 256)
                proc_name(current, &nameBuf, 256)
                let name = String(cString: nameBuf)
                let cleanName = name.isEmpty ? "PID \(current)" : name

                // Detect specific developer tools and AI agents in the ancestor chain
                let lower = cleanName.lowercased()
                if current != pid {
                    if aiToolName == nil && (lower.contains("claude") || lower.contains("2.1.") || lower.contains("claudecode")) {
                        aiToolName = "Claude Code"
                        chain.append("Claude Code (Agent)")
                    } else if aiToolName == nil && (lower.contains("antigravity") || lower.contains("agy")) {
                        aiToolName = "Antigravity AI Agent"
                        chain.append("Antigravity (Agent)")
                    } else if aiToolName == nil && lower.contains("cursor") {
                        aiToolName = "Cursor AI"
                        chain.append("Cursor (IDE)")
                    } else if runnerToolName == nil && lower.contains("uv") {
                        runnerToolName = "uv"
                        chain.append("uv (Runner)")
                    } else if runnerToolName == nil && lower.contains("docker") {
                        runnerToolName = "Docker"
                        chain.append("Docker (CLI)")
                    } else if runnerToolName == nil && (lower.contains("npm") || lower.contains("pnpm") || lower.contains("yarn") || lower.contains("npx")) {
                        runnerToolName = cleanName
                        chain.append("\(cleanName) (CLI)")
                    } else if runnerToolName == nil && lower.contains("cargo") {
                        runnerToolName = "Cargo"
                        chain.append("cargo (CLI)")
                    } else {
                        chain.append(cleanName)
                    }
                } else {
                    chain.append(cleanName)
                }

                let ppid = pid_t(bsdInfo.pbi_ppid)
                if ppid <= 1 {
                    break
                }
                current = ppid
            } else {
                break
            }
        }

        var finalAppName: String?
        if let ai = aiToolName {
            var details: [String] = []
            if let runner = runnerToolName {
                details.append("透過 \(runner)")
            }
            if let term = terminalAppName {
                details.append("在 \(term) 中")
            }
            if details.isEmpty {
                finalAppName = ai
            } else {
                finalAppName = "\(ai) (\(details.joined(separator: ", ")))"
            }
        } else if let runner = runnerToolName, let term = terminalAppName {
            finalAppName = "\(runner) (在 \(term) 中)"
        } else if let runner = runnerToolName {
            finalAppName = "\(runner) 執行環境"
        } else if let term = terminalAppName {
            finalAppName = term
        } else {
            finalAppName = chain.last
        }

        return (finalAppName, chain.reversed())
    }

    /// Sample Docker containers
    public func sampleDockerContainers() -> [DockerContainerInfo] {
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastDockerSampleTime < 3.0 && !cachedDockerContainers.isEmpty {
            return cachedDockerContainers
        }

        let dockerBinaries = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/usr/bin/docker", "/Applications/Docker.app/Contents/Resources/bin/docker"]
        guard let dockerPath = dockerBinaries.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return []
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: dockerPath)
        process.arguments = ["stats", "--no-stream", "--format", "{{json .}}"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }

            var containers: [DockerContainerInfo] = []
            let lines = output.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

            for line in lines {
                guard let jsonData = line.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                    continue
                }

                let id = (dict["ID"] as? String) ?? (dict["Container"] as? String) ?? "unknown"
                let name = (dict["Name"] as? String) ?? id
                let cpuStr = (dict["CPUPerc"] as? String) ?? "0.0%"
                let memStr = (dict["MemUsage"] as? String) ?? "0 B"
                let memPercStr = (dict["MemPerc"] as? String) ?? "0.0%"

                let cpuVal = Double(cpuStr.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) ?? 0.0
                let memPercVal = Double(memPercStr.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) ?? 0.0

                containers.append(DockerContainerInfo(
                    containerId: id,
                    name: name,
                    image: (dict["Container"] as? String) ?? "",
                    cpuPercentage: cpuVal,
                    memoryUsage: memStr,
                    memoryPercentage: memPercVal,
                    status: "running",
                    runningFor: "",
                    command: ""
                ))
            }

            self.cachedDockerContainers = containers
            self.lastDockerSampleTime = now
            return containers
        } catch {
            return []
        }
    }

    /// Terminate process
    public func terminateProcess(pid: pid_t, force: Bool = true) -> Bool {
        let signal = force ? SIGKILL : SIGTERM
        return Darwin.kill(pid, signal) == 0
    }

    /// Lower process priority
    public func lowerPriority(pid: pid_t) -> Bool {
        return Darwin.setpriority(PRIO_PROCESS, id_t(pid), 20) == 0
    }
}
