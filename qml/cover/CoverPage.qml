// CoverPage.qml
import QtQuick 2.0
import Sailfish.Silica 1.0

CoverBackground {
    id: coverBackground

    Component.onCompleted: {
        if (typeof app !== 'undefined' && app.coverData) {
            app.coverData.refresh()
        }
    }

    // CircularProgressBar implementation for Cover
    Item {
        id: coverProgress
        anchors.centerIn: parent
        width: parent.width * 0.8
        height: width

        property real value: (typeof app !== 'undefined' && app.coverData) ? app.coverData.percentage / 100 : 0
        property real lineWidth: 8
        property color backgroundColor: Theme.rgba(Theme.primaryColor, 0.2)
        property color progressColor: Theme.highlightColor

        function forceRepaint() {
            canvas.requestPaint()
        }

        Canvas {
            id: canvas
            anchors.fill: parent

            onPaint: {
                var ctx = getContext("2d")
                var centerX = width / 2
                var centerY = height / 2
                var radius = Math.min(width, height) / 2 - coverProgress.lineWidth / 2

                ctx.clearRect(0, 0, width, height)

                // Background circle
                ctx.beginPath()
                ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI)
                ctx.lineWidth = coverProgress.lineWidth
                ctx.strokeStyle = coverProgress.backgroundColor
                ctx.stroke()

                // Progress arc
                if (coverProgress.value > 0) {
                    ctx.beginPath()
                    ctx.arc(centerX, centerY, radius, -Math.PI / 2,
                           -Math.PI / 2 + 2 * Math.PI * coverProgress.value)
                    ctx.lineWidth = coverProgress.lineWidth
                    ctx.strokeStyle = coverProgress.progressColor
                    ctx.lineCap = "round"
                    ctx.stroke()
                }
            }

            Connections {
                target: coverProgress
                onValueChanged: canvas.requestPaint()
            }
        }

        // Percentage text in center
        Label {
            anchors.centerIn: parent
            text: Math.round(coverProgress.value * 100) + "%"
            font.pixelSize: Theme.fontSizeLarge
            font.bold: true
            color: Theme.primaryColor
        }

        // Update when cover data changes
        Connections {
            target: (typeof app !== 'undefined' && app.coverData) ? app.coverData : null
            onPercentageChanged: {
                coverProgress.value = app.coverData.percentage / 100
                coverProgress.forceRepaint()
            }
        }
    }

    // Data volume info
    Label {
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: coverProgress.bottom
            topMargin: Theme.paddingMedium
        }
        text: (typeof app !== 'undefined' && app.coverData) ?
              app.coverData.usedVolumeStr + " / " + app.coverData.initialVolumeStr :
              "-- / --"
        font.pixelSize: Theme.fontSizeExtraSmall
        color: Theme.secondaryColor
        horizontalAlignment: Text.AlignHCenter
    }

    // Remaining time
    Label {
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: Theme.paddingLarge
        }
        text: (typeof app !== 'undefined' && app.coverData) ?
              app.coverData.remainingTimeStr :
              "--"
        font.pixelSize: Theme.fontSizeExtraSmall
        color: Theme.secondaryColor
        horizontalAlignment: Text.AlignHCenter
    }

    CoverActionList {
        CoverAction {
            iconSource: "image://theme/icon-cover-refresh"
            onTriggered: {
                if (typeof app !== 'undefined' && app.coverData) {
                    app.coverData.refresh()
                }
            }
        }
    }

    // Update timer
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            if (coverProgress) {
                coverProgress.forceRepaint()
            }
        }
    }
}
