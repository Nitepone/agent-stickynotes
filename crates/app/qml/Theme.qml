pragma Singleton
import QtQuick

QtObject {
    readonly property color background: "#e9edf2"
    readonly property color columnBackground: "#dde2ea"
    readonly property color columnEditBackground: "#d3daf0"
    readonly property color text: "#1f2937"
    readonly property color subtleText: "#6b7280"
    readonly property color note: "#fff1a6"
    readonly property color noteText: "#3d3a24"
    readonly property color noteShadow: "#33000000"
    readonly property color progress: "#3b82f6"
    readonly property color progressDone: "#16a34a"
    readonly property color warning: "#d97706"
    readonly property color danger: "#dc2626"
    readonly property color dropIndicator: "#2563eb"
    readonly property color agentReadOnly: "#9ca3af"
    readonly property color agentReadWrite: "#16a34a"

    readonly property int columnWidth: 284
    readonly property int columnSpacing: 12
    readonly property int cardSpacing: 8
    readonly property int radius: 8
    readonly property int suggestedDescriptionChars: 200
}
