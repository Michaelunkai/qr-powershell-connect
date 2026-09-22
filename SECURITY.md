# Security policy

This bridge intentionally grants administrator command execution to an enrolled phone. Use it only on devices and accounts you control. A stolen enrollment QR can register an attacker within its short validity window if they can reach the tailnet endpoint. A stolen Android SSH private key grants access until revoked. Never post QR images, pairing URLs, private keys or state-directory archives in issues.

Restrict tailnet grants to the intended phone/user and host TCP 2222; allow 8080 and 8443 only during enrollment. The browser guide on HTTP 8080 relies on Tailscale's encrypted transport and host identity. It never accepts enrollment POSTs; the client uses pinned TLS 8443. The Windows firewall source range alone is not a per-device authorization policy. Existing broad firewall rules and compromised tailnet peers are outside this project's control. SSH keys remain the application authentication boundary.

Windows admin users and SYSTEM can modify this installation. TLS uses an exact QR-delivered certificate digest instead of public CA trust. The host's ED25519 SSH key is delivered inside that channel and enforced on every SSH connection. Enrollment never downloads or evaluates scripts from the QR. All SSH configuration fields are validated to prevent line injection.

Revoke the public key with `windows/Revoke-Key.ps1` and revoke the phone in Tailscale. Key removal blocks new logins; close existing SSH sessions separately. Stop sshd for immediate host-wide disconnect if necessary. Avoid changing the key file during enrollment or verification.

For a vulnerability, share a minimal reproduction privately with the repository maintainer before public disclosure. Use the repository Security tab to submit a private vulnerability report when reporting is enabled. Do not include real pairing capabilities, private keys or personal device logs.
