# SysMon One

> Product introduction is being finalized.

SysMon One is currently in its first public testing release.

## Current release

v7.1.1

## Platforms

### macOS
- Apple Silicon
- No sudo
- Local only
- Monitor / Diagnose / Storage Doctor
- Process tree / search / terminate
- Fan readout when supported
- Chinese / English

### Windows
- Single `.cmd`
- Uses built-in PowerShell
- No Python required
- Monitor / process tools / storage tools
- Fan data when exposed by Windows/OEM or supported sensor providers
- Current status: **Beta**

## Quick start

### macOS

Download the macOS ZIP from Releases, extract it, then double-click:

`SysMon-One.command`

If macOS blocks execution, see:
`docs/使用说明.zh-CN.txt`

### Windows

Download the Windows ZIP from Releases, extract it, then double-click:

`SysMon-One-Windows.cmd`

## Main keys

| Key | Function |
|---|---|
| C | Storage Doctor |
| P | Process Center |
| / | Process Search |
| Q | Quit |

## Safety

- No telemetry
- No account
- No background daemon
- No automatic deletion of personal files
- Critical system processes are protected from direct termination
- Unsupported sensor values display N/A instead of fabricated values

## License

MIT
