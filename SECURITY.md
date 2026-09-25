# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| v7.1.1 | Yes |
| earlier versions | No |

## Reporting a vulnerability

Please do not open a public issue for security problems.
Use GitHub **Private Vulnerability Reporting** for this repository instead
(Security tab -> Report a vulnerability).

Issues that qualify include, but are not limited to:

- arbitrary file deletion
- privilege escalation
- command injection
- arbitrary process termination
- injection through process names, paths, or command output
- any unintended network access, telemetry, or data upload

## Do not post in public issues

- usernames
- private paths (for example your home directory name)
- IP addresses, tokens, or API keys
- email addresses
- system passwords
- contents of private files

## Design boundaries

SysMon One is a local, single-file, read-mostly tool:

- no sudo for standard operation
- no network access, no telemetry, no account
- no background daemon or automatic updater
- no automatic deletion of personal files
- unsupported sensor values are shown as N/A rather than fabricated

If you believe any of these boundaries is broken in a release, that is a
security report, not a feature request.
