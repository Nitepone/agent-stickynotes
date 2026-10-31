// The icon of every window (title bar, taskbar, Dock, window switcher).
//
// Qt would otherwise use the executable's icon resource, and only when it is
// named the way the platform plugin expects. Setting it here does not depend on
// that, and is the same on every platform. Each call adds one size.
#pragma once

#include <QtGui/QGuiApplication>
#include <QtGui/QIcon>
#include <QtGui/QPixmap>

#include <cstdint>

#include "rust/cxx.h"

inline void add_window_icon(rust::Slice<const uint8_t> png)
{
    static QIcon icon;
    QPixmap pixmap;
    if (!pixmap.loadFromData(png.data(), static_cast<uint>(png.size()), "PNG"))
        return;
    icon.addPixmap(pixmap);
    QGuiApplication::setWindowIcon(icon);
}
