# Audio Priority CLI

Audio Priority is a macOS CLI daemon that automatically manages audio device priorities. Configure preferred input/output order and let the daemon keep your defaults in sync as devices connect and disconnect.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Priority-based auto-switching**: Always picks the highest-priority connected device.
- **Manual mode**: Disable auto-switching when you want to manage defaults yourself.
- **Device memory**: Remembers devices you've connected (even when disconnected).
- **Boot on login**: LaunchAgent starts the daemon automatically.

## Installation

### Requirements
- macOS 13.0 (Ventura) or later

### Build from Source

```bash
./build.sh
```

The CLI binary will be at `dist/audio-priority`.

### Install + Auto-Start

```bash
# Install LaunchAgent using the current binary
./dist/audio-priority install

# Or copy the binary to a directory and install using that path
./dist/audio-priority install --path ~/.local/bin
```

By default, the `install` command writes a LaunchAgent to `~/Library/LaunchAgents/com.audio-priority.daemon.plist` and starts it.

## Usage

```bash
audio-priority status
audio-priority list --output
audio-priority list --known
audio-priority set output <uid1> <uid2>
audio-priority set --output 1,2,6,3,4,5
audio-priority mode manual
audio-priority mode auto
audio-priority apply
```

### Daemon Control

```bash
audio-priority install          # install LaunchAgent and start it
audio-priority uninstall        # remove LaunchAgent
audio-priority start            # start/refresh LaunchAgent
audio-priority stop             # stop LaunchAgent
audio-priority run              # run in the foreground
```

### Command Reference

```text
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
```

### Command Details

```text
install
  --path <dir|path>  Copy the current binary into a destination dir or path and use that for the LaunchAgent.
  --bin <path>       Use a different binary path without copying.
  --no-start         Write the LaunchAgent but do not start it.

list
  --output  Show output devices only.
  --input   Show input devices only.
  --known   Show remembered devices (including disconnected).

set
  Provide device UIDs or list indexes in the desired order. Missing devices are appended based on known history.

mode
  auto   Enable automatic switching (default behavior).
  manual Disable auto-switching and let you manage defaults yourself.
```

## How It Works

1. **Device Discovery**: Uses CoreAudio to enumerate devices and listen for changes.
2. **Priority Storage**: Priorities are stored in `UserDefaults` by device UID.
3. **Auto-Switching**: When a device appears, the daemon selects the highest-priority connected device (unless manual mode is enabled).

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

## License

MIT License - see [LICENSE](LICENSE) for details.
