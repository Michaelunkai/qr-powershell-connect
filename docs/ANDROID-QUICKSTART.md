# Steps on this phone

The setup files have been copied via the authorized ADB connection to:
`/sdcard/Download/qr-powershell-connect/android`

1. Install/open Tailscale and sign into the same tailnet as Windows. Approve its VPN prompt. In Android Settings, set Tailscale as Always-on VPN if desired and allow background activity.
2. Open your existing Termux and run:

   ```bash
   termux-setup-storage
   bash ~/storage/downloads/qr-powershell-connect/android/install.sh
   ```

   Approve the Android storage prompt if shown. The setup installs OpenSSH and Python inside Termux and keeps private credentials inside Termux's private directory.

3. Run `windows/Start-Pairing.ps1` on Windows and scan the fresh QR. It opens a page on the PC's Tailscale address. Tap **Copy pairing command**, open **Termux**, long-press and paste, then press Enter. Keep the Windows pairing window open. The QR expires after fifteen minutes; generate a fresh one if necessary. Previously installed Termux clients work without reinstalling.
4. After `QRBRIDGE_ANDROID_OK` appears, run `windows` or use the Termux:Widget `Windows-PowerShell` shortcut.

Both devices must be connected to Tailscale. Open the new QR normally in your browser; discard old QR images pointing to `qrbridge.invalid`. Enrollment is persistent; you do not rescan for ordinary connections.

## Repair an already-enrolled client reporting a Unix socket path error

If enrollment completed but SSH reports `too long for Unix domain socket`, run in Termux:

```bash
sed -i.bak 's|^[[:space:]]*ControlPath .*|    ControlPath ~/.ssh/qrbridge/cm|' ~/.ssh/qrbridge/config
windows
```

This preserves the enrolled key and pinned host key. It persists across restarts; no fresh pairing is needed. Updated client code generates a short destination-specific socket name for future enrollments, reserving space for OpenSSH's temporary suffix.
