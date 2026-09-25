# Changelog

## v7.1.1

### Fixed
- Fixed AppleSMC startup crash on affected Apple Silicon systems.
- Correctly read Darwin `mach_task_self_` as a Mach port data symbol.
- Corrected task port usage for `vm_deallocate`.
- Added AppleSMC ABI guard.
- Unsupported fan environments now degrade to `N/A` rather than crashing.

### Added
- macOS fan monitoring.
- Windows single-file build.
- Process Center.
- Process tree.
- Process search.
- CPU/RAM Top processes.
- Safe process termination.
- Storage Doctor.
- Chinese / English output.

### Safety
- No sudo for standard operation.
- No telemetry.
- No daemon.
- Personal files excluded from automatic cleanup.
- Critical system processes protected from direct termination.
