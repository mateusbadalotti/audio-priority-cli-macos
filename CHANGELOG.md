# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]
### Added
- Default `audio-priority` output now lists priorities; supports `--input`, `--output`, and `--json` filters.
- `--version` flag (prints the version only) and help links to GitHub issues/pull requests.
- `forget-disconnected` command to forget all disconnected devices.

### Changed
- LaunchAgent now runs the internal daemon entrypoint instead of a foreground `run` command.
- Builds now embed version metadata via Info.plist (driven by `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`).
- Release workflow sets `MARKETING_VERSION` from the tag.

### Fixed

### Removed
- Foreground `run` command.
- `priorities` command (superseded by the default output).
- Indexed `forget` command (replaced by `forget-disconnected`).

## [1.1.0]
### Added
- Auto-switching to the highest-priority connected input/output device.
- Manual mode to disable automatic switching.
- Remembered device list with last-seen timestamps.
- LaunchAgent install/start/stop/uninstall workflow for running as a daemon.
- CLI commands for listing devices, setting priorities, forgetting devices, and applying priorities.
- JSON output for status, device list, and priority list (for automation/Raycast).
- `set --uids` support for specifying device UIDs directly.
- Installer copies the binary and framework together; default install path `~/.local/bin`.
- Uninstall cleanup for installed binary/framework (`--keep-binary` to skip removal).

### Changed
- Migrated to Swift 6.2.

### Fixed

### Removed


## [1.0]
### Added
- Initial release

### Changed

### Fixed

### Removed
