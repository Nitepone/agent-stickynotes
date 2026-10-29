// Dev aid: render the app window to an image file (used for headless UI checks).
#pragma once

#include <QtGui/QGuiApplication>
#include <QtGui/QImage>
#include <QtGui/QWindow>
#include <QtQuick/QQuickWindow>

inline bool save_window_screenshot(const QString& path)
{
    for (QWindow* window : QGuiApplication::topLevelWindows()) {
        if (auto* quick = qobject_cast<QQuickWindow*>(window)) {
            return quick->grabWindow().save(path);
        }
    }
    return false;
}
