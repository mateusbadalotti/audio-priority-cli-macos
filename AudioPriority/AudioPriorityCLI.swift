import Foundation
import AudioPriorityCore

final class AudioPriorityCLI {
    private let controller = AudioPriorityController()
    private let identifierResolver = IdentifierResolver()

    func run() {
        var args = CommandLine.arguments
        args.removeFirst()

        guard let command = args.first else {
            handlePriorities([])
            return
        }

        let remaining = Array(args.dropFirst())

        if command.hasPrefix("-") {
            if command == "--version" || command == "-v" {
                handleVersion()
                return
            }
            if command == "--help" || command == "-h" || command == "help" {
                printUsage()
                return
            }
            let allowed = Set(["--output", "--input", "--json"])
            if args.allSatisfy({ allowed.contains($0) }) {
                handlePriorities(args)
                return
            }
            print("Unknown option(s): \(args.joined(separator: ", "))\n")
            printUsage()
            return
        }

        switch command {
        case "daemon":
            runDaemon()
        case "install":
            handleInstall(remaining)
        case "uninstall":
            handleUninstall(remaining)
        case "start":
            handleStart()
        case "stop":
            handleStop()
        case "status":
            handleStatus(remaining)
        case "list":
            handleList(remaining)
        case "set":
            handleSet(remaining)
        case "forget-disconnected":
            handleForgetDisconnected(remaining)
        case "mode":
            handleMode(remaining)
        case "apply":
            handleApply()
        case "version", "--version", "-v":
            handleVersion()
        case "help", "-h", "--help":
            printUsage()
        default:
            print("Unknown command: \(command)\n")
            printUsage()
        }
    }

    private func runDaemon() {
        controller.startListening()
        if !controller.isCustomMode {
            controller.applyHighestPriorityDevices()
        }
        RunLoop.main.run()
    }

    private func handleInstall(_ args: [String]) {
        var working = args
        let destinationPathArg = takeOption("--path", from: &working)
        let sourcePathArg = takeOption("--bin", from: &working)
        let sourcePath = sourcePathArg ?? currentExecutablePath()
        let noStart = takeFlag("--no-start", from: &working)

        guard working.isEmpty else {
            print("Unexpected arguments: \(working.joined(separator: ", "))")
            return
        }

        guard validateBinaryPath(sourcePath) else {
            print("Binary not found or not executable: \(sourcePath)")
            exit(1)
        }

        let destinationPath = resolveInstallDestination(pathArg: destinationPathArg, sourcePathArg: sourcePathArg)
        var programPath = sourcePath
        var didCopy = false

        do {
            if let destinationPath {
                programPath = try installBinary(from: sourcePath, to: destinationPath)
                didCopy = true
            }

            try requireFrameworkPresent(near: programPath)

            try LaunchAgentManager.install(programPath: programPath, start: !noStart)
            print("LaunchAgent installed at \(LaunchAgentManager.agentURL.path)")
        } catch {
            if didCopy {
                cleanupInstall(at: programPath)
            }
            print("Install failed: \(error.localizedDescription)")
            exit(1)
        }
    }

    private func handleUninstall(_ args: [String]) {
        var working = args
        let keepBinary = takeFlag("--keep-binary", from: &working)
        guard working.isEmpty else {
            print("Unexpected arguments: \(working.joined(separator: ", "))")
            return
        }

        let programPath = launchAgentProgramPath()
        do {
            try LaunchAgentManager.uninstall()
            print("LaunchAgent removed")
        } catch {
            print("Failed to uninstall LaunchAgent: \(error.localizedDescription)")
            exit(1)
        }
        if !keepBinary, let programPath {
            removeInstalledBinary(at: programPath)
        }
    }

    private func handleStart() {
        guard LaunchAgentManager.isInstalled() else {
            print("LaunchAgent not installed. Run: audio-priority install")
            exit(1)
        }
        do {
            try LaunchAgentManager.start()
            print("LaunchAgent started")
        } catch {
            print("Failed to start LaunchAgent: \(error.localizedDescription)")
            exit(1)
        }
    }

