# QR PowerShell Connect

[Download the Android APK and Windows source](https://github.com/Michaelunkai/qr-powershell-connect/releases/latest) | [Native app guide](docs/NATIVE-ANDROID.md)

A Windows 11 / Android bridge (MIT host tools, Apache-2.0 native app) using Windows OpenSSH, a Tailscale mesh, and certificate-pinned, one-time QR enrollment. The phone generates its own ED25519 key. Windows runs the SSH and mesh services without console windows or a logged-in user.

## What this actually guarantees

Enrollment persists until its SSH key is revoked or its application data is erased. Connectivity requires a running, awake PC, working networking, authenticated Tailscale clients, and tailnet policy permitting TCP 2222. Android must allow the VPN to operate. A scan cannot install apps, approve Android permissions, or log into a Tailscale account. Install PowerShell Connect, open its built-in QR scanner and scan the Windows pairing QR once. Future sessions open directly from its home-screen icon. See [native Android setup](docs/NATIVE-ANDROID.md).

There is no zero-latency networking or sub-millisecond Windows service boot. DNS, network initialization, NAT traversal, relay fallback, SSH negotiation and the user's PowerShell profile all consume time. SSH multiplexing avoids repeated handshakes while an existing connection survives. A broken connection can be retried but cannot restore the in-memory state of a terminated PowerShell process. Service configuration checks cannot prove that an entire Windows boot has no visual artifacts.

## Host installation

Run in an elevated Windows PowerShell 5.1 console from this directory:

For automated setup, run `./Setup.ps1`; after signing into Tailscale, run
`./Setup.ps1 -Pair` to verify and display a fresh pairing QR. The equivalent
individual steps are:

```powershell
py -3.13 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -e .
.\windows\Install-Bridge.ps1
& "$env:ProgramFiles\Tailscale\tailscale.exe" up --unattended=true
.\windows\Test-Bridge.ps1 -Loopback
.\windows\Test-Recovery.ps1   # MeshBind only; run before enrolling a phone
```

Complete the Tailscale login URL when prompted. The installer uses winget to install the signed vendor package and Windows Features to install OpenSSH. An enabled local account already in Administrators is required; the default is the invoking user. It refuses to overwrite an existing SSH service. Port 2222 avoids accidental exposure through rules for port 22. The firewall permits Tailscale IPv4 source addresses; no router forwarding or public SSH listener rule is created. Review any pre-existing broad firewall allow rules and tailnet grants independently.

If Windows Features cannot install because of component-store damage, `Install-Bridge.ps1 -Distribution WinGetPreview` uses Microsoft's standalone `Microsoft.OpenSSH.Preview` server MSI. This is an explicitly selected preview distribution, not the stable in-box Windows capability. It avoids servicing the damaged component store and does not repair Windows. The manifest records which distribution rollback owns. [Microsoft documents the standalone MSI route](https://learn.microsoft.com/en-us/troubleshoot/windows-server/system-management-components/upgrade-in-box-openssh-to-latest-openssh-release).

For an environment where Windows servicing cannot install OpenSSH and firewall changes are unavailable, the tested alternative is:

```powershell
.\windows\Install-Bridge.ps1 -Distribution GitHubZipPreview -IngressPolicy MeshBind
```

This selects Microsoft's 10.0p2 Preview ZIP, checks its pinned SHA-256 and Microsoft executable signatures, and registers only the SSH server service. `MeshBind` requires an authenticated Tailscale host and binds SSH exclusively to its Tailscale IPv4 address and localhost. It does not depend on changing global firewall settings. A protected SYSTEM scheduled task repairs a missing mesh listener at boot and every minute, covering the race where sshd starts before Tailscale has assigned its address. The task runs headlessly with no user profile; ordinary SSH sessions still load the user's normal PowerShell profile. The stable Windows capability remains the default for healthy installations.

The default SSH shell is the system Windows PowerShell executable, with its normal profile behavior. The SSH process receives its own session; it does not attach to a desktop terminal already open. An actual authenticated loopback test verifies the administrator token without disabling UAC or setting LocalAccountTokenFilterPolicy.

## Native Android app (recommended)

Build the signed APK with `windows/Build-NativeApp.ps1 -Action Release`, install `dist/PowerShell-Connect-2.0.1.apk`, then scan a fresh QR inside the app. Generate it with `windows/Start-Pairing.ps1`. The app generates and protects its own device key and pins the Windows host key. Version 2.0.1 requests the already-approved Tailscale VPN when opened and bounds SSH connection attempts so reconnects can recover from a delayed network.

PowerShell Connect has a phone-sized terminal, arrows, Ctrl/Alt/Shift, Esc/Tab, function keys and text input. It starts only when opened, keeps active connections in a foreground service when minimized or dismissed from Recents, and shows an ongoing notification. It has no boot receiver. Disconnect or Force stop ends the app session. Read [build, pairing and lifecycle details](docs/NATIVE-ANDROID.md).

## Legacy Termux client (optional)

Install Tailscale, Termux, and optionally Termux:Widget from their official distributions. Termux add-ons must share the app's signing source. Join the same tailnet, approve Android's VPN prompt, and enable Always-on VPN in Android Settings if supported. Permit background activity for Tailscale. An OEM may still kill background apps. Termux need not run continuously for shortcut-based access.

Copy this repository's `android` directory to the phone, then run in Termux:

```bash
bash /path/to/android/install.sh
```

The installer preserves an existing URL opener as `~/bin/termux-url-opener.before-qrbridge` and delegates non-bridge links to it. It creates `windows` in Termux's executable directory and a `Windows-PowerShell` widget shortcut. Persistent credentials live in Termux-private storage under `~/.ssh/qrbridge`, never shared Android storage.

On Windows, run:

```powershell
.\windows\Start-Pairing.ps1
```

Open `%ProgramData%\QrPowerShellConnect\pairing.png` and scan it. The terminal also renders the QR. The new QR opens a real page on your PC's Tailscale address. Tap **Copy pairing command**, open Termux, paste, and press Enter. Keep the pairing window and Tailscale running. Existing Termux installations need no reinstall. Old QR images pointing to `.invalid` must be replaced by running the script again.

The QR is an administrator enrollment capability valid for fifteen minutes when generated by `Start-Pairing.ps1` (the Python CLI defaults to five). Keep it private. The browser guide uses HTTP port 8080 inside the encrypted Tailscale tunnel; registration still uses certificate-pinned TLS on port 8443. Both listeners bind only the Tailscale IPv4 address. The server accepts one new public key, permits same-key retries until expiry, then deletes its QR and TLS files and closes both listeners. A second device needs a fresh enrollment. The temporary firewall rule is removed when the pairing wrapper exits; after a forced process kill, rerun the wrapper or remove `QrBridge-Pairing` manually. There is no pairing listener on boot.

After pairing:

```bash
windows                       # Interactive PowerShell
windows 'Get-Date'            # Run a command
windows --reconnect           # Retry a broken interactive session with backoff
```

Successful enrollment runs a real SSH command and prints `QRBRIDGE_ANDROID_OK` plus the Windows account. Configure Tailscale key expiry deliberately in the admin console; this project does not silently disable it. Retain device revocation as an emergency control. Networks blocking both direct and relay traffic can prevent connectivity.

## Verification and operations

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
.\windows\Test-Bridge.ps1 -Loopback
.\windows\Revoke-Key.ps1 -PublicKey (Get-Content .\phone-key.pub -Raw).Trim()
.\windows\Uninstall-Bridge.ps1
```

`Test-Bridge.ps1` checks service startup, process Session 0, noninteractive LocalSystem execution, the default shell, mesh login and unattended mode, key ACLs, SSH syntax, and the firewall scope. Loopback creates a temporary ED25519 key, pins the real host key, verifies an administrator token, measures cold-session time, and removes the key in `finally`. Do not run enrollment, revocation, and loopback key-file edits concurrently.

Evidence lives under `%ProgramData%\QrPowerShellConnect\verification.json`. SSH logs are under `%ProgramData%\ssh\logs`, or `QrPowerShellConnect\sshd.log` for the ZIP service. Installation/enrollment/revocation events go to `operations.log`; enrollment errors have their own rotating `enrollment.log`. The mesh readiness task writes `recovery.log`. SSH service failures trigger Service Control Manager restarts at 5, 15, and 60 seconds. Tailscale runs its vendor service and handles normal network changes itself. Authentication expiry requires reauthentication, not endless process restarts.

Installation writes a manifest before changing the host and automatically invokes rollback on failure. Rollback restores the saved default shell and SSH configuration and removes bridge firewall rules and the recovery task. It removes the Windows capability or MSI only if this installation added it; the ZIP service is removed while its binaries remain for audit. Tailscale software, identity, protected public-key records and logs are retained so rollback does not destroy unrelated mesh access. Read `docs/architecture.md` for the state model and recovery limits. Deployment validation and limitations are recorded in `docs/VALIDATION.md`.

## Boot acceptance test

1. Record a passing live verification report and the current boot timestamp.
2. Reboot Windows when other work is saved; leave it at the sign-in screen.
3. On Android over mobile data, open the shortcut and run `whoami` and `Get-Date`.
4. Observe the Windows screen from power-on through login. Record any console artifacts separately from unrelated startup software.
5. Rerun verification and confirm a new boot timestamp, running automatic services, and Session 0.

Reboot and real mobile-network results must be recorded explicitly; passing unit tests does not establish them. See `docs/VALIDATION.md` for results from this build.

## Upstream references

- [Microsoft: Windows OpenSSH configuration and DefaultShell](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh-server-configuration)
- [Microsoft: Windows SSH key management](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement)
- [Tailscale unattended Windows service](https://tailscale.com/docs/how-to/run-unattended)
- [Termux application and installation](https://github.com/termux/termux-app)
- [Termux URL hooks](https://wiki.termux.com/wiki/Intents_and_Hooks)

This project has automated tests and live validation tooling; it is not an independently audited security product. See `SECURITY.md` for the security boundary.
