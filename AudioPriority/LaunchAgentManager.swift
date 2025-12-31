import Foundation

struct LaunchAgentManager {
    static let label = "com.audio-priority.daemon"

    static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
            .appendingPathComponent("\(label).plist")
    }

    static var logDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("AudioPriority")
    }

    static var stdoutLogURL: URL {
        logDirectoryURL.appendingPathComponent("stdout.log")
    }

    static var stderrLogURL: URL {
        logDirectoryURL.appendingPathComponent("stderr.log")
    }

    static func install(programPath: String, start: Bool) throws {
        try ensureLaunchAgentsDirectory()
        let fm = FileManager.default
        let hadLogDirectory = fm.fileExists(atPath: logDirectoryURL.path)
        try ensureLogDirectory()
        let existingPlistData = fm.contents(atPath: agentURL.path)
        let wasLoaded = isLoaded()
        let plist = plistDictionary(programPath: programPath)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        do {
            try data.write(to: agentURL, options: .atomic)
            if isLoaded() {
                let result = launchctl(args: ["bootout", serviceDomain(), agentURL.path])
                if result.exitCode != 0 {
                    throw LaunchAgentError.launchctlFailed(command: "bootout", stderr: result.stderr)
                }
            }
            if start {
                let result = launchctl(args: ["bootstrap", serviceDomain(), agentURL.path])
                if result.exitCode != 0 {
                    throw LaunchAgentError.launchctlFailed(command: "bootstrap", stderr: result.stderr)
                }
            }
        } catch {
            if let existingPlistData {
                try? existingPlistData.write(to: agentURL, options: .atomic)
                if wasLoaded {
                    _ = launchctl(args: ["bootstrap", serviceDomain(), agentURL.path])
                }
            } else if fm.fileExists(atPath: agentURL.path) {
                try? fm.removeItem(at: agentURL)
            }
            if !hadLogDirectory, fm.fileExists(atPath: logDirectoryURL.path) {
                let contents = (try? fm.contentsOfDirectory(atPath: logDirectoryURL.path)) ?? []
                if contents.isEmpty {
                    try? fm.removeItem(at: logDirectoryURL)
                }
            }
            throw error
        }
    }

    static func uninstall() throws {
        if isLoaded() {
            let result = launchctl(args: ["bootout", serviceDomain(), agentURL.path])
            if result.exitCode != 0 {
                throw LaunchAgentError.launchctlFailed(command: "bootout", stderr: result.stderr)
            }
        }
        if FileManager.default.fileExists(atPath: agentURL.path) {
            try FileManager.default.removeItem(at: agentURL)
        }
        if FileManager.default.fileExists(atPath: logDirectoryURL.path) {
            try? FileManager.default.removeItem(at: logDirectoryURL)
        }
    }

    static func start() throws {
        if isLoaded() {
            let result = launchctl(args: ["kickstart", "-k", "\(serviceDomain())/\(label)"])
            if result.exitCode != 0 {
                throw LaunchAgentError.launchctlFailed(command: "kickstart", stderr: result.stderr)
            }
        } else {
            let result = launchctl(args: ["bootstrap", serviceDomain(), agentURL.path])
            if result.exitCode != 0 {
                throw LaunchAgentError.launchctlFailed(command: "bootstrap", stderr: result.stderr)
            }
        }
    }

    static func stop() throws {
        if isLoaded() {
            let result = launchctl(args: ["bootout", serviceDomain(), agentURL.path])
            if result.exitCode != 0 {
                throw LaunchAgentError.launchctlFailed(command: "bootout", stderr: result.stderr)
            }
        }
    }

    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: agentURL.path)
    }

    static func isLoaded() -> Bool {
        let result = launchctl(args: ["print", "\(serviceDomain())/\(label)"])
        return result.exitCode == 0
    }

    static func status() -> (installed: Bool, loaded: Bool) {
        let installed = isInstalled()
        let loaded = installed ? isLoaded() : false
        return (installed, loaded)
    }

    static func serviceDomain() -> String {
        let uid = getuid()
        return "gui/\(uid)"
    }

    private static func ensureLogDirectory() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: logDirectoryURL.path) {
            try fm.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
        }
    }

    private static func ensureLaunchAgentsDirectory() throws {
        let fm = FileManager.default
        let parent = agentURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        }
    }

    private static func plistDictionary(programPath: String) -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [programPath, "daemon"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": stdoutLogURL.path,
            "StandardErrorPath": stderrLogURL.path
        ]
    }

    @discardableResult
    private static func launchctl(args: [String]) -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return (1, "", error.localizedDescription)
        }

        process.waitUntilExit()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }

    enum LaunchAgentError: LocalizedError {
        case launchctlFailed(command: String, stderr: String)

        var errorDescription: String? {
            switch self {
            case let .launchctlFailed(command, stderr):
                let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                if detail.isEmpty {
                    return "launchctl \(command) failed."
                }
                return "launchctl \(command) failed: \(detail)"
            }
        }
    }
}
