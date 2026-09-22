# Third-party notices

The Windows/Python bridge tools are MIT licensed; see `LICENSE`.

The native Android application vendors ConnectBot at commit `30b6d7315d2ed5c11f3c92e45e60d57d712315e0` and is Apache-2.0 licensed. See `android-app/LICENSE`, `android-app/UPSTREAM.md`, and retained source-file notices. PowerShell Connect is an independent fork, not an official ConnectBot or Tailscale release.

Android dependencies include ConnectBot sshlib/termlib, AndroidX, Kotlin, Hilt, Conscrypt and JourneyApps ZXing Embedded. Their original licenses apply; dependency coordinates and versions are recorded in `android-app/gradle/libs.versions.toml`.

Tailscale and Microsoft OpenSSH are installed separately from their vendor distributions and retain their respective licenses. No vendor binaries, SDKs or private signing materials are included in the source repository.
