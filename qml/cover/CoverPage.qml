// CoverPage.qml
import QtQuick 2.0
import Sailfish.Silica 1.0

import "../pages"

CoverBackground {
    id: coverBackground
    Component.onCompleted: {
        app.coverData.refresh()
    }
    CircularProgressBar {
        id :coverProgress
        anchors.centerIn: parent
        width: parent.width * 0.8
        height: width
        value: app.coverData.percentage / 100
        lineWidth: 8
    }

    Label {
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: Theme.paddingLarge
        }
        text: app.coverData.remainingTimeStr
        font.pixelSize: Theme.fontSizeExtraSmall
        color: Theme.secondaryColor
    }

    CoverActionList {
        CoverAction {
            iconSource: "image://theme/icon-cover-refresh"
            onTriggered: app.coverData.refresh()
        }
    }

    Timer {
        interval: 500
        running: true
        onTriggered: {
            if (coverProgress) {
                coverProgress.forceRepaint()
            }
        }
    }

}
