import QtQuick 2.0
import Sailfish.Silica 1.0
import QtQuick.LocalStorage 2.0
import Nemo.Configuration 1.0

Page {
    id: page
    // Loading state for network requests
    property bool loading: false
    // Indicates whether we are showing fallback demo data
    property bool demoMode: false
    // Model for daily consumption overview
    ListModel { id: dailyModel }

    // Configuration values (persistent via Nemo.Configuration)
    ConfigurationGroup {
        id: configGroup
        path: "/apps/harbour-datapass"

        ConfigurationValue {
            id: refreshIntervalConfig
            key: "refreshInterval"
            defaultValue: 10800000  // 3 hours in milliseconds
        }

        ConfigurationValue {
            id: retentionDaysConfig
            key: "retentionDays"
            defaultValue: 30  // days
        }
    }

    onStatusChanged: {
        if (status === PageStatus.Active) {
            // Refresh configurable interval when page becomes active
            refreshInterval = refreshIntervalConfig.value
            getData()
        }
    }

    // Dual CircularProgressBar implementation
    Component {
        id: circularProgressBar

        Item {
            id: progressBarRoot
            property real dataValue: 0.0
            property real timeValue: 0.0
            property real lineWidth: 12
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
                    var outerRadius = Math.min(width, height) / 2 - progressBarRoot.lineWidth / 2
                    var innerRadius = outerRadius - progressBarRoot.lineWidth - 8

                    ctx.clearRect(0, 0, width, height)

                    // Outer circle (time) - background
                    ctx.beginPath()
                    ctx.arc(centerX, centerY, outerRadius, 0, 2 * Math.PI)
                    ctx.lineWidth = progressBarRoot.lineWidth
                    ctx.strokeStyle = progressBarRoot.backgroundColor
                    ctx.stroke()

                    // Inner circle (data) - background
                    ctx.beginPath()
                    ctx.arc(centerX, centerY, innerRadius, 0, 2 * Math.PI)
                    ctx.lineWidth = progressBarRoot.lineWidth
                    ctx.strokeStyle = progressBarRoot.backgroundColor
                    ctx.stroke()

                    // Outer progress arc (time)
                    if (progressBarRoot.timeValue > 0) {
                        ctx.beginPath()
                        ctx.arc(centerX, centerY, outerRadius, -Math.PI / 2,
                               -Math.PI / 2 + 2 * Math.PI * progressBarRoot.timeValue)
                        ctx.lineWidth = progressBarRoot.lineWidth
                        ctx.strokeStyle = progressBarRoot.timeProgressColor
                        ctx.lineCap = "round"
                        ctx.stroke()
                    }

                    // Inner progress arc (data)
                    if (progressBarRoot.dataValue > 0) {
                        ctx.beginPath()
                        ctx.arc(centerX, centerY, innerRadius, -Math.PI / 2,
                               -Math.PI / 2 + 2 * Math.PI * progressBarRoot.dataValue)
                        ctx.lineWidth = progressBarRoot.lineWidth
                        ctx.strokeStyle = progressBarRoot.dataProgressColor
                        ctx.lineCap = "round"
                        ctx.stroke()
                    }
                }

                Connections {
                    target: progressBarRoot
                    onDataValueChanged: canvas.requestPaint()
                    onTimeValueChanged: canvas.requestPaint()
                }
            }

            // Center text with data percentage
            Column {
                anchors.centerIn: parent
                spacing: Theme.paddingSmall

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Math.round(progressBarRoot.dataValue * 100) + "%"
                    font.pixelSize: Theme.fontSizeExtraLarge
                    font.bold: true
                    color: Theme.primaryColor
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Daten")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                }
            }
        }
    }

    // -----------------------------------------------
    // Constants & helper functions (centralised)
    // -----------------------------------------------
    property int totalSeconds: 30 * 24 * 60 * 60   // 30‑day billing period in seconds
    property int refreshInterval: refreshIntervalConfig.value        // 3 h in ms (periodic API pull)
    property string dbName: "TelekomData"

    function bytesToGB(bytes) {
        return bytes / 1073741824;
    }

    function calcTimeProgress(remainingSec) {
        var prog = (totalSeconds - remainingSec) / totalSeconds;
        return Math.max(0, Math.min(1, prog));
    }

    // Database functions (using above constants)
    function getDatabase() {
        return LocalStorage.openDatabaseSync(dbName, "1.0", "Stores usage data", 1000000);
    }

    function initDatabase() {
        var db = getDatabase();
        db.transaction(function(tx) {
            tx.executeSql('CREATE TABLE IF NOT EXISTS usage_data(' +
                         'timestamp INTEGER PRIMARY KEY, ' +
                         'used_volume INTEGER, ' +
                         'remaining_seconds INTEGER)');
            // Index improves recent‑data queries
            tx.executeSql('CREATE INDEX IF NOT EXISTS idx_timestamp ON usage_data(timestamp)');
            
            // Neue Tabelle für tägliche Zusammenfassungen
            tx.executeSql('CREATE TABLE IF NOT EXISTS daily_usage(' +
                         'date TEXT PRIMARY KEY, ' +
                         'used_volume_start INTEGER, ' +
                         'used_volume_end INTEGER, ' +
                         'daily_consumption INTEGER, ' +
                         'timestamp INTEGER)');
            tx.executeSql('CREATE INDEX IF NOT EXISTS idx_daily_date ON daily_usage(date)');

        });
    }

    function saveData(data) {
        var db = getDatabase();
        var timestamp = new Date().getTime();
        var dateStr = new Date(timestamp).toISOString().slice(0, 10); // YYYY-MM-DD
        db.transaction(function(tx) {
            // Insert new usage entry
            var ins = tx.executeSql('INSERT INTO usage_data VALUES(?, ?, ?)',
                                   [timestamp, data.usedVolume, data.remainingSeconds]);
            // SQLite errors are reported via the result object's `message` property
            if (ins && ins.message) {
                console.log('DB insert error:', ins.message);
            }

            // Update daily aggregation table
            // Try to update existing row for today
            var upd = tx.executeSql('SELECT used_volume_start, used_volume_end FROM daily_usage WHERE date = ?', [dateStr]);
            if (upd.rows.length === 0) {
                // No entry yet – create one with start and end equal to current value
                tx.executeSql('INSERT INTO daily_usage (date, used_volume_start, used_volume_end, daily_consumption, timestamp) VALUES(?, ?, ?, ?, ?)',
                             [dateStr, data.usedVolume, data.usedVolume, 0, timestamp]);
            } else {
                var row = upd.rows.item(0);
                var startVal = row.used_volume_start;
                // Update end value and compute consumption for the day
                var consumption = data.usedVolume - startVal;
                tx.executeSql('UPDATE daily_usage SET used_volume_end = ?, daily_consumption = ?, timestamp = ? WHERE date = ?',
                             [data.usedVolume, consumption, timestamp, dateStr]);
            }

            // Remove entries older than 30 days to keep DB lean (both tables)
            // Use configurable retention period (default 30 days)
            var retentionDays = retentionDaysConfig.value;
            var cutoff = new Date().getTime() - (retentionDays * 24 * 60 * 60 * 1000);
            tx.executeSql('DELETE FROM usage_data WHERE timestamp < ?', [cutoff]);
            tx.executeSql('DELETE FROM daily_usage WHERE timestamp < ?', [cutoff]);
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

    // Load daily aggregation data into ListModel
    function loadDailyData() {
        dailyModel.clear();
        var db = getDatabase();
        db.transaction(function(tx) {
            var rs = tx.executeSql('SELECT date, daily_consumption FROM daily_usage ORDER BY date DESC LIMIT 7');
            for (var i = 0; i < rs.rows.length; i++) {
                var row = rs.rows.item(i);
                dailyModel.append({ date: row.date, daily_consumption: row.daily_consumption });
            }
        });
    }

    // Simple linear projection
    function calculateSimpleEstimate(usedVolume, remainingSeconds) {
        var usedDays = (totalSeconds - remainingSeconds) / 86400;
        if (usedDays <= 0) {
            return (bytesToGB(usedVolume)).toFixed(2);
        }
        var dailyUsage = usedVolume / usedDays;
        var totalDays = totalSeconds / 86400;
        var estimatedTotal = dailyUsage * totalDays;
        return (estimatedTotal / 1073741824).toFixed(2);
    }

    // Trend-based calculation
    // Retrieve daily usage entries for the last N days (default 7)
    function getDailyHistoricalData(days) {
        days = days || 7;
        var db = getDatabase();
        var result = [];
        var cutoff = new Date().getTime() - (days * 24 * 60 * 60 * 1000);
        db.transaction(function(tx) {
            var rs = tx.executeSql('SELECT * FROM daily_usage WHERE timestamp > ? ORDER BY timestamp DESC', [cutoff]);
            for (var i = 0; i < rs.rows.length; i++) {
                result.push(rs.rows.item(i));
            }
        });
        return result;
    }

    // Trend estimation based on daily consumption of the last 7 days
    function calculateTrendEstimate() {
        var dailyData = getDailyHistoricalData(7);
        if (dailyData.length < 2) return null;
        var totalConsumption = 0;
        var daysCount = 0;
        for (var i = 0; i < dailyData.length; i++) {
            // daily_consumption may be negative on the first entry of the day; ignore if zero or negative
            var consumption = dailyData[i].daily_consumption;
            if (consumption > 0) {
                totalConsumption += consumption;
                daysCount++;
            }
        }
        if (daysCount === 0) return null;
        var avgDailyGB = (totalConsumption / daysCount) / 1073741824;
        return avgDailyGB; // GB per day
    }

    // ------ Timer for periodic refresh (uses constant)
    Timer {
        interval: refreshInterval
        running: true
        repeat: true
        onTriggered: getData()
    }

    // ------ Network request with timeout & simple retry ------
    function getData(retryCount) {
        // Indicate loading UI
        page.loading = true;
        retryCount = retryCount || 0;
        var xhr = new XMLHttpRequest();
        xhr.timeout = 15000; // 15 s
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                page.loading = false;
                if (xhr.status === 200) {
                    var data = JSON.parse(xhr.responseText);
                    saveData(data);
                    updateUI(data);
                } else {
                    // retry once on server (5xx) errors
                    if (retryCount < 1 && xhr.status >= 500) {
                        console.log("Retrying after server error", xhr.status);
                        getData(retryCount + 1);
                        return;
                    }
                    console.log("API Error, using demo data. Status:", xhr.status);
                    loadDemoData();
                }
            }
        };
        xhr.ontimeout = function() {
            page.loading = false;
            console.log("Request timed out – using demo data");
            loadDemoData();
        };
        xhr.open("GET", "https://pass.telekom.de/api/service/generic/v1/status");
        xhr.send();
    }

    function loadDemoData() {
        page.demoMode = true;
        var demoData = {
            title: qsTr("Demo Datenverbrauch"),
            usedVolumeStr: "15.2 GB",
            initialVolumeStr: "30 GB",
            usedPercentage: 50.7,
            remainingTimeStr: qsTr("14 Tage 12 Stunden"),
            usedVolume: 16321798144,
            remainingSeconds: 1244160
        };
        updateUI(demoData);
    }

    function updateUI(data) {
        console.log("Updating UI with data:", JSON.stringify(data))

        // Reset demo flag when real data arrives
        if (page.demoMode && !data.title.includes("Demo")) {
            page.demoMode = false;
        }

        titleLabel.text = data.title || "Telekom Datenverbrauch"
        volumeValueLabel.text = data.usedVolumeStr + " / " + data.initialVolumeStr
        percentageValueLabel.text = data.usedPercentage + "%"
        remainingValueLabel.text = data.remainingTimeStr

        // Update progress bar values using shared helpers
        if (progressBar.item) {
            progressBar.item.dataValue = data.usedPercentage / 100
            progressBar.item.timeValue = calcTimeProgress(data.remainingSeconds)
        }

        // Simple linear projection (uses property totalSeconds)
        var simpleEstimate = calculateSimpleEstimate(data.usedVolume, data.remainingSeconds)
        estimatedSimpleValueLabel.text = simpleEstimate + " GB"

        // Current average usage based on totalSeconds property
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

            // Calculate and set time progress for cover (uses helper)
            var timeProgress = calcTimeProgress(data.remainingSeconds)
            app.coverData.timeProgress = Math.max(0, Math.min(1, timeProgress)) * 100
        } else {
            console.log("app.coverData not available")
        }

        // Force repaint
        if (progressBar.item) {
            progressBar.item.forceRepaint()
        }
        // Refresh daily list model
        loadDailyData();
    }

        SilicaFlickable {
            // Show BusyIndicator when loading data
            BusyIndicator {
                id: busyInd
                running: page.loading
                anchors.centerIn: parent
                visible: page.loading
                size: BusyIndicatorSize.Large
            }
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                text: qsTr("Aktualisieren")
                onClicked: getData()
            }
            MenuItem {
                text: qsTr("Einstellungen")
                onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"))
            }
        }

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("Telekom Datenverbrauch")
            }
            // Show a warning when demo data is used
            Label {
                id: errorLabel
                visible: page.demoMode
                text: qsTr("API unavailable – using demo data")
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter
                anchors.horizontalCenter: parent.horizontalCenter
                // topMargin removed – Column handles spacing
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
                        item.dataValue = 0.0
                        item.timeValue = 0.0
                    }
                }

                onItemChanged: {
                    if (item) {
                        item.lineWidth = 15
                        item.dataValue = 0.0
                        item.timeValue = 0.0
                    }
                }
            }

            // Legend for the dual circles
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingLarge

                Row {
                    spacing: Theme.paddingSmall
                    Rectangle {
                        width: 16
                        height: 16
                        radius: 8
                        color: Theme.highlightColor
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Label {
                        text: "Datenvolumen"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryColor
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    spacing: Theme.paddingSmall
                    Rectangle {
                        width: 16
                        height: 16
                        radius: 8
                        color: Theme.secondaryHighlightColor
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Label {
                        text: "Abrechnungszeit"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryColor
                        anchors.verticalCenter: parent.verticalCenter
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
                    text: qsTr("Verbrauch in Prozent")
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
                    text: qsTr("Verbleibende Zeit")
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
                    text: qsTr("Statistiken")
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
                    text: qsTr("Durchschnittlicher täglicher Verbrauch")
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
                    text: qsTr("Trend (letzte 7 Tage)")
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
                    text: qsTr("Prognosen")
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
                    text: qsTr("Geschätzter Gesamtverbrauch (linear)")
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
                text: qsTr("Geschätzter Gesamtverbrauch (Trend)")
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
            // Daily usage list
            Label {
                text: qsTr("Verbrauch pro Tag (letzte 7 Tage)")
                font.bold: true
                color: Theme.highlightColor
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
            }
            ListView {
                id: dailyList
                width: parent.width
                height: dailyModel.count * (Theme.itemSizeSmall + Theme.paddingSmall)
                model: dailyModel
                delegate: Row {
                    width: parent.width
                    spacing: Theme.paddingMedium
                    Label {
                        text: model.date
                        width: parent.width * 0.5
                    }
                    Label {
                        // daily_consumption stored in bytes, convert to GB
                        text: (model.daily_consumption / 1073741824).toFixed(2) + " GB"
                        horizontalAlignment: Text.AlignRight
                        width: parent.width * 0.5
                    }
                }
            }
        }
    }
    }

    Component.onCompleted: {
        // Settings are managed by Nemo.Configuration in the settings object
        initDatabase()
        getData()
    }
}
