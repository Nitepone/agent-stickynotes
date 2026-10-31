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
| Windows x86_64 | `-setup.exe` installer, and a `.zip` holding `stickynotes.exe` and the Qt DLLs it needs | a Windows runner (MSVC, Inno Setup) |
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

The Windows installer is built with [Inno Setup 6](https://jrsoftware.org/isinfo.php)
from [`scripts/packaging/windows/installer.iss`](scripts/packaging/windows/installer.iss).
It was chosen over NSIS because it is preinstalled on GitHub's Windows runners
(the workflow installs it with Chocolatey if not), has a built-in directory page
and Settings > Apps uninstaller registration, and needs no plugins. It installs
the `windeployqt` folder (64-bit Windows 10+ only) to a directory the user picks,
default `C:\Program Files\Agent Stickynotes` (all users) or
`%LOCALAPPDATA%\Programs\Agent Stickynotes` (current user), chosen at the first
prompt. It adds a Start menu shortcut and an uninstaller that removes the files
and the shortcut; boards and settings in the user's data folders are kept. The
version comes from `scripts/version.sh` (Cargo.toml). To build locally from Git
Bash with Inno Setup installed, run `scripts/package-windows.sh` (set
`SKIP_INSTALLER=1` for the zip only). Run
`stickynotes-<version>-windows-x86_64-setup.exe` to install; uninstall from
Settings > Apps. The installer is unsigned, so SmartScreen shows a first-run
warning.

The packaging steps are scripts you can run on the matching OS, with Qt 6
(`qmake`, plus `windeployqt` or `macdeployqt`) on `PATH`:
`scripts/package-windows.sh` (from Git Bash) and `scripts/package-macos.sh`
write to `target/dist/`. The macOS app is ad hoc signed, not notarized, and the
Windows `.exe` is unsigned, so both trigger a first-run warning.


## Icons

The artwork is [`scripts/packaging/agent-stickynotes.svg`](scripts/packaging/agent-stickynotes.svg)
(also the AppImage icon). The 16 px size uses a simplified variant,
[`agent-stickynotes-16.svg`](scripts/packaging/agent-stickynotes-16.svg): the column
and its title are dropped and the three notes sit on whole pixels, because the full
artwork blurs the notes together at that size. Everything else is the same artwork.

`scripts/make-icons.sh` renders both into the committed
`scripts/packaging/icon.ico` (16, 24, 32, 48, 64, 128 and 256 px) and
`scripts/packaging/icon.icns` (16 to 1024 px, with the @2x entries), and the PNGs
in `crates/app/icons/` that the app embeds for its window icon. It needs
python3 with `venv` and the cairo library, and installs cairosvg and Pillow in a
temporary venv. Run it only when the artwork changes, and commit the results.

- **Windows:** `crates/app/build.rs` compiles `crates/app/windows/stickynotes.rc`
  with the `embed-resource` crate (Windows hosts only, so Linux builds are
  unaffected), which embeds `icon.ico` as the executable's icon, under the name
  `IDI_ICON1` that Qt looks for. Explorer uses it. The installer, its uninstaller
  entry and the Start menu shortcut use the same icon (`SetupIconFile`,
  `UninstallDisplayIcon`).
- **Window icon (all platforms):** `main.rs` embeds the PNGs and `cpp/window_icon.h`
  sets them with `QGuiApplication::setWindowIcon`, so the title bar, taskbar and
  Dock do not depend on the executable's icon resource.
- **macOS:** `scripts/package-macos.sh` copies `icon.icns` into the bundle's
  `Contents/Resources` and sets `CFBundleIconFile` in `Info.plist`, for the Dock and
  Finder.
