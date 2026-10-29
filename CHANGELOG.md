# Changelog

## 2.0.2 - 2026-10-30

- SSH liveness probe: on open, on return to the app and every 45 s while visible, a request that gets no reply within 10 s drops a frozen or half-open link and redials automatically.
- Two-row key bar (Esc, Tab, Ctrl, Alt, Shift, ^C/^S/^X, arrows, Home/End, PgUp/PgDn), plus a `⋯` sheet with nano, PSReadLine, F1–F12 and symbol keys.
- Larger default font and terminal layout tuned for nano and full-screen tools.
- New adaptive icon (light/dark/monochrome, every launcher shape) and matching notification icon.
- `Repair-Bridge.ps1` now also re-enables and restarts a stopped or disabled Tailscale service, starts sshd after a mesh outage, and restarts sshd when its Tailscale listener is missing.
- sshd config: `AllowUsers` is written from a single normalised lowercase account name.
- Beautiful README, screenshots and release assets (APK, PC setup zip, SHA256 sums).

## 2.0.1 - 2026-09-22

- Opening the native app requests an already-approved Tailscale VPN when the mesh is absent.
- Bound SSH TCP connection and key-exchange waits so automatic reconnect can recover.
- Preserve device pairing, Administrator PowerShell, the phone key panel and visible background sessions.
- Update QR script instructions for the native app; retain the optional Termux client.
- Add automated CI, explicit build-toolchain overrides and a Gradle distribution checksum.
- Record owner-confirmed reboots and independent host, phone and relay-network checks.

## 2.0.0

Initial native Android terminal based on ConnectBot, with pinned QR enrollment, Android Keystore protection, a phone keyboard, home shortcut and foreground-service notification.
