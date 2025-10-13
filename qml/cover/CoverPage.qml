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

    // Dual CircularProgressBar implementation for Cover
    Item {
        id: coverProgress
        anchors.centerIn: parent
        width: parent.width * 0.8
        height: width

        property real dataValue: (typeof app !== 'undefined' && app.coverData) ? app.coverData.percentage / 100 : 0
        property real timeValue: (typeof app !== 'undefined' && app.coverData) ? app.coverData.timeProgress / 100 : 0
        property real lineWidth: 6
        property color backgroundColor: Theme.rgba(Theme.primaryColor, 0.2)
        property color dataProgressColor: Theme.highlightColor
        property color timeProgressColor: Theme.secondaryHighlightColor

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
                var outerRadius = Math.min(width, height) / 2 - coverProgress.lineWidth / 2
                var innerRadius = outerRadius - coverProgress.lineWidth - 4

                ctx.clearRect(0, 0, width, height)

                // Outer circle (time) - background
                ctx.beginPath()
                ctx.arc(centerX, centerY, outerRadius, 0, 2 * Math.PI)
                ctx.lineWidth = coverProgress.lineWidth
                ctx.strokeStyle = coverProgress.backgroundColor
                ctx.stroke()

                // Inner circle (data) - background
                ctx.beginPath()
                ctx.arc(centerX, centerY, innerRadius, 0, 2 * Math.PI)
                ctx.lineWidth = coverProgress.lineWidth
                ctx.strokeStyle = coverProgress.backgroundColor
                ctx.stroke()

                // Outer progress arc (time)
                if (coverProgress.timeValue > 0) {
                    ctx.beginPath()
                    ctx.arc(centerX, centerY, outerRadius, -Math.PI / 2,
                           -Math.PI / 2 + 2 * Math.PI * coverProgress.timeValue)
                    ctx.lineWidth = coverProgress.lineWidth
                    ctx.strokeStyle = coverProgress.timeProgressColor
                    ctx.lineCap = "round"
                    ctx.stroke()
                }

                // Inner progress arc (data)
                if (coverProgress.dataValue > 0) {
                    ctx.beginPath()
                    ctx.arc(centerX, centerY, innerRadius, -Math.PI / 2,
                           -Math.PI / 2 + 2 * Math.PI * coverProgress.dataValue)
                    ctx.lineWidth = coverProgress.lineWidth
                    ctx.strokeStyle = coverProgress.dataProgressColor
                    ctx.lineCap = "round"
                    ctx.stroke()
                }
            }

            Connections {
                target: coverProgress
                onDataValueChanged: canvas.requestPaint()
                onTimeValueChanged: canvas.requestPaint()
            }
        }

        // Center text with data percentage
        Label {
            anchors.centerIn: parent
            text: Math.round(coverProgress.dataValue * 100) + "%"
            font.pixelSize: Theme.fontSizeMedium
            font.bold: true
            color: Theme.primaryColor
        }

        // Update when cover data changes
        Connections {
            target: (typeof app !== 'undefined' && app.coverData) ? app.coverData : null
            onPercentageChanged: {
                coverProgress.dataValue = app.coverData.percentage / 100
                coverProgress.forceRepaint()
            }
            onTimeProgressChanged: {
                coverProgress.timeValue = app.coverData.timeProgress / 100
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
