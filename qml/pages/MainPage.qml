import QtQuick 2.0
import Sailfish.Silica 1.0
import QtQuick.LocalStorage 2.0

Page {
    id: page

    onStatusChanged: {
        if (status === PageStatus.Active) {
            getData()
        }
    }

    // CircularProgressBar implementation
    Component {
        id: circularProgressBar

        Item {
            id: progressBarRoot
            property real value: 0.0
            property real lineWidth: 10
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
                    var radius = Math.min(width, height) / 2 - progressBarRoot.lineWidth / 2

                    ctx.clearRect(0, 0, width, height)

                    // Background circle
                    ctx.beginPath()
                    ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI)
                    ctx.lineWidth = progressBarRoot.lineWidth
                    ctx.strokeStyle = progressBarRoot.backgroundColor
                    ctx.stroke()

                    // Progress arc
                    if (progressBarRoot.value > 0) {
                        ctx.beginPath()
                        ctx.arc(centerX, centerY, radius, -Math.PI / 2,
                               -Math.PI / 2 + 2 * Math.PI * progressBarRoot.value)
                        ctx.lineWidth = progressBarRoot.lineWidth
                        ctx.strokeStyle = progressBarRoot.progressColor
                        ctx.lineCap = "round"
                        ctx.stroke()
                    }
                }

                Connections {
                    target: progressBarRoot
                    onValueChanged: canvas.requestPaint()
                }
            }

            // Percentage text in center
            Label {
                anchors.centerIn: parent
                text: Math.round(progressBarRoot.value * 100) + "%"
                font.pixelSize: Theme.fontSizeExtraLarge
                font.bold: true
                color: Theme.primaryColor
            }
        }
    }

    // Database functions
    function getDatabase() {
        return LocalStorage.openDatabaseSync("TelekomData", "1.0", "Stores usage data", 1000000);
    }

    function initDatabase() {
        var db = getDatabase();
        db.transaction(function(tx) {
            tx.executeSql('CREATE TABLE IF NOT EXISTS usage_data(timestamp INTEGER PRIMARY KEY, used_volume INTEGER, remaining_seconds INTEGER)');
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
            var result = tx.executeSql('SELECT * FROM usage_data WHERE timestamp > ? ORDER BY timestamp DESC',
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
        interval: 10800000 // 3 hours
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
                } else {
                    // Handle error case - show demo data
                    console.log("API Error, using demo data. Status:", xhr.status)
                    var demoData = {
                        title: "Demo Datenverbrauch",
                        usedVolumeStr: "15.2 GB",
                        initialVolumeStr: "30 GB",
                        usedPercentage: 50.7,
                        remainingTimeStr: "14 Tage 12 Stunden",
                        usedVolume: 16321798144, // bytes
                        remainingSeconds: 1244160 // seconds
                    };
                    updateUI(demoData);
                }
            }
        }
        xhr.open("GET", "https://pass.telekom.de/api/service/generic/v1/status");
        xhr.send();
    }

    function updateUI(data) {
        console.log("Updating UI with data:", JSON.stringify(data))

        titleLabel.text = data.title || "Telekom Datenverbrauch"
        volumeValueLabel.text = data.usedVolumeStr + " / " + data.initialVolumeStr
        percentageValueLabel.text = data.usedPercentage + "%"
        remainingValueLabel.text = data.remainingTimeStr

        // Update progress bar value
        if (progressBar.item) {
            progressBar.item.value = data.usedPercentage / 100
        }

        // Simple linear projection
        var totalSeconds = 30 * 24 * 60 * 60
        var simpleEstimate = calculateSimpleEstimate(data.usedVolume, totalSeconds, data.remainingSeconds)
        estimatedSimpleValueLabel.text = simpleEstimate + " GB"

        // Current average usage
        var usedDays = (totalSeconds - data.remainingSeconds) / 86400
        var dailyAverage = (data.usedVolume / 1073741824 / usedDays).toFixed(2)
        averageValueLabel.text = dailyAverage + " GB/Tag"

        // Trend-based estimation
        var trend = calculateTrendEstimate();
        if(trend !== null) {
            trendValueLabel.text = trend.toFixed(2) + " GB/Tag"

            var remainingDays = data.remainingSeconds / (24 * 60 * 60);
            var currentGB = data.usedVolume / 1073741824;
            var estimatedTotal = currentGB + (trend * remainingDays);
            estimatedTrendValueLabel.text = estimatedTotal.toFixed(2) + " GB"
        } else {
            trendValueLabel.text = "Nicht verfügbar"
            estimatedTrendValueLabel.text = "Nicht verfügbar"
        }

        // Update global cover data
        if (typeof app !== 'undefined' && app.coverData) {
            console.log("Updating app.coverData")
            app.coverData.usedVolumeStr = data.usedVolumeStr
            app.coverData.initialVolumeStr = data.initialVolumeStr
            app.coverData.percentage = data.usedPercentage
            app.coverData.remainingTimeStr = data.remainingTimeStr
            app.coverData.estimatedGB = simpleEstimate
        } else {
            console.log("app.coverData not available")
        }

        // Force repaint
        if (progressBar.item) {
            progressBar.item.forceRepaint()
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                text: "Aktualisieren"
                onClicked: getData()
            }
        }

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: "Telekom Datenverbrauch"
            }

            Label {
                id: titleLabel
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
                text: "Lade Daten..."
            }

            // Custom circular progress bar
            Loader {
                id: progressBar
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.6
                height: width
                sourceComponent: circularProgressBar

                Component.onCompleted: {
                    if (item) {
                        item.lineWidth = 15
                        item.value = 0.0
                    }
                }

                onItemChanged: {
                    if (item) {
                        item.lineWidth = 15
                        item.value = 0.0
                    }
                }
            }

            // Data sections
            Column {
                width: parent.width
                spacing: Theme.paddingMedium

                // Data Volume Section
                Column {
                    width: parent.width
                    spacing: Theme.paddingSmall

                    Label {
                        text: "Datenvolumen"
                        font.bold: true
                        color: Theme.highlightColor
                        font.pixelSize: Theme.fontSizeLarge
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2*x
                    }
                    Label {
                        id: volumeValueLabel
                        color: Theme.primaryColor
                        font.pixelSize: Theme.fontSizeMedium
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2*x
                        text: "-- / --"
                    }
                }

                // Usage Percentage Section
                Column {
                    width: parent.width
                    spacing: Theme.paddingSmall

                    Label {
                        text: "Verbrauch in Prozent"
                        font.bold: true
                        color: Theme.highlightColor
                        font.pixelSize: Theme.fontSizeLarge
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2*x
                    }
                    Label {
                        id: percentageValueLabel
                        color: Theme.primaryColor
                        font.pixelSize: Theme.fontSizeMedium
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2*x
                        text: "--%"
                    }
                }

                // Remaining Time Section
                Column {
                    width: parent.width
                    spacing: Theme.paddingSmall

                    Label {
                        text: "Verbleibende Zeit"
                        font.bold: true
                        color: Theme.highlightColor
                        font.pixelSize: Theme.fontSizeLarge
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2*x
                    }
                    Label {
                        id: remainingValueLabel
                        color: Theme.primaryColor
                        font.pixelSize: Theme.fontSizeMedium
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2*x
                        text: "--"
                    }
                }

                Separator {
                    width: parent.width
                    color: Theme.rgba(Theme.highlightColor, 0.3)
                }

                // Statistics Section
                Label {
                    text: "Statistiken"
                    font.bold: true
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeExtraLarge
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2*x
                }

                // Average Daily Usage
                Column {
                    width: parent.width
                    spacing: Theme.paddingSmall

                    Label {
                        text: "Durchschnittlicher täglicher Verbrauch"
                        font.bold: true
                        color: Theme.primaryColor
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2*x
                    }
                    Label {
                        id: averageValueLabel
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeMedium
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2*x
                        text: "-- GB/Tag"
                    }
                }

                // Trend (Last 7 Days)
                Column {
                    width: parent.width
                    spacing: Theme.paddingSmall

                    Label {
                        text: "Trend (letzte 7 Tage)"
                        font.bold: true
                        color: Theme.primaryColor
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2*x
                    }
                    Label {
                        id: trendValueLabel
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeMedium
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2*x
                        text: "-- GB/Tag"
                    }
                }

                Separator {
                    width: parent.width
                    color: Theme.rgba(Theme.highlightColor, 0.3)
                }

                // Projections Section
                Label {
                    text: "Prognosen"
                    font.bold: true
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeExtraLarge
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2*x
                }

                // Estimated Total (Linear)
                Column {
                    width: parent.width
                    spacing: Theme.paddingSmall

                    Label {
                        text: "Geschätzter Gesamtverbrauch (linear)"
                        font.bold: true
                        color: Theme.primaryColor
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2*x
                    }
                    Label {
                        id: estimatedSimpleValueLabel
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeMedium
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2*x
                        text: "-- GB"
                    }
                }

                // Estimated Total (Trend)
                Column {
                    width: parent.width
                    spacing: Theme.paddingSmall

                    Label {
                        text: "Geschätzter Gesamtverbrauch (Trend)"
                        font.bold: true
                        color: Theme.primaryColor
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2*x
                    }
                    Label {
                        id: estimatedTrendValueLabel
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeMedium
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2*x
                        text: "-- GB"
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        initDatabase()
        getData()
    }
}
