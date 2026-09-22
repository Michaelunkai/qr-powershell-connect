# Native Android PowerShell app: proposed design

Status: design prepared for user review; app implementation has not started.

## Outcome

Install a standalone, open-source Android application named PowerShell Connect on the user's Samsung Galaxy S25 Ultra. Tapping its launcher icon opens the saved Windows PowerShell connection. Termux is not a runtime dependency. The existing Windows SSH and Tailscale services remain the host transport. Administrator access is the existing configured Windows account's access, not Android root.

## Approach selection

Recommended: adapt the maintained ConnectBot Android SSH application and terminal components into a separately identified application, preserving its upstream notices. This reuses a real SSH transport and terminal emulator while adding this project's enrollment and phone-first connection screen.

Alternative: a new Android shell around SSH and a terminal library. It gives more UI freedom but introduces more integration and lifecycle risk.

Alternative: a browser/PWA terminal. It adds a permanent Windows web gateway and does not satisfy the native standalone application requirement as directly. Do not pursue it.

Before implementation, select and record an upstream commit, inspect its license and build configuration, and pin dependencies. Keep native sources under android-app. Use the contained Android Studio SDK/JBR and a project Gradle wrapper; do not change global development settings.

## Phone interface

Use a midnight navy terminal with high-contrast text, restrained cyan accents, and an adaptive launcher icon showing a white terminal prompt and cyan connection mark. Provide monochrome/themed-icon artwork. Respect system navigation, display cutouts, font scaling, keyboard insets, and light/dark accessibility requirements.

The top bar shows Windows, connection state, and an overflow menu. The main area is an actual VT-compatible terminal with scrollback, text selection, copy/paste, configurable font size, and UTF-8 output. Network work never runs on the UI thread. Recalculate terminal rows and columns and send SSH PTY resize events when the keyboard, orientation, or display size changes.

Keep two touch rows above the Android keyboard, with minimum 48dp targets:

- Esc, Tab, Ctrl, Alt, Shift, keyboard toggle.
- Left, Down, Up, Right, Home, End.

An expandable keys panel provides PgUp, PgDn, Insert, Delete, F1-F12, and commonly needed PowerShell punctuation. Ctrl, Alt, and Shift are visible one-shot modifiers; long press locks a modifier, and another tap clears it. Translate supported combinations into terminal sequences, including Ctrl+C interrupt and Shift+Tab. Do not imply every desktop Windows shortcut has an equivalent in an SSH terminal. Copy and Paste have explicit controls so Ctrl+C remains usable as interrupt. Hardware keyboards remain supported.

## Pairing and credentials

First launch offers in-app QR scanning with contextual camera permission and a paste-link alternative. Decode the existing enrollment payload, generate a new Ed25519 key in app-private storage, pin the enrollment TLS certificate before transmitting the capability, and pin the returned SSH host key. Encrypt stored private-key material with an Android Keystore-backed wrapping key; exclude credentials from backups and logs. Never read or extract Termux's private app files.

The new app needs one authorized enrollment because Android isolates credentials between applications. After that, save the connection and launch it directly. Host-key changes require explicit verification; expired enrollment gets a clear rescan message. No tokens or private keys belong in source code or APK resources. Handle existing browser QR envelopes as data; do not rely on unverified HTTPS app-link ownership.

## Session lifetime

Reuse an active connection while switching away and returning. Maintain a user-visible Android foreground service only while a session is active, with notification actions to return or disconnect and an appropriate documented service type after upstream inspection. Request notification permission contextually. Do not promise invisible indefinite background execution or bypass Android background restrictions.

Reconnect after transient connectivity loss using bounded exponential backoff and cancel retries on explicit disconnect. Never replay commands automatically. A reconnect creates a new shell if the old SSH session was lost; show that distinction. Opening the app after process death reconnects the saved profile. Explain a missing Tailscale connection, offline PC, rejected key, or host-key mismatch in plain language with actionable controls. Do not silently turn off Tailscale authentication expiry or weaken SSH verification.

## Installation and updates

Build a signed APK and preserve its signing key outside the repository with restricted ACLs. Provide a repeatable build/install script and release checksums. Install data-preservingly on the explicitly identified authorized Samsung device when its ADB connection is available. Never uninstall Termux or revoke its working key automatically. A launcher icon appears through normal Android application installation; pinned shortcut placement and any OS prompts remain subject to Android and launcher approval.

## Acceptance criteria

Run unit tests for payload validation, pin rejection, modifier encoding, terminal size calculation, reconnection cancellation, and credential serialization. Run lint and APK build checks. Verify portrait and landscape layouts with keyboard open/closed and enlarged fonts on an emulator before testing the physical phone.

On the phone, confirm the exact installed package and APK identity, successful real SSH authentication, PowerShell administrator identity, output rendering, arrows in command history, Tab completion, Ctrl+C interrupt, selection/copy/paste, function-key panel, rotation, background/return, reconnect, and launch after process recreation. Confirm no enrollment secret appears in logs. Record results separately from unverified conditions.

Physical-device enrollment may require the user to scan one new QR and approve normal Android prompts. Reboot and mobile-network acceptance must be tested explicitly; emulator results are not substitutes. Android cannot guarantee perpetual connectivity or prevent every OS/OEM process termination.

## Current environment evidence

Existing project is clean at commit 7d04d9d before this design. The contained Android SDK and bundled JBR exist under F:\backup\windowsapps\installed\AndroidStudio. No Android build or Maestro device-list MCP tools were exposed during discovery; use the pinned Gradle wrapper and available CLI tools, and distinguish those results in validation reports. No physical device has been selected or modified for this app yet.

## References

- https://github.com/connectbot/connectbot
- https://github.com/connectbot/termlib
- https://developer.android.com/develop/background-work/services/fgs/service-types
- https://developer.android.com/develop/background-work/services/fgs/launch
