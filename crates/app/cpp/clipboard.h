// What the clipboard holds, for pasting into a task's artifacts. QML cannot
// read clipboard images, so this is the C++ side of Ctrl+V in the task dialog.
#pragma once

#include <QtCore/QBuffer>
#include <QtCore/QByteArray>
#include <QtCore/QDateTime>
#include <QtCore/QMimeData>
#include <QtCore/QString>
#include <QtCore/QStringList>
#include <QtCore/QUrl>
#include <QtGui/QClipboard>
#include <QtGui/QGuiApplication>
#include <QtGui/QImage>

#include <cstdint>

#include "rust/cxx.h"

/// The clipboard's image as PNG bytes; empty when it holds no image.
inline rust::Vec<uint8_t> clipboard_image_png()
{
    rust::Vec<uint8_t> out;
    const QMimeData* mime = QGuiApplication::clipboard()->mimeData();
    if (!mime || !mime->hasImage())
        return out;
    const QImage image = qvariant_cast<QImage>(mime->imageData());
    if (image.isNull())
        return out;
    QByteArray bytes;
    QBuffer buffer(&bytes);
    buffer.open(QIODevice::WriteOnly);
    if (!image.save(&buffer, "PNG"))
        return out;
    for (char c : bytes)
        out.push_back(static_cast<uint8_t>(c));
    return out;
}

/// pasted-YYYYMMDD-HHMMSS.png, in local time.
inline QString clipboard_image_name()
{
    return QStringLiteral("pasted-") + QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss"))
        + QStringLiteral(".png");
}

/// The local files on the clipboard, one path per line; empty for none.
inline QString clipboard_file_paths()
{
    QStringList paths;
    const QMimeData* mime = QGuiApplication::clipboard()->mimeData();
    if (mime && mime->hasUrls())
        for (const QUrl& url : mime->urls())
            if (url.isLocalFile())
                paths << url.toLocalFile();
    return paths.join(QLatin1Char('\n'));
}
