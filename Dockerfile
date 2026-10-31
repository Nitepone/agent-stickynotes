# syntax=docker/dockerfile:1
#
# Reproducible Linux build container for agent-stickynotes.
#
# It holds the pinned toolchain (Rust + Qt 6 + AppImage tooling) and nothing
# else: the source tree is mounted at /src when it runs, see
# scripts/build-linux-container.sh. CI builds the Linux AppImage in this image.
#
#   docker build -t agent-stickynotes-build .
#
# Pins (bump deliberately, all in this file):
#   * Rust       RUST_VERSION       (keep in step with RUST_VERSION in .github/workflows/build.yml)
#   * Debian     trixie (13)        via the official rust image tag
#   * Qt 6       6.8.2              Debian trixie's Qt; apt packages are pinned to 6.8.2*
#   * AppImage   linuxdeploy tools  release tags + SHA-256 below
#
# The binary links against this image's glibc (2.41), so the AppImage runs on
# distributions at least that new (Debian 13, Ubuntu 25.04, Fedora 42, ...).

ARG RUST_VERSION=1.93.0
FROM rust:${RUST_VERSION}-trixie

ARG QT_APT_VERSION=6.8.2*

ENV DEBIAN_FRONTEND=noninteractive

# Qt 6 development files and the QML modules the UI imports at run time
# (QtQuick, Controls, Dialogs, Layouts, Window, Models). The QML modules are
# needed here so linuxdeploy can find and bundle them into the AppImage.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        "qt6-base-dev=${QT_APT_VERSION}" \
        "qt6-base-dev-tools=${QT_APT_VERSION}" \
        "qt6-declarative-dev=${QT_APT_VERSION}" \
        "qt6-declarative-dev-tools=${QT_APT_VERSION}" \
        "qt6-wayland=${QT_APT_VERSION}" \
        "qml6-module-qtquick=${QT_APT_VERSION}" \
        "qml6-module-qtquick-controls=${QT_APT_VERSION}" \
        "qml6-module-qtquick-dialogs=${QT_APT_VERSION}" \
        "qml6-module-qtquick-layouts=${QT_APT_VERSION}" \
        "qml6-module-qtquick-templates=${QT_APT_VERSION}" \
        "qml6-module-qtquick-window=${QT_APT_VERSION}" \
        "qml6-module-qtqml-models=${QT_APT_VERSION}" \
        "qml6-module-qtqml-workerscript=${QT_APT_VERSION}" \
        "qml6-module-qt-labs-folderlistmodel=${QT_APT_VERSION}" \
        "qml6-module-qt-labs-platform=${QT_APT_VERSION}" \
        build-essential pkg-config git ca-certificates curl file hunspell-en-us \
        libgl-dev libvulkan-dev libxkbcommon-dev libxkbcommon-x11-0 \
        libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
        libxcb-randr0 libxcb-render-util0 libxcb-shape0 libxcb-xkb1 \
        libfuse2t64 desktop-file-utils squashfs-tools \
 && rm -rf /var/lib/apt/lists/*

# cxx-qt finds Qt through qmake; the default `qmake` is not guaranteed to be Qt 6.
ENV QMAKE=/usr/lib/qt6/bin/qmake6

# AppImage tooling, pinned by release tag and verified by checksum. The tools
# are themselves AppImages, which need FUSE; containers have none, so they are
# told to unpack and run instead.
ENV APPIMAGE_EXTRACT_AND_RUN=1
ARG LINUXDEPLOY_TAG=1-alpha-20251107-1
ARG LINUXDEPLOY_SHA256=c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d
ARG LINUXDEPLOY_QT_TAG=1-alpha-20250213-1
ARG LINUXDEPLOY_QT_SHA256=15106be885c1c48a021198e7e1e9a48ce9d02a86dd0a1848f00bdbf3c1c92724
ARG LINUXDEPLOY_APPIMAGE_TAG=1-alpha-20250213-1
ARG LINUXDEPLOY_APPIMAGE_SHA256=992d502a248e14ab185448ddf6f6e7d25558cb84d4623c354c3af350c25fccb3
RUN mkdir -p /opt/appimage-tools && cd /opt/appimage-tools \
 && curl -fsSL -o linuxdeploy-x86_64.AppImage \
      "https://github.com/linuxdeploy/linuxdeploy/releases/download/${LINUXDEPLOY_TAG}/linuxdeploy-x86_64.AppImage" \
 && curl -fsSL -o linuxdeploy-plugin-qt-x86_64.AppImage \
      "https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/${LINUXDEPLOY_QT_TAG}/linuxdeploy-plugin-qt-x86_64.AppImage" \
 && curl -fsSL -o linuxdeploy-plugin-appimage-x86_64.AppImage \
      "https://github.com/linuxdeploy/linuxdeploy-plugin-appimage/releases/download/${LINUXDEPLOY_APPIMAGE_TAG}/linuxdeploy-plugin-appimage-x86_64.AppImage" \
 && printf '%s  %s\n' \
      "${LINUXDEPLOY_SHA256}" linuxdeploy-x86_64.AppImage \
      "${LINUXDEPLOY_QT_SHA256}" linuxdeploy-plugin-qt-x86_64.AppImage \
      "${LINUXDEPLOY_APPIMAGE_SHA256}" linuxdeploy-plugin-appimage-x86_64.AppImage \
    | sha256sum -c - \
 && chmod +x ./*.AppImage
ENV PATH=/opt/appimage-tools:${PATH}

# The CI check job runs rustfmt and clippy in this image too (the official
# image has only the minimal toolchain).
RUN rustup component add rustfmt clippy

# Builds run as an unprivileged user chosen by the caller (docker run --user),
# so give every such user a writable HOME and keep the build caches in /cache.
ENV HOME=/tmp/home \
    CARGO_HOME=/cache/cargo \
    CARGO_TARGET_DIR=/cache/target
RUN mkdir -p /tmp/home /cache && chmod 1777 /tmp/home && chmod 0777 /cache

WORKDIR /src
CMD ["scripts/package-appimage.sh"]