    private func handleStop() {
        do {
            try LaunchAgentManager.stop()
            print("LaunchAgent stopped")
        } catch {
            print("Failed to stop LaunchAgent: \(error.localizedDescription)")
            exit(1)
        }
    }

    private func handleStatus() {
        handleStatus([])
    }

    private func handleStatus(_ args: [String]) {
        var working = args
        let jsonOutput = takeFlag("--json", from: &working)

        guard working.isEmpty else {
            print("Unexpected arguments: \(working.joined(separator: ", "))")
            return
        }

        let status = LaunchAgentManager.status()
        if jsonOutput {
            controller.refreshDevices()
            let payload = AudioPriorityJSONStatusPayload(
                launchAgentInstalled: status.installed,
                launchAgentRunning: status.loaded,
                mode: controller.isCustomMode ? "manual" : "auto",
                defaultInput: AudioPriorityJSON.defaultDevice(id: controller.currentInputId, devices: controller.inputDevices),
                defaultOutput: AudioPriorityJSON.defaultDevice(id: controller.currentOutputId, devices: controller.outputDevices)
            )
            printJSON(payload)
            return
        }

        print("LaunchAgent installed: \(status.installed ? "yes" : "no")")
        print("LaunchAgent running: \(status.loaded ? "yes" : "no")")
        print("Mode: \(controller.isCustomMode ? "manual" : "auto")")
    }

    private func handleList(_ args: [String]) {
        var working = args
        let outputOnly = takeFlag("--output", from: &working)
        let inputOnly = takeFlag("--input", from: &working)
        let includeKnown = takeFlag("--known", from: &working)
        let jsonOutput = takeFlag("--json", from: &working)

        guard working.isEmpty else {
            print("Unexpected arguments: \(working.joined(separator: ", "))")
            return
        }

        let types: [AudioDeviceType]
        if outputOnly || inputOnly {
            var selected: [AudioDeviceType] = []
            if outputOnly { selected.append(.output) }
            if inputOnly { selected.append(.input) }
            types = selected
        } else {
            types = [.output, .input]
        }

        if jsonOutput {
            printJSONList(types: types, includeKnown: includeKnown)
            return
        }

        if includeKnown {
            listKnownDevices(types: types)
            return
        }

        controller.refreshDevices()
        if types.contains(.output) {
            printDevices(title: "Output", devices: controller.outputDevices)
        }
        if types.contains(.input) {
            printDevices(title: "Input", devices: controller.inputDevices)
        }
    }

    private func handlePriorities(_ args: [String]) {
        var working = args
        let outputOnly = takeFlag("--output", from: &working)
        let inputOnly = takeFlag("--input", from: &working)
        let jsonOutput = takeFlag("--json", from: &working)

        guard working.isEmpty else {
            print("Unexpected arguments: \(working.joined(separator: ", "))")
            return
        }

        let types: [AudioDeviceType]
        if outputOnly || inputOnly {
            var selected: [AudioDeviceType] = []
            if outputOnly { selected.append(.output) }
            if inputOnly { selected.append(.input) }
            types = selected
        } else {
            types = [.output, .input]
        }

        controller.refreshDevices()
        let known = controller.priorityManager.getKnownDevices()
        let connected = controller.outputDevices + controller.inputDevices

        if jsonOutput {
            let payload = AudioPriorityJSON.prioritiesPayload(
                priorityOutput: controller.priorityManager.getPriorityUIDs(type: .output),
                priorityInput: controller.priorityManager.getPriorityUIDs(type: .input),
                knownDevices: known,
                connectedDevices: connected
            )
            let filtered = AudioPriorityJSONPrioritiesPayload(
                output: types.contains(.output) ? payload.output : [],
                input: types.contains(.input) ? payload.input : []
            )
            printJSON(filtered)
            return
        }

        if types.contains(.output) {
            printPriorityList(title: "Output Priority", type: .output, known: known)
        }
        if types.contains(.input) {
            printPriorityList(title: "Input Priority", type: .input, known: known)
        }
    }

