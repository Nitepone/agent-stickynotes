# Building release artifacts

[`.github/workflows/build.yml`](.github/workflows/build.yml) runs on pushes to
`main`, pull requests and `v*` tags. Three independent jobs each upload an
artifact named `stickynotes-<version>-<platform>`, where `<version>` is the tag
without its `v`, or the Cargo version plus the short commit (`0.1.0-7ee8067`).
A version tag also attaches all three, with a `SHA256SUMS.txt`, to a GitHub
release.

| Platform | Artifact | Built on |
|---|---|---|
| Linux x86_64 | `.AppImage` | the pinned build container below |
| Windows x86_64 | `.zip` holding `stickynotes.exe` and the Qt DLLs it needs | a Windows runner (MSVC) |
| macOS arm64 | `.dmg` | a macOS runner (`macdeployqt`) |

The Linux build runs in the [`Dockerfile`](Dockerfile) image: Rust 1.93.0 and
Qt 6.8.2 on Debian 13, with the AppImage tools pinned by version and checksum.
To build it locally (needs Docker):

```sh
docker build -t agent-stickynotes-build .
scripts/build-linux-container.sh    # builds the image if needed, then the AppImage
# -> target/container-cache/target/dist/stickynotes-<version>-linux-x86_64.AppImage
```

The AppImage needs glibc 2.41 or newer (Debian 13, Ubuntu 25.04, Fedora 42).

**Windows is built natively, not cross-compiled from the Linux container.** Qt's
tools (`qmake`, `moc`, `rcc`, `qmlcachegen`, `windeployqt`) have to run, and
cxx-qt generates C++ that must compile against Qt for the *target*. A MinGW
cross build would need a MinGW Qt plus host and target Qt kept in step, which
is fragile; on a Windows runner the official MSVC Qt build just works. The
`.exe` is linked as a GUI program (no console window); build with
`WINDOWS_CONSOLE=1` to keep one.

The packaging steps are scripts you can run on the matching OS, with Qt 6
(`qmake`, plus `windeployqt` or `macdeployqt`) on `PATH`:
`scripts/package-windows.sh` (from Git Bash) and `scripts/package-macos.sh`
write to `target/dist/`. The macOS app is ad hoc signed, not notarized, and the
Windows `.exe` is unsigned, so both trigger a first-run warning.

