# mediaremote-adapter (vendored)

- Source: https://github.com/ungive/mediaremote-adapter, tag `v0.7.7`, unchanged. Only the `MediaRemoteAdapter` target is built; the test client is not.
- Licence: BSD 3-Clause, see `LICENSE`. The licence is also copied into the app bundle (`Contents/Resources/mediaremote-adapter-LICENSE`).
- Built by `scripts/build-app.sh` with CMake into `.build/mediaremote-adapter`, then copied into `Contents/Frameworks`. The Perl script goes into `Contents/Resources`.
- Why: macOS 15.4 and later only let Apple-signed processes read now-playing information through the private MediaRemote framework. The adapter runs inside `/usr/bin/perl` (Apple-signed) and prints JSON lines that Wyrmwatch reads.
