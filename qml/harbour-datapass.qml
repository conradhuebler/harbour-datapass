import QtQuick 2.0
import Sailfish.Silica 1.0
import "pages"

ApplicationWindow
{
    id: app

    // Global cover data object
    QtObject {
        id: coverData
        property string usedVolumeStr: ""
        property string initialVolumeStr: ""
        property real percentage: 0
        property string remainingTimeStr: ""
        property string estimatedGB: ""

        function refresh() {
            console.log("Cover refresh triggered")
            if (pageStack.currentPage && pageStack.currentPage.getData) {
                pageStack.currentPage.getData()
            }
        }
    }

    // Make coverData accessible globally
    property alias coverData: coverData

    initialPage: Component { MainPage { } }
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations
}
