# Architecture and operational contract

## Selected design

Windows OpenSSH plus Tailscale provides native service lifetime and NAT traversal. Raw WireGuard would require reachable endpoints or a managed rendezvous server; a custom reverse-shell daemon would duplicate mature authentication and terminal handling. Windows service definitions are installed by Windows Features and the Tailscale package, or by direct registration of the verified Microsoft ZIP server. No user-logon task is needed. The optional MeshBind mode adds a headless SYSTEM startup and periodic readiness task.

The SSH listener is IPv4, port 2222, public-key only, restricted to the selected local administrator. Its dedicated authorized-keys file is outside the shared `administrators_authorized_keys` file, preventing enrollment keys from authenticating as every local administrator. Tailscale provides encrypted routing; ordinary OpenSSH supplies SSH on Windows. This does not depend on Tailscale SSH server support for Windows.

In Firewall mode, the Windows firewall restricts the listener to tailnet source addresses. In MeshBind mode, sshd binds only localhost and the recorded Tailscale IPv4 address. Windows' host network model and any third-party forwarding must still preserve interface isolation; this is not a replacement for a healthy host firewall. Tailscale addresses persist across ordinary network changes and reboots, but deleting/recreating a tailnet device can change its address and requires reconfiguration and pairing. The SYSTEM task waits up to sixty seconds for the address, restarts SSH only if the mesh listener is missing, and repeats each minute. A stopped or revoked Tailscale connection is not silently reauthenticated.

## Enrollment protocol v1

The QR contains `http://<Tailscale-IPv4>:8080/enroll#BASE64URL(JSON)` with fields:

| Field | Meaning |
|---|---|
| v | Integer protocol version, 1 |
| host | Host Tailscale IPv4 address in 100.64.0.0/10 |
| port | Temporary TLS enrollment port, 8443 |
| pin | SHA-256 digest of the DER TLS certificate, lowercase hex |
| token | 32 random bytes, Base64URL encoded without padding |
| expires | Unix timestamp, fifteen minutes via PowerShell wrapper; five via Python CLI |

Port 8080 serves a static browser guide over the encrypted Tailscale tunnel. The capability remains in the URL fragment, which is not sent in HTTP requests. The guide uses no external assets, forbids framing, and sends no-store and no-referrer headers. Its Copy button creates a command for the already-installed Termux client, using the legacy `https://qrbridge.invalid/enroll#...` envelope solely as a command argument, never as browser navigation. Actual enrollment remains on pinned TLS port 8443. Trust in the guide's delivery depends on the Tailscale tunnel and host, not public HTTPS. Both listeners close on expiry. Chrome app intents and Web Share are not prerequisites for this flow.

No private key or account password appears in the QR. After matching the TLS certificate digest on the connected socket, Android sends JSON `{"token":...,"key":...}` to `POST /enroll`. Windows parses a genuine ED25519 public key before appending it. An in-process mutex serializes claims. The first successful claim commits the token to that public key; same-key retries are idempotent until expiry. A failed registration does not consume the token. Server restart invalidates all prior tokens.

The response includes SSH host, port, user and full ED25519 host public key. These travel over the pinned TLS connection. The client validates all values before generating SSH configuration and uses `StrictHostKeyChecking yes`. SSH key replacement is detected. Pair again only after verifying an intentional server rebuild.

## State and privileges

Machine state lives in `%ProgramData%\QrPowerShellConnect`, protected for SYSTEM and Administrators. The project repository holds no credentials. Enrollment runs only on demand as Administrator. The normal bridge consists of two noninteractive Windows services, plus the MeshBind readiness task when selected. The Android key is generated in Termux app-private storage with mode 0600 and has no passphrase to support immediate launch; Android's screen lock and application-data protection are therefore part of the credential boundary.

The SSH shell loads the account's standard profile. A slow or interactive profile delays or disrupts automation. This project does not rewrite the profile. The mesh transports an SSH stream across network changes where possible; transport failure starts a new PowerShell session. It does not migrate live command state. No keepalive mechanism guarantees survival through reboot, suspend, VPN revocation or Android process termination.

## Recovery

The installation manifest records the pre-install shell, existing configuration, capability ownership and unattended preference before mutation. `preparing` indicates an interrupted installation; invoke rollback before retrying. `installed` indicates configuration completed, not Android enrollment. `rolled-back` prevents accidental repeated rollback. Preserve the manifest for audit; archive the state directory deliberately before a clean reinstall.

A failed rollback leaves the manifest and logs for inspection. Do not delete state to hide a partial rollback. Tailscale is retained intentionally; if it was installed solely for this bridge, an operator may uninstall it using Windows Apps after rollback. Enrollment, revocation and loopback use the same Windows named mutex for exclusive key-store maintenance; a competing operation times out after ten seconds and can be retried. Force-killing enrollment may leave protected certificate/QR files and a firewall rule but no surviving listener; delete those files and the pairing rule or rerun pairing.

## Timing and evidence

Measure cold SSH session duration with the loopback test and warm commands from Android using an existing ControlMaster. Report network type and relay/direct routing alongside results. The tests do not assert timing bounds that depend on external networks. Boot readiness is constrained by Windows, service scheduling and network initialization. Static headless checks show Session 0 execution but do not substitute for a recorded physical boot observation.
