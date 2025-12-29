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
        try ensureLogDirectory()
        let plist = plistDictionary(programPath: programPath)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: agentURL, options: .atomic)
        if isLoaded() {
            _ = launchctl(args: ["bootout", serviceDomain(), agentURL.path])
        }
        if start {
            _ = launchctl(args: ["bootstrap", serviceDomain(), agentURL.path])
        }
    }

    static func uninstall() throws {
        if isLoaded() {
            _ = launchctl(args: ["bootout", serviceDomain(), agentURL.path])
        }
        if FileManager.default.fileExists(atPath: agentURL.path) {
            try FileManager.default.removeItem(at: agentURL)
        }
    }

    static func start() {
        if isLoaded() {
            _ = launchctl(args: ["kickstart", "-k", "\(serviceDomain())/\(label)"])
        } else {
            _ = launchctl(args: ["bootstrap", serviceDomain(), agentURL.path])
        }
    }

    static func stop() {
        if isLoaded() {
            _ = launchctl(args: ["bootout", serviceDomain(), agentURL.path])
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
            "ProgramArguments": [programPath, "run"],
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
}
