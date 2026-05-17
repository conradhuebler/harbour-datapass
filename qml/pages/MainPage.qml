import QtQuick 2.0
import Sailfish.Silica 1.0
import QtQuick.LocalStorage 2.0
import Nemo.Configuration 1.0

Page {
    id: page
    objectName: "mainPage"
    // Loading state for network requests
    property bool loading: false
    // Indicates whether we are showing fallback demo data
    property bool demoMode: false
    // Model for daily consumption overview
    ListModel { id: dailyModel }
    // Track which volumes we've already shown dialogs for (prevent spam)
    property var shownDialogsForVolumes: ({})

    // Configuration values (persistent via Nemo.Configuration)
    ConfigurationGroup {
        id: configGroup
        path: "/apps/harbour-datapass"

        ConfigurationValue {
            id: refreshIntervalConfig
            key: "/refreshInterval"
            defaultValue: 10800000  // 3 hours in milliseconds
        }

        ConfigurationValue {
            id: retentionDaysConfig
            key: "/retentionDays"
            defaultValue: 30  // days
        }

        ConfigurationValue {
            id: activePresetIdConfig
            key: "/activePresetId"
            defaultValue: 1  // Default preset ID
        }

        ConfigurationValue {
            id: autoSwitchPresetsConfig
            key: "/autoSwitchPresets"
            defaultValue: true  // Automatically switch presets based on detected volume
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
    property string dbName: "TelekomDataV3"
    property int userPinnedPresetId: -1             // set when user manually taps a preset; -1 = no pin

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

    // Reset database (clear all data)
    function resetDatabase() {
        console.log("Resetting database...");

        var db = getDatabase();

        // Delete all data from tables (don't drop - avoid locks)
        db.transaction(function(tx) {
            tx.executeSql('DELETE FROM daily_usage');
            tx.executeSql('DELETE FROM usage_data');
            tx.executeSql('DELETE FROM presets');
            console.log("All data deleted");
        });

        // Reset active preset config to 0 (no preset)
        activePresetIdConfig.value = 0;

        // Reload UI
        presetsListModel.clear();
        var presetsData = getAllPresetsWithData();
        for (var i = 0; i < presetsData.length; i++) {
            presetsListModel.append(presetsData[i]);
        }

        // Refresh data
        getData();

        console.log("Database reset complete");
    }

    function initDatabase() {
        var db = getDatabase();
        db.transaction(function(tx) {
            // Create presets table for managing multiple connections
            tx.executeSql('CREATE TABLE IF NOT EXISTS presets(' +
                         'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
                         'name TEXT NOT NULL, ' +
                         'max_volume_bytes INTEGER NOT NULL, ' +
                         'color TEXT DEFAULT "#00BFFF", ' +
                         'icon TEXT DEFAULT "📱", ' +
                         'created_timestamp INTEGER, ' +
                         'is_active INTEGER DEFAULT 0)');

            // Check if usage_data table exists and has preset_id column
            try {
                tx.executeSql('SELECT preset_id FROM usage_data LIMIT 1');
            } catch(e) {
                // Column doesn't exist, try to add it
                try {
                    tx.executeSql('ALTER TABLE usage_data ADD COLUMN preset_id INTEGER DEFAULT 1');
                } catch(e2) {
                    // Table might not exist yet, create it
                    tx.executeSql('CREATE TABLE IF NOT EXISTS usage_data(' +
                                 'timestamp INTEGER PRIMARY KEY, ' +
                                 'used_volume INTEGER, ' +
                                 'remaining_seconds INTEGER, ' +
                                 'preset_id INTEGER DEFAULT 1)');
                }
            }

            // Index improves recent‑data queries
            tx.executeSql('CREATE INDEX IF NOT EXISTS idx_timestamp ON usage_data(timestamp)');

            // Create daily_usage table with composite PRIMARY KEY (date, preset_id)
            tx.executeSql('CREATE TABLE IF NOT EXISTS daily_usage(' +
                         'date TEXT NOT NULL, ' +
                         'used_volume_start INTEGER, ' +
                         'used_volume_end INTEGER, ' +
                         'daily_consumption INTEGER, ' +
                         'timestamp INTEGER, ' +
                         'preset_id INTEGER NOT NULL DEFAULT 1, ' +
                         'PRIMARY KEY(date, preset_id))');

            tx.executeSql('CREATE INDEX IF NOT EXISTS idx_daily_date ON daily_usage(date)');
            tx.executeSql('CREATE INDEX IF NOT EXISTS idx_daily_preset ON daily_usage(preset_id)');

            // No default preset - user creates them via dialog when unknown volume is detected
        });
    }

    function saveData(data) {
        var db = getDatabase();
        var timestamp = new Date().getTime();
        var dateStr = new Date(timestamp).toISOString().slice(0, 10); // YYYY-MM-DD

        // Detect preset by matching initialVolume from API data
        var presetId = null;
        if (data.initialVolume) {
            db.transaction(function(tx) {
                var rs = tx.executeSql('SELECT id FROM presets WHERE max_volume_bytes = ? LIMIT 1', [data.initialVolume]);
                if (rs.rows.length > 0) {
                    presetId = rs.rows.item(0).id;
                }
            });
        }

        // Fallback to active preset if no match
        if (presetId === null) {
            var fallbackId = getActivePresetId();
            var fallbackPreset = getPresetById(fallbackId);
            // Only use the fallback if the data is plausible for that preset
            if (fallbackPreset && fallbackPreset.max_volume_bytes > 0 &&
                    data.usedVolume > fallbackPreset.max_volume_bytes) {
                console.log("Warning: usedVolume", data.usedVolume, "exceeds fallback preset max",
                            fallbackPreset.max_volume_bytes, "- data not saved to avoid corruption");
                return;
            }
            presetId = fallbackId;
            console.log("Warning: No preset matched initialVolume " + data.initialVolume + ", using active preset", presetId);
        } else {
            console.log("Saving data under preset_id:", presetId, "for volume:", data.initialVolume);
        }

        db.transaction(function(tx) {
            // Insert new usage entry with preset_id
            var ins = tx.executeSql('INSERT INTO usage_data(timestamp, used_volume, remaining_seconds, preset_id) VALUES(?, ?, ?, ?)',
                                   [timestamp, data.usedVolume, data.remainingSeconds, presetId]);
            // SQLite errors are reported via the result object's `message` property
            if (ins && ins.message) {
                console.log('DB insert error:', ins.message);
            }

            // Update daily aggregation table
            // Try to update existing row for today with same preset
            var upd = tx.executeSql('SELECT used_volume_start, used_volume_end FROM daily_usage WHERE date = ? AND preset_id = ?', [dateStr, presetId]);
            if (upd.rows.length === 0) {
                // New day: use previous day's end as today's start so single-read-per-day
                // still yields correct consumption (Sailfish background timers don't run)
                // Find the most recent valid predecessor: last day where end ≤ today's reading.
                // This skips corrupt entries (e.g. wrong-preset data) and billing-period resets.
                var prevRow = tx.executeSql(
                    'SELECT used_volume_end FROM daily_usage WHERE preset_id = ? AND date < ? AND used_volume_end <= ? ORDER BY date DESC LIMIT 1',
                    [presetId, dateStr, data.usedVolume]);
                var dayStart = prevRow.rows.length > 0 ? prevRow.rows.item(0).used_volume_end : data.usedVolume;
                var initialConsumption = data.usedVolume - dayStart;
                tx.executeSql('INSERT INTO daily_usage (date, used_volume_start, used_volume_end, daily_consumption, timestamp, preset_id) VALUES(?, ?, ?, ?, ?, ?)',
                             [dateStr, dayStart, data.usedVolume, initialConsumption, timestamp, presetId]);
            } else {
                var row = upd.rows.item(0);
                var startVal = row.used_volume_start;
                // Update end value and compute consumption for the day
                var consumption = data.usedVolume - startVal;
                tx.executeSql('UPDATE daily_usage SET used_volume_end = ?, daily_consumption = ?, timestamp = ? WHERE date = ? AND preset_id = ?',
                             [data.usedVolume, consumption, timestamp, dateStr, presetId]);
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

    // Load daily aggregation data into ListModel (filtered by active preset)
    function loadDailyData() {
        dailyModel.clear();
        var db = getDatabase();
        var presetId = getActivePresetId();

        db.transaction(function(tx) {
            var rs = tx.executeSql('SELECT date, daily_consumption FROM daily_usage WHERE preset_id = ? ORDER BY date DESC LIMIT 7', [presetId]);
            for (var i = 0; i < rs.rows.length; i++) {
                var row = rs.rows.item(i);
                dailyModel.append({ date: row.date, daily_consumption: row.daily_consumption });
            }
        });
    }

    // ===== PRESET MANAGEMENT FUNCTIONS =====

    // Get active preset ID (from Nemo.Configuration)
    function getActivePresetId() {
        return activePresetIdConfig.value;
    }

    // Set active preset and update config
    function setActivePreset(presetId) {
        var db = getDatabase();
        db.transaction(function(tx) {
            // Update is_active flag
            tx.executeSql('UPDATE presets SET is_active = 0');
            tx.executeSql('UPDATE presets SET is_active = 1 WHERE id = ?', [presetId]);
        });
        activePresetIdConfig.value = presetId;
        console.log("Preset switched to ID:", presetId);
    }

    // Get preset by ID
    function getPresetById(presetId) {
        var preset = null;
        var db = getDatabase();
        db.transaction(function(tx) {
            var rs = tx.executeSql('SELECT * FROM presets WHERE id = ?', [presetId]);
            if (rs.rows.length > 0) {
                preset = rs.rows.item(0);
            }
        });
        return preset;
    }

    // Get all presets
    function getAllPresets() {
        var presets = [];
        var db = getDatabase();
        db.transaction(function(tx) {
            var rs = tx.executeSql('SELECT * FROM presets ORDER BY created_timestamp ASC');
            for (var i = 0; i < rs.rows.length; i++) {
                presets.push(rs.rows.item(i));
            }
        });
        return presets;
    }

    // Create new preset
    function createPreset(name, maxVolume, color, icon) {
        var newId = null;
        var db = getDatabase();
        db.transaction(function(tx) {
            var result = tx.executeSql('INSERT INTO presets(name, max_volume_bytes, color, icon, created_timestamp) VALUES(?, ?, ?, ?, ?)',
                                     [name, maxVolume, color, icon, new Date().getTime()]);
            newId = result.insertId;
        });
        return newId;
    }

    // Update preset
    function updatePreset(presetId, name, maxVolume, color, icon) {
        var db = getDatabase();
        db.transaction(function(tx) {
            tx.executeSql('UPDATE presets SET name = ?, max_volume_bytes = ?, color = ?, icon = ? WHERE id = ?',
                         [name, maxVolume, color, icon, presetId]);
        });
    }

    // Delete preset (not allowed if it's the last one)
    function deletePreset(presetId) {
        var db = getDatabase();
        var deleted = false;
        db.transaction(function(tx) {
            var count = tx.executeSql('SELECT COUNT(*) as cnt FROM presets');
            if (count.rows.item(0).cnt > 1) {
                tx.executeSql('DELETE FROM presets WHERE id = ?', [presetId]);
                deleted = true;

                // If deleted preset was active, switch to first remaining
                if (getActivePresetId() === presetId) {
                    var remaining = tx.executeSql('SELECT id FROM presets LIMIT 1');
                    if (remaining.rows.length > 0) {
                        setActivePreset(remaining.rows.item(0).id);
                    }
                }
            }
        });
        return deleted;
    }

    // Get last data for a specific preset
    function getLastDataForPreset(presetId) {
        var db = getDatabase();
        var lastData = null;

        var preset = getPresetById(presetId);
        var maxVolume = preset ? preset.max_volume_bytes : 0;

        db.transaction(function(tx) {
            // Filter out entries where used_volume exceeds the preset's max — those are
            // foreign data accidentally attributed to this preset via the fallback path.
            var rs = maxVolume > 0
                ? tx.executeSql('SELECT * FROM usage_data WHERE preset_id = ? AND used_volume <= ? ORDER BY timestamp DESC LIMIT 1',
                               [presetId, maxVolume])
                : tx.executeSql('SELECT * FROM usage_data WHERE preset_id = ? ORDER BY timestamp DESC LIMIT 1',
                               [presetId]);
            if (rs.rows.length > 0) {
                lastData = rs.rows.item(0);
            }
        });

        return lastData;
    }

    // Get all presets with their last data for display
    function getAllPresetsWithData() {
        var allPresets = getAllPresets();
        var presetsWithData = [];

        for (var i = 0; i < allPresets.length; i++) {
            var preset = allPresets[i];
            var lastData = getLastDataForPreset(preset.id);

            presetsWithData.push({
                id: preset.id,
                name: preset.name,
                icon: preset.icon,
                color: preset.color,
                max_volume_bytes: preset.max_volume_bytes,
                is_active: preset.is_active,
                lastUsedVolume: lastData ? lastData.used_volume : 0,
                lastTimestamp: lastData ? lastData.timestamp : 0
            });
        }

        return presetsWithData;
    }

    // Reload preset list from database
    function reloadPresetsList() {
        presetsListModel.clear();
        var presetsData = getAllPresetsWithData();
        for (var i = 0; i < presetsData.length; i++) {
            presetsListModel.append(presetsData[i]);
        }
        console.log("Reloaded presets list, count:", presetsData.length);
    }

    // Switch to preset and show stored data (no API call)
    function switchToPreset(presetId) {
        setActivePreset(presetId);

        // Reload preset list to update is_active flags in UI
        reloadPresetsList();

        // Get preset and last stored data
        var preset = getPresetById(presetId);
        if (preset) {
            presetLabel.text = preset.icon + " " + preset.name;

            // Load last stored data for this preset
            var lastData = getLastDataForPreset(presetId);
            if (lastData) {
                console.log("Switching to preset", preset.name, "- showing stored data");
                updateUIWithStoredData(lastData, preset);
            } else {
                console.log("No stored data for preset", preset.name);
            }
        }

        // Note: User must manually refresh (Pull-Down) to get new API data
    }

    // Auto-detect preset based on initial volume from API
    function autoDetectPreset(initialVolumeBytes) {
        var db = getDatabase();
        var matchedPresetId = null;
        var matchedPresetName = "";

        db.transaction(function(tx) {
            // Find preset with matching max_volume (exact match)
            var rs = tx.executeSql('SELECT id, name FROM presets WHERE max_volume_bytes = ? LIMIT 1',
                                 [initialVolumeBytes]);
            if (rs.rows.length > 0) {
                matchedPresetId = rs.rows.item(0).id;
                matchedPresetName = rs.rows.item(0).name;
            }
        });

        // Check if auto-switch is enabled
        var autoSwitchEnabled = autoSwitchPresetsConfig.value;

        if (matchedPresetId !== null) {
            // Known volume found
            // Don't auto-switch if the user has manually pinned a preset
            var userPinned = userPinnedPresetId !== -1 && userPinnedPresetId !== matchedPresetId;
            if (autoSwitchEnabled && !userPinned && matchedPresetId !== getActivePresetId()) {
                // Auto-switch enabled and different preset - switch automatically
                console.log("Auto-switching to preset:", matchedPresetName);
                switchToPreset(matchedPresetId);
            } else if (userPinned) {
                console.log("Auto-switch suppressed: user pinned preset", userPinnedPresetId);
            }
            // If auto-switch disabled, do nothing (stay on current preset)
        } else {
            // Unknown volume - show dialog only ONCE per volume
            var volumeKey = initialVolumeBytes.toString();
            if (!shownDialogsForVolumes[volumeKey]) {
                console.log("Unknown volume detected:", initialVolumeBytes, "bytes - showing dialog");
                shownDialogsForVolumes[volumeKey] = true;
                showNewVolumeDialog(initialVolumeBytes);
            } else {
                console.log("Unknown volume", initialVolumeBytes, "bytes - dialog already shown");
            }
        }

        return matchedPresetId;
    }

    // Show dialog for new/unknown volume
    function showNewVolumeDialog(volumeBytes) {
        newVolumeDialog.volumeBytes = volumeBytes;
        newVolumeDialog.open();
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
    // Retrieve completed daily entries for the last N days (today excluded, date-based filter)
    function getDailyHistoricalData(days) {
        days = days || 7;
        var db = getDatabase();
        var result = [];
        var presetId = getActivePresetId();
        var now = new Date();
        var today = now.toISOString().slice(0, 10);
        var cutoff = new Date(now.getTime() - (days * 24 * 60 * 60 * 1000)).toISOString().slice(0, 10);
        db.transaction(function(tx) {
            var rs = tx.executeSql(
                'SELECT * FROM daily_usage WHERE date >= ? AND date < ? AND preset_id = ? ORDER BY date DESC',
                [cutoff, today, presetId]);
            for (var i = 0; i < rs.rows.length; i++) {
                result.push(rs.rows.item(i));
            }
        });
        return result;
    }

    // Trend estimation based on daily consumption of completed days (last 7 days)
    function calculateTrendEstimate() {
        var dailyData = getDailyHistoricalData(7);
        if (dailyData.length === 0) return null;
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

    // Update UI with stored data from database (no API call)
    function updateUIWithStoredData(storedData, preset) {
        if (!storedData || !preset) {
            console.log("No stored data or preset available");
            return;
        }

        // Build data object from stored values
        var usedVolume = storedData.used_volume;
        var maxVolume = preset.max_volume_bytes;

        // Adjust remaining time for elapsed time since data was stored
        var elapsedSeconds = Math.round((new Date().getTime() - storedData.timestamp) / 1000);
        var remainingSeconds = Math.max(0, storedData.remaining_seconds - elapsedSeconds);

        var usedGB = (usedVolume / 1073741824).toFixed(2);
        var maxGB = maxVolume > 0 ? (maxVolume / 1073741824).toFixed(0) : "?";
        var usedPercentage = maxVolume > 0 ? Math.round((usedVolume / maxVolume) * 100) : 0;

        // Format remaining time
        var days = Math.floor(remainingSeconds / 86400);
        var hours = Math.floor((remainingSeconds % 86400) / 3600);
        var remainingTimeStr = days + " Tage " + hours + " Std.";

        // Show how old the cached data is
        var ageMinutes = Math.round(elapsedSeconds / 60);
        var ageStr = ageMinutes < 60 ? ageMinutes + " Min." : Math.round(ageMinutes / 60) + " Std.";

        var data = {
            title: qsTr("Gespeicherte Daten") + " (" + ageStr + ")",
            usedVolumeStr: usedGB + " GB",
            initialVolumeStr: maxGB + " GB",
            usedPercentage: usedPercentage,
            remainingTimeStr: remainingTimeStr,
            usedVolume: usedVolume,
            remainingSeconds: remainingSeconds,
            initialVolume: maxVolume
        };

        // Use regular updateUI with constructed data
        updateUI(data);
    }

    function updateUI(data) {
        console.log("Updating UI with data:", JSON.stringify(data))

        // Reset demo flag when real data arrives
        if (page.demoMode && !data.title.includes("Demo")) {
            page.demoMode = false;
        }

        // Auto-detect and switch preset based on initialVolume from API
        var matchedPresetId = null;
        if (data.initialVolume) {
            matchedPresetId = autoDetectPreset(data.initialVolume);
        }

        // If live data belongs to a different preset than what's currently displayed,
        // only refresh the list (to update "last seen") but don't overwrite the main display
        if (matchedPresetId !== null && matchedPresetId !== getActivePresetId()) {
            reloadPresetsList();
            return;
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
        // Reload preset list to show updated lastUsedVolume
        reloadPresetsList();
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
                onClicked: {
                    userPinnedPresetId = -1;
                    getData()
                }
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

            // Show active preset
            Label {
                id: presetLabel
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: {
                    var presetId = getActivePresetId();
                    if (presetId === 0) {
                        return qsTr("Kein Preset aktiv");
                    }
                    var preset = getPresetById(presetId);
                    if (preset) {
                        return preset.icon + " " + preset.name;
                    }
                    return qsTr("Kein Preset");
                }
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
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
            Item {
                id: progressBarContainer
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.6
                height: width

                Loader {
                    id: progressBar
                    anchors.fill: parent
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

                MouseArea {
                    anchors.fill: parent
                    onClicked: getData()
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

            // ===== ALL CONNECTIONS SECTION =====
            SectionHeader {
                text: qsTr("Alle Verbindungen")
            }

            ListView {
                id: presetsListView
                width: parent.width
                height: contentHeight
                interactive: false
                model: presetsListModel

                delegate: ListItem {
                    id: listItem
                    width: parent.width
                    contentHeight: presetRowHeight.implicitHeight + Theme.paddingSmall

                    RemorseItem { id: remorse }

                    Row {
                        id: presetRowHeight
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2*x
                        spacing: Theme.paddingMedium

                        Text {
                            text: model.icon
                            font.pixelSize: Theme.fontSizeExtraLarge
                            verticalAlignment: Text.AlignVCenter
                        }

                        Column {
                            width: parent.width - iconWidth.width - Theme.paddingMedium
                            spacing: Theme.paddingSmall

                            Label {
                                text: model.name + (model.is_active ? " ✓" : "")
                                font.pixelSize: Theme.fontSizeMedium
                                color: model.is_active ? Theme.highlightColor : Theme.primaryColor
                                truncationMode: TruncationMode.Fade
                            }

                            Label {
                                text: {
                                    if (model.lastUsedVolume > 0 && model.lastTimestamp > 0) {
                                        var gb = (model.lastUsedVolume / 1073741824).toFixed(1);
                                        var maxGb = model.max_volume_bytes > 0 ? (model.max_volume_bytes / 1073741824).toFixed(0) : "?";
                                        var date = new Date(model.lastTimestamp).toLocaleDateString();
                                        return gb + " GB / " + maxGb + " GB (" + date + ")";
                                    } else {
                                        return qsTr("Keine Daten");
                                    }
                                }
                                font.pixelSize: Theme.fontSizeExtraSmall
                                color: Theme.secondaryColor
                            }
                        }

                        Text {
                            id: iconWidth
                            text: model.icon
                            font.pixelSize: Theme.fontSizeExtraLarge
                            visible: false
                        }
                    }

                    onClicked: {
                        userPinnedPresetId = model.id;
                        switchToPreset(model.id);
                    }

                    onPressAndHold: {
                        remorse.execute(listItem, qsTr("Preset wird gelöscht"), function() {
                            var deleted = deletePreset(model.id);
                            if (deleted) {
                                reloadPresetsList();
                            } else {
                                console.log("Could not delete preset - last one?");
                            }
                        });
                    }
                }
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }
        }
    }

    // New Volume Dialog
    Dialog {
        id: newVolumeDialog
        canAccept: newVolumeDialog.useExistingPreset ? existingPresetCombo.currentIndex >= 0
                                                     : presetNameField.text.length > 0
        acceptDestination: page
        acceptDestinationAction: PageStackAction.Pop

        property real volumeBytes: 0
        property bool useExistingPreset: false

        SilicaFlickable {
            anchors.fill: parent
            contentHeight: dialogColumn.height

            Column {
                id: dialogColumn
                width: parent.width
                spacing: Theme.paddingMedium

                DialogHeader {
                    title: qsTr("Neue Verbindung erkannt")
                    acceptText: newVolumeDialog.useExistingPreset ? qsTr("Aktualisieren") : qsTr("Erstellen")
                    cancelText: qsTr("Ignorieren")
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2*x
                    text: qsTr("Ein unbekanntes Datenvolumen wurde erkannt. Möchtest du ein neues Profil erstellen oder zu einem existierenden hinzufügen?")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                    wrapMode: Text.Wrap
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2*x
                    text: qsTr("Volumen: ") + (newVolumeDialog.volumeBytes / 1073741824).toFixed(1) + " GB"
                    font.pixelSize: Theme.fontSizeMedium
                    font.bold: true
                    color: Theme.highlightColor
                }

                TextSwitch {
                    id: modeSwitch
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2*x
                    text: qsTr("Zu bestehendem Profil hinzufügen")
                    checked: newVolumeDialog.useExistingPreset
                    onCheckedChanged: newVolumeDialog.useExistingPreset = checked
                }

                SectionHeader {
                    text: qsTr("Neues Profil erstellen")
                    visible: !newVolumeDialog.useExistingPreset
                }

                TextField {
                    id: presetNameField
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2*x
                    placeholderText: qsTr("z.B. Handy SIM, WLAN Router")
                    label: qsTr("Profilname")
                    visible: !newVolumeDialog.useExistingPreset
                }

                SectionHeader {
                    text: qsTr("Bestehendes Profil")
                    visible: newVolumeDialog.useExistingPreset
                }

                ComboBox {
                    id: existingPresetCombo
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2*x
                    label: qsTr("Profil auswählen")
                    visible: newVolumeDialog.useExistingPreset

                    menu: ContextMenu {
                        Repeater {
                            model: getAllPresets()
                            delegate: MenuItem {
                                text: modelData.icon + " " + modelData.name
                                onClicked: existingPresetCombo.currentIndex = index
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: Theme.paddingLarge
                }
            }
        }

        onAccepted: {
            var volumeBytes = newVolumeDialog.volumeBytes > 0 ? newVolumeDialog.volumeBytes : 0;
            if (!newVolumeDialog.useExistingPreset) {
                var newPresetId = createPreset(presetNameField.text, volumeBytes, "#00BFFF", "📱");
                console.log("Created preset:", presetNameField.text, "with volume:", volumeBytes, "bytes");
                reloadPresetsList();
                switchToPreset(newPresetId);
            } else {
                var presets = getAllPresets();
                var selectedPreset = presets[existingPresetCombo.currentIndex];
                console.log("Updated preset:", selectedPreset.name, "to volume:", volumeBytes, "bytes");
                updatePreset(selectedPreset.id, selectedPreset.name, volumeBytes, selectedPreset.color, selectedPreset.icon);
                reloadPresetsList();
                switchToPreset(selectedPreset.id);
            }
            presetNameField.text = "";
            newVolumeDialog.useExistingPreset = false;
        }

        onRejected: {
            presetNameField.text = "";
            newVolumeDialog.useExistingPreset = false;
        }
    }

    // Preset List Model for compact display
    ListModel {
        id: presetsListModel
    }

    // Timer to wait for DB initialization to complete
    Timer {
        id: dbInitTimer
        interval: 50
        repeat: false
        onTriggered: {
            console.log("DB init complete, loading presets...");
            // Reload preset list after DB init
            presetsListModel.clear();
            var presetsData = getAllPresetsWithData();
            for (var i = 0; i < presetsData.length; i++) {
                presetsListModel.append(presetsData[i]);
            }
            getData();
        }
    }

    Component.onCompleted: {
        // Initialize database
        initDatabase();
        // Wait for DB init to complete before loading data
        dbInitTimer.start();
    }
}
}
