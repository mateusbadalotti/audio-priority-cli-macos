# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]
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
