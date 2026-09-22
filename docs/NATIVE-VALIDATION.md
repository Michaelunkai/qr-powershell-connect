# Native Android validation — 2026-09-22

These results describe observed tests, not a guarantee of future uptime.

## Release 2.0.1 update

The owner confirmed successful operation after rebooting both devices and explicitly authorized public release. A fresh Windows service/administrator loopback audit passed after the new boot. Android uptime and the VPN log independently confirmed a new boot and Always-on Tailscale initialization.

The signed 2.0.1 update was installed without clearing data. With both PowerShell Connect and Tailscale force-stopped, opening only PowerShell Connect started Tailscale and reached the normal Windows PowerShell prompt. The app requests the vendor connect broadcast only when the mesh VPN is absent. TCP connect and key exchange now have finite timeouts so reconnect backoff can proceed.

Final APK SHA-256: `e37689b6f92e2c0ab2423170e7d42b933ea1abfaaec4048b4374e36e8226e146`. Focused native suite: 22 tests, zero failures/errors. Final release lint has zero errors; upstream warnings remain.

## Earlier 2.0.0 device checks

- Signed OSS release installed on the authorized Samsung SM-S938B without clearing its data. The installed APK was pulled back and its SHA-256 matched the local artifact: `e03cb8f21e4a980661f4277253513c946c91ab2855d24f01fcd7874d237bb0e2`.
- Native real SSH connection to Windows PowerShell over Tailscale; Windows identity/token check returned `True` for membership in Administrators.
- Home-screen shortcut opens the saved Windows connection without repeating enrollment. Pairing survives app force-stop and data-preserving APK update.
- Portrait with Samsung keyboard, landscape terminal, on-screen command-history Up, Ctrl+C interruption, full command text entry, and expanded function/navigation keys tested on the physical phone.
- A 45-second delayed PowerShell command completed after the app was dismissed from Recents and the screen was turned off. The foreground service remained active. A host-side marker and visible `BACKGROUND_OK` terminal output confirmed completion.
- The Android notification displayed `Terminal active in background · Tap to return`. Tapping it returned to the same terminal and output; the app process ID remained unchanged.
- Force stop removed the process and foreground service. Opening the app again connected with its saved identity.
- Idle background sample: 42,769 KiB proportional set size, 172,036 KiB RSS, zero process CPU ticks in a ten-second sample. This is one measurement, not a benchmark or long-duration battery test.
- Final merged release manifest explicitly sets `stopWithTask=false` and `exported=false` for the terminal service. It has no boot-completed receiver. Its only manifest receiver is AndroidX's permission-protected profile installer.
- Native focused suite: 21 tests, zero failures/errors. Final release lint: zero errors, 148 warnings, one hint. Release packaging passed.
- Python host/enrollment suite: 15 tests passed. Live host verification passed automatic LocalSystem services, Session 0, unattended Tailscale, mesh-only listening, strict key ACLs, PowerShell default shell and authenticated administrator loopback.
- Emulator testing also reached the live Windows SSH server. Its temporary authorization key was revoked and its app stopped after testing; the physical phone's key was retained.

## Mobile-network transport check

Wi-Fi was temporarily disabled on the phone with an automatic restoration script armed. The Windows host received two Tailscale replies through the Paris DERP relay (158 ms and 122 ms), confirming mesh reachability through the alternate network path. Android wireless debugging disconnected when Wi-Fi was disabled, so no new interactive terminal command was independently captured during that interval. This is transport evidence, not a universal-network guarantee.

## Still unverified

- Independent visual observation of the complete Windows boot and access specifically before desktop sign-in. Normal post-reboot operation was accepted by the owner.
- Independent process observation before the first app launch after Android boot. The owner tested post-reboot functionality, and the terminal app manifest has no boot receiver.
- Real mobile-data/different-network reconnection and long-duration screen-off/Doze behavior.
- Native camera QR enrollment on the physical handset: deployment used the public-key-only ADB provisioning route. QR parsing/TLS enrollment have automated coverage, but that is not an observed camera-to-session test.
- Landscape with the software keyboard expanded; extreme font scaling and every third-party keyboard.

The owner accepted both-device reboot tests and authorized publication. Unperformed cases above remain explicitly unverified. Millisecond cold boot, unrestricted access from every network, and flawless future operation are not achievable acceptance guarantees.

Local screenshots and detailed deployment evidence remain in ignored `runtime/`, excluding them from public source control. They may contain personal device context. Signing material and enrolled keys remain outside the repository.
