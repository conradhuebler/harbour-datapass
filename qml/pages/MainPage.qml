import QtQuick 2.0
import Sailfish.Silica 1.0
import QtQuick.LocalStorage 2.0


Page {
    id: page

    QtObject {
        id: coverData
        property string usedVolumeStr: ""
        property string initialVolumeStr: ""
        property real percentage: 0
        property string remainingTimeStr: ""
        property string estimatedGB: ""

        function refresh() {
            getData()
        }
    }


   onStatusChanged: {
        if (status === PageStatus.Active) {
            getData()
        }
    }

    // Database functions
    function getDatabase() {
        return LocalStorage.openDatabaseSync("TelekomData", "1.0", "Stores usage data", 1000000);
    }

    function initDatabase() {
        var db = getDatabase();
        db.transaction(function(tx) {
            tx.executeSql('CREATE TABLE IF NOT EXISTS usage_data(timestamp INTEGER PRIMARY KEY,
                          used_volume INTEGER, remaining_seconds INTEGER)');
        });
    }

    function saveData(data) {
        var db = getDatabase();
        var timestamp = new Date().getTime();
        db.transaction(function(tx) {
            tx.executeSql('INSERT INTO usage_data VALUES(?, ?, ?)',
                         [timestamp, data.usedVolume, data.remainingSeconds]);
        });
    }

    function getHistoricalData() {
        var db = getDatabase();
        var data = [];
        db.transaction(function(tx) {
            var result = tx.executeSql('SELECT * FROM usage_data WHERE timestamp > ?
                                      ORDER BY timestamp DESC',
                                      [new Date().getTime() - (7 * 24 * 60 * 60 * 1000)]);
            for(var i = 0; i < result.rows.length; i++) {
                data.push(result.rows.item(i));
            }
        });
        return data;
    }

    // Simple linear projection
    function calculateSimpleEstimate(usedVolume, totalSeconds, remainingSeconds) {
        var usedDays = (totalSeconds - remainingSeconds) / 86400
        var dailyUsage = usedVolume / usedDays
        var totalDays = totalSeconds / 86400
        var estimatedTotal = dailyUsage * totalDays
        return (estimatedTotal / 1073741824).toFixed(2)
    }

    // Trend-based calculation
    function calculateTrendEstimate() {
        var historicalData = getHistoricalData();
        if(historicalData.length < 2) return null;

        var firstEntry = historicalData[historicalData.length-1];
        var lastEntry = historicalData[0];
        var daysDiff = (lastEntry.timestamp - firstEntry.timestamp) / (24 * 60 * 60 * 1000);
        var volumeDiff = lastEntry.used_volume - firstEntry.used_volume;

        return daysDiff > 0 ? volumeDiff / daysDiff / 1073741824 : 0;
    }

    Timer {
        interval: 10800000
        running: true
        repeat: true
        onTriggered: getData()
    }

    function getData() {
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    var data = JSON.parse(xhr.responseText);
                    saveData(data);
                    updateUI(data);
                }
            }
        }
        xhr.open("GET", "https://pass.telekom.de/api/service/generic/v1/status");
        xhr.send();
    }

    function updateUI(data) {
        titleLabel.text = data.title
        volumeLabel.text = data.usedVolumeStr + " / " + data.initialVolumeStr
        percentageLabel.text = data.usedPercentage + "%"
        remainingLabel.text = data.remainingTimeStr
        progressBar.value = data.usedPercentage / 100

        // Simple linear projection
        var totalSeconds = 30 * 24 * 60 * 60
        var simpleEstimate = calculateSimpleEstimate(data.usedVolume, totalSeconds, data.remainingSeconds)
        estimatedLabelSimple.text = qsTr("Estimated total usage (linear)") + ": " + simpleEstimate + " GB"

        // Current average usage
        var usedDays = (totalSeconds - data.remainingSeconds) / 86400
        var dailyAverage = (data.usedVolume / 1073741824 / usedDays).toFixed(2)
        averageLabel.text = qsTr("Average daily usage") + ": " + dailyAverage + " " + qsTr("GB/day")

        // Trend-based estimation
        var trend = calculateTrendEstimate();
        if(trend !== null) {
            trendLabel.text = qsTr("Trend (last 7 days)") + ": " + trend.toFixed(2) + " " + qsTr("GB/day")

            var remainingDays = data.remainingSeconds / (24 * 60 * 60);
            var currentGB = data.usedVolume / 1073741824;
            var estimatedTotal = currentGB + (trend * remainingDays);
            estimatedLabelTrend.text = qsTr("Estimated total usage (trend)") + ": " + estimatedTotal.toFixed(2) + " GB"
        }

        app.coverData.usedVolumeStr = data.usedVolumeStr
        app.coverData.initialVolumeStr = data.initialVolumeStr
        app.coverData.percentage = data.usedPercentage
        app.coverData.remainingTimeStr = data.remainingTimeStr
        app.coverData.estimatedGB = simpleEstimate

        if (progressBar) {
            progressBar.forceRepaint()
        }

    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                text: qsTr("Refresh")
                onClicked: getData()
            }
        }

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("Telekom Data Usage")
            }

            Label {
                id: titleLabel
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
            }

            CircularProgressBar {
                id: progressBar
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.6
                height: width
                lineWidth: 15
            }

            Label {
                id: volumeLabel
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                color: Theme.primaryColor
                font.pixelSize: Theme.fontSizeMedium
            }

            Label {
                id: percentageLabel
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                color: Theme.primaryColor
                font.pixelSize: Theme.fontSizeMedium
            }

            Label {
                id: remainingLabel
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                color: Theme.primaryColor
                font.pixelSize: Theme.fontSizeMedium
            }

            Label {
                id: averageLabel
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeMedium
            }

            Label {
                id: trendLabel
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeMedium
            }

            Label {
                id: estimatedLabelSimple
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeMedium
            }

            Label {
                id: estimatedLabelTrend
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeMedium
            }
        }
    }

    Component.onCompleted: {
        initDatabase()
        getData()
    }
}