    private func handleSet(_ args: [String]) {
        var working = args
        let outputOnly = takeFlag("--output", from: &working)
        let inputOnly = takeFlag("--input", from: &working)
        let uidsMode = takeFlag("--uids", from: &working)

        if outputOnly || inputOnly {
            guard !(outputOnly && inputOnly) else {
                print("Usage: audio-priority set --output <indexes...> OR audio-priority set --input <indexes...>")
                exit(1)
            }
            let type: AudioDeviceType = outputOnly ? .output : .input
            guard !working.isEmpty else {
                print("Usage: audio-priority set --\(type == .output ? "output" : "input") <indexes...>")
                exit(1)
            }
            if uidsMode {
                let uids = identifierResolver.splitIdentifiers(working)
                guard !uids.isEmpty else {
                    print("Usage: audio-priority set --\(type == .output ? "output" : "input") --uids <uids...>")
                    exit(1)
                }
                controller.setPriorities(type: type, orderedUIDs: uids, refresh: false)
            } else {
                let identifiers = identifierResolver.splitIdentifiers(working)
                guard !identifiers.isEmpty else {
                    print("Usage: audio-priority set --\(type == .output ? "output" : "input") <indexes...>")
                    exit(1)
                }
                controller.refreshDevices()
                let devices = type == .output ? controller.outputDevices : controller.inputDevices
                let uids = resolveUIDsOrExit(for: type, identifiers: identifiers, devices: devices, listKnown: false)
                controller.setPriorities(type: type, orderedUIDs: uids, refresh: false)
            }
            print("Priority updated for \(type.rawValue) devices")
            return
        }

        guard args.count >= 2 else {
            print("Usage: audio-priority set <input|output> <indexes...>")
            exit(1)
        }
        var positional = args
        let positionalUidsMode = positional.contains("--uids")
        if positionalUidsMode {
            positional.removeAll { $0 == "--uids" }
        }
        guard !positional.isEmpty else {
            print("Usage: audio-priority set <input|output> <indexes...>")
            exit(1)
        }
        let type = parseType(positional[0])
        let remaining = Array(positional.dropFirst())
        if positionalUidsMode {
            let uids = identifierResolver.splitIdentifiers(remaining)
            guard !uids.isEmpty else {
                print("Usage: audio-priority set <input|output> --uids <uids...>")
                exit(1)
            }
            controller.setPriorities(type: type, orderedUIDs: uids, refresh: false)
        } else {
            let identifiers = identifierResolver.splitIdentifiers(remaining)
            guard !identifiers.isEmpty else {
                print("Usage: audio-priority set <input|output> <indexes...>")
                exit(1)
            }
            controller.refreshDevices()
            let devices = type == .output ? controller.outputDevices : controller.inputDevices
            let uids = resolveUIDsOrExit(for: type, identifiers: identifiers, devices: devices, listKnown: false)
            controller.setPriorities(type: type, orderedUIDs: uids, refresh: false)
        }
        print("Priority updated for \(type.rawValue) devices")
    }

    private func handleForgetDisconnected(_ args: [String]) {
        var working = args
        let outputOnly = takeFlag("--output", from: &working)
        let inputOnly = takeFlag("--input", from: &working)

        guard !(outputOnly && inputOnly) else {
            print("Usage: audio-priority forget-disconnected [--output | --input]")
            exit(1)
        }

        guard working.isEmpty else {
            print("Unexpected arguments: \(working.joined(separator: ", "))")
            exit(1)
        }

        controller.refreshDevices()
        let known = controller.priorityManager.getKnownDevices()
        let connectedOutputs = Set(controller.outputDevices.map { $0.uid })
        let connectedInputs = Set(controller.inputDevices.map { $0.uid })
        let includeOutputs = !inputOnly
        let includeInputs = !outputOnly

        var count = 0
        for device in known {
            if device.isInput {
                guard includeInputs, !connectedInputs.contains(device.uid) else { continue }
                controller.forgetDevice(uid: device.uid, type: .input)
                count += 1
            } else {
                guard includeOutputs, !connectedOutputs.contains(device.uid) else { continue }
                controller.forgetDevice(uid: device.uid, type: .output)
                count += 1
            }
        }

        if count == 0 {
            print("No disconnected devices to forget")
        } else if count == 1 {
            print("Forgot 1 disconnected device")
        } else {
            print("Forgot \(count) disconnected devices")
        }
    }

