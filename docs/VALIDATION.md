# Host validation — 2026-09-22

The owner confirmed that the connection works after rebooting both Windows and Android and authorized publication. A subsequent live audit independently confirmed a new Windows boot, automatic SSH and Tailscale services running as LocalSystem, Session 0 execution, unattended mesh mode, strict key ACLs, mesh-only SSH listeners and an authenticated Administrator PowerShell loopback session.

The Python enrollment suite passes 15 tests, including real TLS exchange, wrong-pin rejection, expiry, replay/concurrency controls, invalid input rejection and legacy-client socket naming. Native Android checks are documented separately in [NATIVE-VALIDATION.md](NATIVE-VALIDATION.md).

The observed Windows deployment uses the Microsoft OpenSSH 10.0p2 Preview ZIP fallback with explicit Tailscale/localhost binding. The stable Windows capability remains the default installer path. A protected SYSTEM recovery task handles the boot race where the mesh address becomes available after sshd starts. An earlier deliberate SSH-stop test confirmed recovery of the listener. No visual desktop console is required by the services or recovery task.

Host reports remain in the protected ProgramData state directory. Device screenshots, enrollment capabilities, SSH identities, signing secrets and detailed personal logs are excluded from the published source.

## Interpretation and limits

- The owner's reboot acceptance is a user-reported result. Live service verification is an independent tool-observed result.
- Session 0 and headless task configuration are verified. A camera recording of the entire boot sequence was not independently captured.
- Connectivity requires an awake Windows PC, Internet access, valid Tailscale authentication and permitted tailnet traffic. A network that blocks all usable paths cannot be made universally reachable by this app.
- Normal reboot preserves enrollment. Uninstalling/clearing app data, resetting a device or revoking its credentials deliberately removes access.
- A lost SSH session cannot recreate the in-memory state of a terminated command. Use a durable Windows job runner for work that must survive host shutdown or session loss.
- This is tested open-source software, not an independent security certification or a promise of flawless future operation.
