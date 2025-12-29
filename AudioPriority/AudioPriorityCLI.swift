import Foundation
import CoreAudio

final class AudioPriorityCLI {
    private let controller = AudioPriorityController()

    func run() {
        var args = CommandLine.arguments
        args.removeFirst()

        guard let command = args.first else {
            printUsage()
            return
        }

        let remaining = Array(args.dropFirst())

        switch command {
        case "run":
            runDaemon()
        case "install":
            handleInstall(remaining)
        case "uninstall":
            handleUninstall()
        case "start":
            handleStart()
        case "stop":
            handleStop()
        case "status":
            handleStatus()
        case "list":
            handleList(remaining)
        case "set":
            handleSet(remaining)
        case "forget":
            handleForget(remaining)
        case "mode":
            handleMode(remaining)
        case "apply":
            handleApply()
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
        let destinationPath = takeOption("--path", from: &working)
        let sourcePath = takeOption("--bin", from: &working) ?? currentExecutablePath()
        let noStart = takeFlag("--no-start", from: &working)

        guard working.isEmpty else {
            print("Unexpected arguments: \(working.joined(separator: ", "))")
            return
        }

        var programPath = sourcePath
        if let destinationPath {
            do {
                programPath = try installBinary(from: sourcePath, to: destinationPath)
            } catch {
                print("Install failed: \(error.localizedDescription)")
                exit(1)
            }
        }

        do {
            try LaunchAgentManager.install(programPath: programPath, start: !noStart)
            print("LaunchAgent installed at \(LaunchAgentManager.agentURL.path)")
        } catch {
            print("Failed to install LaunchAgent: \(error.localizedDescription)")
            exit(1)
        }
    }

    private func handleUninstall() {
        do {
            try LaunchAgentManager.uninstall()
            print("LaunchAgent removed")
        } catch {
            print("Failed to uninstall LaunchAgent: \(error.localizedDescription)")
            exit(1)
        }
    }

    private func handleStart() {
        guard LaunchAgentManager.isInstalled() else {
            print("LaunchAgent not installed. Run: audio-priority install")
            exit(1)
        }
        LaunchAgentManager.start()
        print("LaunchAgent started")
    }

    private func handleStop() {
        LaunchAgentManager.stop()
        print("LaunchAgent stopped")
    }

    private func handleStatus() {
        let status = LaunchAgentManager.status()
        print("LaunchAgent installed: \(status.installed ? "yes" : "no")")
        print("LaunchAgent running: \(status.loaded ? "yes" : "no")")
        print("Mode: \(controller.isCustomMode ? "manual" : "auto")")
    }

    private func handleList(_ args: [String]) {
        var working = args
        let outputOnly = takeFlag("--output", from: &working)
        let inputOnly = takeFlag("--input", from: &working)
        let includeKnown = takeFlag("--known", from: &working)

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

        if includeKnown {
            listKnownDevices(types: types)
            return
        }

        controller.refreshDevices()
        if types.contains(.output) {
            printDevices(title: "Output", devices: controller.outputDevices, currentId: controller.currentOutputId)
        }
        if types.contains(.input) {
            printDevices(title: "Input", devices: controller.inputDevices, currentId: controller.currentInputId)
        }
    }

    private func handleSet(_ args: [String]) {
        var working = args
        let outputOnly = takeFlag("--output", from: &working)
        let inputOnly = takeFlag("--input", from: &working)

        if outputOnly || inputOnly {
            guard !(outputOnly && inputOnly) else {
                print("Usage: audio-priority set --output <uids|indexes...> OR audio-priority set --input <uids|indexes...>")
                exit(1)
            }
            let type: AudioDeviceType = outputOnly ? .output : .input
            guard !working.isEmpty else {
                print("Usage: audio-priority set --\(type == .output ? "output" : "input") <uids|indexes...>")
                exit(1)
            }
            let identifiers = splitIdentifiers(working)
            let uids = resolveUIDs(for: type, identifiers: identifiers)
            controller.setPriorities(type: type, orderedUIDs: uids)
            print("Priority updated for \(type.rawValue) devices")
            return
        }

        guard args.count >= 2 else {
            print("Usage: audio-priority set <input|output> <uid|index...>")
            exit(1)
        }
        let type = parseType(args[0])
        let identifiers = splitIdentifiers(Array(args.dropFirst()))
        let uids = resolveUIDs(for: type, identifiers: identifiers)
        controller.setPriorities(type: type, orderedUIDs: uids)
        print("Priority updated for \(type.rawValue) devices")
    }

    private func handleForget(_ args: [String]) {
        guard let uid = args.first else {
            print("Usage: audio-priority forget <uid>")
            exit(1)
        }
        controller.forgetDevice(uid: uid)
        print("Device forgotten")
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

    private func listKnownDevices(types: [AudioDeviceType]) {
        let known = controller.priorityManager.getKnownDevices()
        for type in types {
            let matching = known.filter { $0.isInput == (type == .input) }
            print("\(type == .input ? "Input" : "Output") Known Devices:")
            if matching.isEmpty {
                print("  (none)")
                continue
            }
            for device in matching {
                print("  \(device.name) | \(device.uid) | last seen \(device.lastSeenRelative)")
            }
        }
    }

    private func printDevices(title: String, devices: [AudioDevice], currentId: AudioObjectID?) {
        print("\(title):")
        if devices.isEmpty {
            print("  (none)")
        } else {
            for (index, device) in devices.enumerated() {
                let marker = device.id == currentId ? "*" : " "
                let connected = device.isConnected ? "connected" : "disconnected"
                print("  [\(index + 1)]\(marker) \(device.name) | \(device.uid) | \(connected)")
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

    private func splitIdentifiers(_ args: [String]) -> [String] {
        var identifiers: [String] = []
        for arg in args {
            let parts = arg.split(separator: ",").map { String($0) }
            for part in parts where !part.isEmpty {
                identifiers.append(part)
            }
        }
        return identifiers
    }

    private func resolveUIDs(for type: AudioDeviceType, identifiers: [String]) -> [String] {
        controller.refreshDevices()
        let devices = type == .output ? controller.outputDevices : controller.inputDevices
        var uids: [String] = []

        for identifier in identifiers {
            if let index = Int(identifier) {
                let zeroBased = index - 1
                guard zeroBased >= 0, zeroBased < devices.count else {
                    print("Invalid index \(index). Use audio-priority list --\(type == .output ? "output" : "input") to see indexes.")
                    exit(1)
                }
                uids.append(devices[zeroBased].uid)
            } else {
                uids.append(identifier)
            }
        }

        return uids
    }

    private func currentExecutablePath() -> String {
        let path = CommandLine.arguments[0]
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private func installBinary(from sourcePath: String, to destinationPath: String) throws -> String {
        let fm = FileManager.default
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

        try fm.copyItem(at: URL(fileURLWithPath: sourcePath), to: finalURL)
        return finalURL.path
    }

    private func printUsage() {
        print("""
Audio Priority CLI

Usage:
  audio-priority run
  audio-priority install [--path <dir|path>] [--bin <path>] [--no-start]
  audio-priority uninstall
  audio-priority start
  audio-priority stop
  audio-priority status
  audio-priority list [--output] [--input] [--known]
  audio-priority set <input|output> <uid|index...>
  audio-priority set --output <uid|index...>
  audio-priority set --input <uid|index...>
  audio-priority forget <uid>
  audio-priority mode <auto|manual>
  audio-priority apply
""")
    }
}