    private func handleMode(_ args: [String]) {
        guard let value = args.first else {
            print("Usage: audio-priority mode <auto|manual>")
            exit(1)
        }
        let normalized = value.lowercased()
        let enabled: Bool
        switch normalized {
        case "auto", "automatic", "off", "false", "0":
            enabled = false
        case "manual", "on", "true", "1":
            enabled = true
        default:
            print("Unknown mode: \(value)")
            exit(1)
        }
        controller.setCustomMode(enabled)
        print("Mode set to \(enabled ? "manual" : "auto")")
    }

    private func handleApply() {
        controller.applyHighestPriorityDevices()
        print("Applied highest priority devices")
    }

    private func handleVersion() {
        print(versionString())
    }

    private func printPriorityList(title: String, type: AudioDeviceType, known: [StoredDevice]) {
        let uids = controller.priorityManager.getPriorityUIDs(type: type)
        print("\(title):")
        guard !uids.isEmpty else {
            print("  (none)")
            return
        }
        let knownByKey = Dictionary(uniqueKeysWithValues: known.map { device in
            ("\(device.uid)::\(device.isInput)", device)
        })
        for (index, uid) in uids.enumerated() {
            let key = "\(uid)::\(type == .input)"
            let name = knownByKey[key]?.name ?? "Unknown device"
            print("  \(index + 1) - \(name) | \(uid)")
        }
    }

    private func listKnownDevices(types: [AudioDeviceType]) {
        let known = controller.priorityManager.getKnownDevices()
        for type in types {
            let matching = known.filter { $0.isInput == (type == .input) }
            print("\(type == .input ? "Input" : "Output") Known Devices:")
            if matching.isEmpty {
                print("  (none)")
                continue
            }
            for (index, device) in matching.enumerated() {
                print("  \(index + 1) - \(device.name) | last seen \(device.lastSeenRelative)")
            }
        }
    }

    private func printJSONList(types: [AudioDeviceType], includeKnown: Bool) {
        let payload: AudioPriorityJSONListPayload
        if includeKnown {
            controller.refreshDevices()
            let known = controller.priorityManager.getKnownDevices()
            let connected = controller.outputDevices + controller.inputDevices
            payload = AudioPriorityJSON.listPayload(knownDevices: known, connectedDevices: connected)
        } else {
            controller.refreshDevices()
            payload = AudioPriorityJSON.listPayload(
                known: false,
                outputDevices: controller.outputDevices,
                inputDevices: controller.inputDevices
            )
        }

        let filtered = AudioPriorityJSONListPayload(
            known: payload.known,
            output: types.contains(.output) ? payload.output : [],
            input: types.contains(.input) ? payload.input : []
        )

        printJSON(filtered)
    }

