import QtQuick 2.0
import Sailfish.Silica 1.0

Item {
    id: root

    property real value: 0
    property real lineWidth: 10
    property color backgroundColor: "azure"
    property color foregroundColor: {
        if (value <= 0.25) return "darkgreen"
        if (value <= 0.50) return "greenyellow"
        if (value <= 0.65) return "orange"
        if (value <= 0.85) return "orangered"
        if (value <= 0.90) return "crimson"
        return Theme.errorColor
    }

    width: 200
    height: 200

    // Neu: Überwache Sichtbarkeit
    onVisibleChanged: {
        if (visible) {
            canvas.requestPaint()
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        // Neu: Überwache Größenänderungen
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()

            var centerX = width/2
            var centerY = height/2
            var radius = Math.min(width, height)/2 - lineWidth/2

            // Background circle
            ctx.beginPath()
            ctx.lineWidth = lineWidth
            ctx.strokeStyle = backgroundColor
            ctx.arc(centerX, centerY, radius, 0, 2*Math.PI)
            ctx.stroke()

            // Progress circle
            if (value > 0) {
                ctx.beginPath()
                ctx.lineWidth = lineWidth
                ctx.strokeStyle = foregroundColor
                ctx.arc(centerX, centerY, radius, -Math.PI/2, (-Math.PI/2) + (value * 2 * Math.PI))
                ctx.stroke()
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: Theme.paddingSmall

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Math.round(root.value * 100) + "%"
            font.pixelSize: Theme.fontSizeLarge
            color: root.foregroundColor
        }
    }

    // Trigger repaint when value changes
    onValueChanged: canvas.requestPaint()
    Component.onCompleted: canvas.requestPaint()

    // Neu: Timer für verzögertes Neuzeichnen
    Timer {
        id: repaintTimer
        interval: 100
        repeat: false
        onTriggered: canvas.requestPaint()
    }

    // Neu: Funktion zum Neuzeichnen
    function forceRepaint() {
        repaintTimer.restart()
    }
}
