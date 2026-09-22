# Changelog

## 2.0.1 - 2026-09-22

- Opening the native app requests an already-approved Tailscale VPN when the mesh is absent.
- Bound SSH TCP connection and key-exchange waits so automatic reconnect can recover.
- Preserve device pairing, Administrator PowerShell, the phone key panel and visible background sessions.
- Update QR script instructions for the native app; retain the optional Termux client.
- Add automated CI, explicit build-toolchain overrides and a Gradle distribution checksum.
- Record owner-confirmed reboots and independent host, phone and relay-network checks.

## 2.0.0

Initial native Android terminal based on ConnectBot, with pinned QR enrollment, Android Keystore protection, a phone keyboard, home shortcut and foreground-service notification.