    private func printJSON<T: Encodable>(_ payload: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(payload)
            if let text = String(data: data, encoding: .utf8) {
                print(text)
            }
        } catch {
            writeStderr("Failed to encode JSON output: \(error.localizedDescription)")
            exit(1)
        }
    }

    private func printDevices(title: String, devices: [AudioDevice]) {
        print("\(title):")
        if devices.isEmpty {
            print("  (none)")
        } else {
            for (index, device) in devices.enumerated() {
                print("  \(index + 1) - \(device.name)")
            }
        }
    }

    private func parseType(_ value: String) -> AudioDeviceType {
        switch value.lowercased() {
        case "input", "in", "mic", "microphone":
            return .input
        case "output", "out", "speaker", "speakers":
            return .output
        default:
            print("Unknown type: \(value)")
            exit(1)
        }
    }

    private func takeOption(_ name: String, from args: inout [String]) -> String? {
        guard let index = args.firstIndex(of: name) else { return nil }
        let valueIndex = args.index(after: index)
        guard valueIndex < args.count else { return nil }
        let value = args[valueIndex]
        args.removeSubrange(index...valueIndex)
        return value
    }

    private func takeFlag(_ name: String, from args: inout [String]) -> Bool {
        guard let index = args.firstIndex(of: name) else { return false }
        args.remove(at: index)
        return true
    }

    private func resolveUIDsOrExit(for type: AudioDeviceType, identifiers: [String], devices: [AudioDevice], listKnown: Bool) -> [String] {
        do {
            return try identifierResolver.resolveUIDs(type: type, identifiers: identifiers, devices: devices)
        } catch {
            print(error.localizedDescription)
            if listKnown {
                print("Use audio-priority list --known --\(type == .output ? "output" : "input") to see indexes.")
            } else {
                print("Use audio-priority list --\(type == .output ? "output" : "input") to see indexes.")
            }
            exit(1)
        }
    }

    private func currentExecutablePath() -> String {
        let path = CommandLine.arguments[0]
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private func resolveInstallDestination(pathArg: String?, sourcePathArg: String?) -> String? {
        if let pathArg {
            return expandTilde(pathArg)
        }
        guard sourcePathArg == nil else {
            return nil
        }
        return defaultInstallPath()
    }

    private func defaultInstallPath() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local")
            .appendingPathComponent("bin")
            .path
    }

    private func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    private func installBinary(from sourcePath: String, to destinationPath: String) throws -> String {
        let fm = FileManager.default
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let destinationURL = URL(fileURLWithPath: destinationPath)
        let destinationIsDir = (try? destinationURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let finalURL: URL

        if destinationIsDir {
            finalURL = destinationURL.appendingPathComponent("audio-priority")
        } else {
            finalURL = destinationURL
        }

        let parentURL = finalURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: parentURL.path) {
            try fm.createDirectory(at: parentURL, withIntermediateDirectories: true)
        }

        if fm.fileExists(atPath: finalURL.path) {
            try fm.removeItem(at: finalURL)
        }

        let destinationFrameworkURL = frameworkURL(near: finalURL)

        do {
            try fm.copyItem(at: sourceURL, to: finalURL)
            try copyFrameworkIfPresent(from: sourceURL, to: finalURL)
            return finalURL.path
        } catch {
            if fm.fileExists(atPath: finalURL.path) {
                try? fm.removeItem(at: finalURL)
            }
            if fm.fileExists(atPath: destinationFrameworkURL.path) {
                try? fm.removeItem(at: destinationFrameworkURL)
            }
            let frameworkDir = destinationFrameworkURL.deletingLastPathComponent()
            if let contents = try? fm.contentsOfDirectory(atPath: frameworkDir.path), contents.isEmpty {
                try? fm.removeItem(at: frameworkDir)
            }
            throw error
        }
    }

    private func copyFrameworkIfPresent(from sourceURL: URL, to binaryURL: URL) throws {
        let fm = FileManager.default
        let sourceFrameworkURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent("Frameworks")
            .appendingPathComponent("AudioPriorityCore.framework")

        let destinationFrameworkURL = frameworkURL(near: binaryURL)
        let destinationFrameworkDir = destinationFrameworkURL.deletingLastPathComponent()

        guard fm.fileExists(atPath: sourceFrameworkURL.path) else { return }

        if !fm.fileExists(atPath: destinationFrameworkDir.path) {
            try fm.createDirectory(at: destinationFrameworkDir, withIntermediateDirectories: true)
        }

        if fm.fileExists(atPath: destinationFrameworkURL.path) {
            try fm.removeItem(at: destinationFrameworkURL)
        }

        try fm.copyItem(at: sourceFrameworkURL, to: destinationFrameworkURL)
    }

    private func requireFrameworkPresent(near programPath: String) throws {
        let fm = FileManager.default
        let frameworkURL = frameworkURL(near: programPath)

        if !fm.fileExists(atPath: frameworkURL.path) {
            throw InstallError(message: "AudioPriorityCore.framework not found next to the binary. Keep Frameworks/AudioPriorityCore.framework alongside the executable.")
        }
    }

    private func launchAgentProgramPath() -> String? {
        let plistURL = LaunchAgentManager.agentURL
        guard let data = try? Data(contentsOf: plistURL) else {
            return nil
        }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        if let programArguments = plist["ProgramArguments"] as? [String], let programPath = programArguments.first {
            return programPath
        }
        if let programPath = plist["Program"] as? String {
            return programPath
        }
        return nil
    }

    private func removeInstalledBinary(at programPath: String) {
        let url = URL(fileURLWithPath: programPath)
        guard url.lastPathComponent == "audio-priority" else {
            writeStderr("Skipping binary removal (unexpected path): \(programPath)")
            return
        }

        let fm = FileManager.default
        let frameworkURL = frameworkURL(near: url)

        if fm.fileExists(atPath: frameworkURL.path) {
            do {
                try fm.removeItem(at: frameworkURL)
            } catch {
                writeStderr("Failed to remove framework: \(error.localizedDescription)")
            }
        }

        if fm.fileExists(atPath: url.path) {
            do {
                try fm.removeItem(at: url)
                print("Removed binary at \(programPath)")
            } catch {
                writeStderr("Failed to remove binary: \(error.localizedDescription)")
            }
        }

        let frameworkDir = frameworkURL.deletingLastPathComponent()
        if let contents = try? fm.contentsOfDirectory(atPath: frameworkDir.path), contents.isEmpty {
            try? fm.removeItem(at: frameworkDir)
        }
    }

    private func writeStderr(_ message: String) {
        guard let data = (message + "\n").data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }

    private func validateBinaryPath(_ path: String) -> Bool {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }
        return fm.isExecutableFile(atPath: path)
    }

    private func frameworkURL(near programPath: String) -> URL {
        frameworkURL(near: URL(fileURLWithPath: programPath))
    }

    private func frameworkURL(near binaryURL: URL) -> URL {
        binaryURL.deletingLastPathComponent()
            .appendingPathComponent("Frameworks")
            .appendingPathComponent("AudioPriorityCore.framework")
    }

    private func cleanupInstall(at programPath: String) {
        let fm = FileManager.default
        let binaryURL = URL(fileURLWithPath: programPath)
        let frameworkURL = frameworkURL(near: binaryURL)

        if fm.fileExists(atPath: frameworkURL.path) {
            try? fm.removeItem(at: frameworkURL)
        }
        if fm.fileExists(atPath: binaryURL.path) {
            try? fm.removeItem(at: binaryURL)
        }

        let frameworkDir = frameworkURL.deletingLastPathComponent()
        if let contents = try? fm.contentsOfDirectory(atPath: frameworkDir.path), contents.isEmpty {
            try? fm.removeItem(at: frameworkDir)
        }
    }

    private struct InstallError: LocalizedError {
        let message: String

        var errorDescription: String? {
            message
        }
    }

    private func printUsage() {
        print("""
Audio Priority CLI

Usage:
  audio-priority [--output] [--input] [--json]
  audio-priority install [--path <dir|path>] [--bin <path>] [--no-start]
  audio-priority uninstall [--keep-binary]
  audio-priority start
  audio-priority stop
  audio-priority status [--json]
  audio-priority list [--output] [--input] [--known] [--json]
  audio-priority set <input|output> <indexes...>
  audio-priority set --output <indexes...>
  audio-priority set --input <indexes...>
  audio-priority set <input|output> --uids <uids...>
  audio-priority set --output --uids <uids...>
  audio-priority set --input --uids <uids...>
  audio-priority forget-disconnected [--output | --input]
  audio-priority mode <auto|manual>
  audio-priority apply
  audio-priority --version
  audio-priority --help

Project:
  Issues: https://github.com/mateusbadalotti/audio-priority-cli-macos/issues
  Pull requests: https://github.com/mateusbadalotti/audio-priority-cli-macos/pulls
""")
    }
}

private func versionString() -> String {
    let bundle = Bundle.main
    let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    if let short, !short.isEmpty {
        return short
    }

    if let build, !build.isEmpty {
        return build
    }

    return "version unknown"
}
