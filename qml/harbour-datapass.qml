import QtQuick 2.0
import Sailfish.Silica 1.0
import "pages"
import "cover"

ApplicationWindow
{
    id: app

    property QtObject coverData: QtObject {
        property string usedVolumeStr: ""
        property string initialVolumeStr: ""
        property real percentage: 0
        property string remainingTimeStr: ""
        property string estimatedGB: ""

        onPercentageChanged: {
            if (coverData.percentage > 0) {
                coverUpdateTimer.restart()
            }
        }

        function refresh() {
            if (pageStack.currentPage && pageStack.currentPage.getData) {
                pageStack.currentPage.getData()
            }
        }
    }

    Timer {
        id: coverUpdateTimer
        interval: 100
        repeat: false
        onTriggered: {
            if (cover && cover.item) {
                var coverItem = cover.item
                if (coverItem.children) {
                    for (var i = 0; i < coverItem.children.length; i++) {
                        var child = coverItem.children[i]
                        if (child.forceRepaint) {
                            child.forceRepaint()
                        }
                    }
                }
            }
        }
    }

    initialPage: Component { MainPage { id: mainPage } }
    cover: Component { CoverPage { } }

    allowedOrientations: defaultAllowedOrientations
}
