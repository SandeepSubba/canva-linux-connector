# Changelog

## 1.1.0

Fixes found while setting up Affinity 3 with Linux-Affinity-Installer (Wine 11.21) on KDE Plasma.

### Fixed

- **Sign-in codes no longer end up in the log.** Wine's and Affinity's output used to be appended to `handler.log`, and some launchers print the whole link, so the one-time sign-in code could be written there. That output now goes to a separate `wine.log`, filtered so link queries and `code=`, `token=`, `state=` and `exchangeId=` values read `<hidden>`. `handler.log` stays one redacted line per link.
- **Launchers that can't take links are refused.** Linux-Affinity-Installer's `affinity-on-linux.exe` treats a link as a file name (`No such file: affinity://…`), so the sign-in never reached Affinity. `setup --exe` now refuses it, and a config that points at it is ignored with a warning; the connector uses `AffinityHook.exe` or `Affinity.exe` instead.

### Added

- `setup` and `doctor` recognise a handler that passes links to such a launcher (such as Linux-Affinity-Installer's `affinity-url-handler.desktop`), explain why sign-in fails, and suggest `setup --force`.
- Documentation: a step-by-step [guide](docs/GUIDE.md), [troubleshooting](docs/TROUBLESHOOTING.md) and [how it works](docs/HOW-IT-WORKS.md).
- Tests for log redaction, file-only launchers and the installer's handler.

## 1.0.0

- First release: `setup`, `doctor`, `paste`, `launch`, `handle` and `uninstall`.
