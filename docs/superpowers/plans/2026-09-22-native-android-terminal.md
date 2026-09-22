# Native Android Terminal Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task. The user approved autonomous execution on 2026-09-22.

**Goal:** Build, install, configure and validate PowerShell Connect on the authorized Samsung phone.

**Architecture:** Vendor ConnectBot at commit 30b6d7315d2ed5c11f3c92e45e60d57d712315e0. Add a launcher/enrollment activity, Keystore wrapping, a two-row terminal key panel and project-local build/provisioning scripts. Keep the existing Windows SSH/Tailscale bridge.

**Tech Stack:** Kotlin, Compose, Android Keystore, ConnectBot sshlib/termlib, Gradle, PowerShell, authorized ADB.

## Build foundation
- [x] Inspect upstream license, manifest, Gradle versions and available SDK.
- [x] Identify authorized handset by SM-S938B model.
- [x] Produce baseline `:app:assembleOssDebug`; address environment failures without global configuration changes.
- [x] Set application ID `org.qrbridge.powershell`, backup disabled, dedicated launcher and icon.

## Enrollment and launch
- [x] Add `bridge/BridgeKeyVault.kt`: AES-GCM Android Keystore wrapping for Ed25519 private bytes; decrypt only for authentication.
- [x] Add `bridge/BridgeEnrollment.kt`: validate mesh address, port, expiry, token and TLS pin; bound responses; save exact SSH host key.
- [x] Add `bridge/BridgeActivity.kt`: first-run QR/paste enrollment, progress/error screen, saved-host direct launch, public-only ADB provisioning files.
- [x] Integrate vault decoding into `PubkeyUtils.kt`; preserve ordinary upstream key formats.
- [x] Add `windows/Configure-NativeApp.ps1`: use explicit device serial, read only the app-generated public key, authorize under key-store lock, deliver public connection metadata, launch and verify package. Do not transfer enrollment tokens or extract Termux credentials.

## Phone interface
- [x] Add `bridge/BridgeKeyboard.kt`: two 48dp rows, one-shot/locked modifiers, arrows, Esc/Tab, keyboard switch and expanded function/navigation/punctuation keys.
- [x] Replace keyboard renderer for native bridge; reserve actual measured keyboard height in terminal layout.
- [x] Preserve modifier state when sending Tab so Shift+Tab works.
- [x] Set readable phone defaults, scrollback, persistent key panel, themed adaptive icon and blue/cyan palette.

## Validation and delivery
- [x] Add unit tests for payload validation, host rejection and modifier behavior; run narrow tests then lint/APK build.
- [x] Build signed release, keep signing material outside Git, generate checksum and reproducible build instructions.
- [x] Install without clearing data; provision via the authorized device public key.
- [x] Verify real PowerShell output, keyboard controls, orientation, background/return and direct launcher connection; record screenshots and limitations.
- [x] Commit source, upstream notices, release instructions and validation evidence. Preserve existing Termux access.

## Publication acceptance gate
- [x] Verify background command completion after Recents dismissal, notification return, and Force stop on the physical phone.
- [x] Record owner-confirmed Windows reboot acceptance and independently verify post-boot services. Pre-login visual observation remains unverified.
- [x] Record owner-confirmed Android reboot acceptance and independently verify uptime and Always-on VPN initialization.
- [x] Verify alternate-network Tailscale relay reachability with Wi-Fi disabled. Native camera enrollment and an interactive command over mobile data remain separately unverified.
- [ ] Publish a new public GitHub repository after the remaining device acceptance tests pass.
