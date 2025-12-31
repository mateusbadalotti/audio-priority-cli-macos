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

## Usage

```bash
audio-priority status
audio-priority status --json
audio-priority list --output
audio-priority list --known
audio-priority list --output --json
audio-priority priorities --json
audio-priority set output 1 2
audio-priority set --output 1,2,6,3,4,5
audio-priority set --output --uids "BuiltInSpeakerDevice" "USB Audio"
audio-priority mode manual
audio-priority mode auto
audio-priority apply
```

### Daemon Control

```bash
audio-priority install          # install LaunchAgent and start it
audio-priority uninstall        # remove LaunchAgent and installed binary
audio-priority start            # start/refresh LaunchAgent
audio-priority stop             # stop LaunchAgent
audio-priority run              # run in the foreground
```

### Command Reference

```text
audio-priority run
audio-priority install [--path <dir|path>] [--bin <path>] [--no-start]
audio-priority uninstall [--keep-binary]
audio-priority start
audio-priority stop
audio-priority status
audio-priority status --json
audio-priority list [--output] [--input] [--known] [--json]
audio-priority priorities [--output] [--input] [--json]
audio-priority set <input|output> <indexes...>
audio-priority set --output <indexes...>
audio-priority set --input <indexes...>
audio-priority set <input|output> --uids <uids...>
audio-priority set --output --uids <uids...>
audio-priority set --input --uids <uids...>
audio-priority forget <input|output> <indexes...>
audio-priority forget --output <indexes...>
audio-priority forget --input <indexes...>
audio-priority forget --known --output <indexes...>
audio-priority forget --known --input <indexes...>
audio-priority mode <auto|manual>
audio-priority apply
```

### Command Details

```text
install
  --path <dir|path>  Copy the current binary into a destination dir or path and use that for the LaunchAgent (defaults to ~/.local/bin).
  --bin <path>       Use a different binary path without copying (skips the default install path).
  --no-start         Write the LaunchAgent but do not start it.

uninstall
  --keep-binary  Keep the installed binary and framework in place.

status
  --json  Output JSON (includes LaunchAgent status, mode, and current default devices).

list
  --output  Show output devices only.
  --input   Show input devices only.
  --known   Show remembered devices (including disconnected).
  --json    Output JSON (includes indexes, uid, name, type, and connection state; known list includes lastSeen).

priorities
  --output  Show output priorities only.
  --input   Show input priorities only.
  --json    Output JSON (includes priority order, names when known, and connection state).

set
  Provide list indexes in the desired order. Missing devices are appended based on known history.
  --uids  Provide device UIDs instead of numeric indexes.

forget
  Provide list indexes to remove devices from the known list (use --known) or from currently connected devices.

mode
  auto   Enable automatic switching (default behavior).
  manual Disable auto-switching and let you manage defaults yourself.
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
