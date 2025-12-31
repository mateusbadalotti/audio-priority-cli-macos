# Audio Priority CLI

Audio Priority is a macOS CLI daemon that automatically manages audio device priorities. Configure preferred input/output order and let the daemon keep your defaults in sync as devices connect and disconnect.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Priority-based auto-switching**: Always picks the highest-priority connected device.
- **Manual mode**: Disable auto-switching when you want to manage defaults yourself.
- **Device memory**: Remembers devices you've connected (even when disconnected).
- **Boot on login**: LaunchAgent starts the daemon automatically.

## Installation

### Requirements
- macOS 14.0 (Sonoma) or later

### Build from Source

```bash
./build.sh
```

The CLI binary will be at `dist/audio-priority`.
The build also outputs `dist/Frameworks/AudioPriorityCore.framework`, which must stay alongside the binary.

### Testing

```bash
xcodebuild -scheme AudioPriorityTests test
```
Note: running tests requires macOS 14 or later.

### Install + Auto-Start

```bash
# Install LaunchAgent using the current binary
./dist/audio-priority install

# Or copy the binary to a directory and install using that path
./dist/audio-priority install --path ~/.local/bin
```

By default, the `install` command copies the binary to `~/.local/bin`, writes a LaunchAgent to `~/Library/LaunchAgents/com.audio-priority.daemon.plist`, and starts it.
If you use `--path`, the installer copies the binary to that location instead. In both cases, it also copies `Frameworks/AudioPriorityCore.framework` alongside the binary.

## Quick Start

```bash
# List output devices (indexes shown in order)
audio-priority list --output

# Set output priority by index (1 = highest priority)
audio-priority set output 2 1 3

# Apply the highest-priority connected devices now
audio-priority apply
```

## Common Commands

```bash
audio-priority [--output] [--input] [--json]   # show priorities (default)
audio-priority list [--output] [--input] [--known] [--json]
audio-priority set <input|output> <indexes...>
audio-priority set <input|output> --uids <uids...>
audio-priority mode <auto|manual>
audio-priority apply
audio-priority forget-disconnected [--output] [--input]
audio-priority status [--json]
audio-priority --version
```

### Daemon Control

```bash
audio-priority install [--path <dir|path>] [--bin <path>] [--no-start]
audio-priority uninstall [--keep-binary]
audio-priority start
audio-priority stop
```

## How It Works

1. **Device Discovery**: Uses CoreAudio to enumerate devices and listen for changes.
2. **Priority Storage**: Priorities are stored in `UserDefaults` by device UID.
3. **Auto-Switching**: When a device appears, the daemon selects the highest-priority connected device (unless manual mode is enabled).

### CoreAudio Notes

- Uses CoreAudio device APIs to list input/output devices and to set system defaults.
- Monitors CoreAudio property changes to react to device connects/disconnects and default changes.
- Requires macOS (CoreAudio is part of the system frameworks).

## Project Structure

```
AudioPriority/
├── main.swift                     # CLI entrypoint
├── AudioPriorityCLI.swift         # Command parsing
├── AudioPriorityController.swift  # Core logic
├── Models/
│   └── AudioDevice.swift
├── Services/
│   ├── AudioDeviceService.swift
│   └── PriorityManager.swift
└── LaunchAgentManager.swift
```

## Targets

- `AudioPriority`: CLI tool.
- `AudioPriorityCore`: shared framework target for core logic.
- `AudioPriorityTests`: unit tests (links against `AudioPriorityCore`).

## License

MIT License - see [LICENSE](LICENSE) for details.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).
