// Notes when the user last gave the app input (mouse, keyboard, wheel, touch).
//
// An application-level event filter observes input without consuming it, so
// no view can hide activity from it and it cannot take events from any view.
// Only events that come from the system count: Qt synthesizes hover events
// itself when the layout changes under a still pointer, and those are not the
// user doing anything.
#pragma once

#include <QtCore/QCoreApplication>
#include <QtCore/QDateTime>
#include <QtCore/QEvent>
#include <QtCore/QObject>
#include <QtGui/QGuiApplication>
#include <QtGui/QMouseEvent>
#include <QtGui/QWindow>

#include <atomic>
#include <cstdint>

class ActivityFilter : public QObject
{
public:
    static ActivityFilter& instance()
    {
        static ActivityFilter filter;
        return filter;
    }

    std::atomic<int64_t> lastMs { 0 };
    // Only for the dev hook below: also count events sent from code.
    std::atomic<bool> countSynthetic { false };

protected:
    bool eventFilter(QObject*, QEvent* event) override
    {
        switch (event->type()) {
        case QEvent::MouseMove:
        case QEvent::MouseButtonPress:
        case QEvent::MouseButtonRelease:
        case QEvent::Wheel:
        case QEvent::KeyPress:
        case QEvent::TouchBegin:
        case QEvent::TouchUpdate:
        case QEvent::TabletMove:
        case QEvent::TabletPress:
            if (event->spontaneous() || countSynthetic)
                lastMs = QDateTime::currentMSecsSinceEpoch();
            break;
        default:
            break;
        }
        return false; // never consume anything
    }
};

inline void install_activity_filter()
{
    if (auto* app = QGuiApplication::instance())
        app->installEventFilter(&ActivityFilter::instance());
}

// Milliseconds since the epoch of the last user input; 0 if none yet.
inline int64_t last_activity_ms()
{
    return ActivityFilter::instance().lastMs.load();
}

// Dev aids for headless checks. Offscreen there is no real input, so a mouse
// move is sent through the application from code. Events sent from code are
// not "spontaneous", so by default the filter ignores them (as it does Qt's
// own synthesized hover events); `counted` makes this one count, which lets a
// check cover both outcomes.
inline void send_test_mouse_move(bool counted)
{
    const auto windows = QGuiApplication::topLevelWindows();
    if (windows.isEmpty())
        return;
    QWindow* window = windows.first();
    const QPointF local(20, 20);
    QMouseEvent move(QEvent::MouseMove, local, window->mapToGlobal(local), Qt::NoButton, Qt::NoButton,
                     Qt::NoModifier);
    auto& filter = ActivityFilter::instance();
    filter.countSynthetic = counted;
    QCoreApplication::sendEvent(window, &move);
    filter.countSynthetic = false;
}

inline void simulate_user_activity() { send_test_mouse_move(true); }
inline void simulate_synthetic_activity() { send_test_mouse_move(false); }
