# PowerShell Connect for Android

The native Android app is a maintained project fork of ConnectBot. It requires Android 7 or newer and uses Tailscale to reach the Windows SSH service. Termux is optional and is not used by this app.

## Build and install

Install Android Studio's SDK and bundled JDK, then run from the repository:

```powershell
.\windows\Build-NativeApp.ps1 -Action Test
.\windows\Build-NativeApp.ps1 -Action Lint
.\windows\Build-NativeApp.ps1 -Action Release
```

For a different existing toolchain, pass `-JavaHome`, `-SdkRoot`, and `-GradleHome` explicitly. These affect only the build process environment.

The default contained Android Studio directory is `F:\backup\windowsapps\installed\AndroidStudio`. Use `-StudioRoot` to select another directory with `android-studio\jbr` and `android-sdk` children. The wrapper pins Gradle and all direct library versions. Android SDK licenses must be accepted. This reproduces the build process; byte-identical APK output across different machines is not claimed.

The release APK and SHA-256 are written under `dist`. Signing material remains in the host installer's administrator-only `%ProgramData%\QrPowerShellConnect` directory, outside source control. Keep that signing identity to install future updates without losing app data. Never commit or distribute the signing password or private keystore. The Windows host setup must be completed before a signed release is built.

Install `dist\PowerShell-Connect-2.0.1.apk` using Android's package installer. Approve the notification permission so the active session is visible. Join the same Tailscale network as Windows and allow the VPN. For boot availability, enable Tailscale's Android Always-on VPN option where supported; this is independent of PowerShell Connect's launch-only lifecycle.

## Pair once

On Windows, run the following in an administrator PowerShell:

```powershell
.\windows\Start-Pairing.ps1
```

Open PowerShell Connect and tap **Scan connection QR**. Use its scanner, rather than opening the QR in a browser. The app creates its Ed25519 private key locally, protects it with an Android Keystore wrapping key, and enrolls only the public key using the exact TLS certificate fingerprint embedded in the short-lived QR. The server returns the SSH host key, which the app pins. No private key is embedded in the QR.

An already authorized ADB connection can provision the app without a QR:

```powershell
.\windows\Configure-NativeApp.ps1 -Serial '<verified-adb-serial>'
```

The script verifies the handset model, reads only its newly generated public key, authorizes that key, and supplies public Windows connection metadata. Use `-ExpectedModel` for another deliberately selected phone. It does not copy another application's credentials. Credentials survive normal reboots and app updates but not app data deletion, uninstall, device reset, or key revocation.

## Controls and lifecycle

- Open the PowerShell icon to request the already-approved Tailscale VPN and connect directly. SSH TCP connection attempts have a 15-second timeout and key exchange has a 20-second timeout; failed attempts use bounded reconnect backoff. The session uses the account's normal Windows PowerShell profile.
- The two terminal key rows provide arrows, Esc, Tab, Ctrl, Alt, Shift, Home and End. **More** opens F1–F12, page navigation, editing keys and punctuation.
- Tap a modifier for one key; hold it to lock; tap again to release. Ctrl+C interrupts a foreground PowerShell command. Text input supports composing longer commands before sending them; Paste uses the Android clipboard.
- Home, Back and dismissing the app from Recents leave active sessions running. The foreground-service notification reads **Terminal active in background · Tap to return**. Tapping it returns to the saved Windows session.
- The notification's Disconnect action deliberately closes sessions. Android Force stop and Android's Active apps Stop control stop the app. These controls are respected, not bypassed.
- There is no Android boot receiver, scheduled job or alarm to launch the terminal. After phone reboot, open the icon to reconnect. Tailscale must be available independently.
- While connected, network callbacks, a Wi-Fi lock and SSH keepalives maintain the session; the terminal is not continuously redrawn while its UI is absent. Foreground-service memory and network costs are nonzero. There is no claim of zero battery use.

If the network disappears, reconnect retries use bounded backoff. A new SSH connection starts a new shell if the old session has died; it cannot restore a terminated command's memory. Windows sleep, shutdown, Android process termination, VPN expiry and blocked networks can interrupt access. For jobs that must survive loss of the SSH session, run them through Windows Task Scheduler or another durable job runner.

Android can stop even a foreground service under exceptional resource pressure. An ongoing notification is the supported mechanism for visible background work, not an unlimited execution guarantee. See [Android foreground services](https://developer.android.com/develop/background-work/services/fgs) and [user stopping controls](https://developer.android.com/develop/background-work/services/fgs/handle-user-stopping).

## Validation

See [native validation results](NATIVE-VALIDATION.md). Tests distinguish observed physical-device results from configuration checks and unperformed reboot/network tests. The project does not claim sub-millisecond Windows startup or universal network availability.
