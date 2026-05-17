import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0

Page {
    id: settingsPage
    allowedOrientations: defaultAllowedOrientations

    // Load settings when page becomes active
    onStatusChanged: {
        if (status === PageStatus.Active) {
            intervalSlider.value = refreshIntervalConfig.value
            retentionSlider.value = retentionDaysConfig.value
            reloadPresetsModel()
        }
    }

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
            id: autoSwitchPresetsConfig
            key: "/autoSwitchPresets"
            defaultValue: true  // Automatically switch presets based on detected volume
        }
    }

    // Settings range constraints
    property int minInterval: 3600000   // 1 h in ms
    property int maxInterval: 43200000  // 12 h in ms

    // Presets ListModel
    ListModel {
        id: presetsModel
    }

    // Reload presets from database
    function reloadPresetsModel() {
        presetsModel.clear();

        // Find MainPage instance to access getAllPresets()
        var mainPage = pageStack.find(function(page) {
            return page.objectName === "mainPage";
        });

        if (mainPage === null) {
            console.log("Could not find MainPage instance in reloadPresetsModel");
            return;
        }

        var allPresets = mainPage.getAllPresets();
        for (var i = 0; i < allPresets.length; i++) {
                presetsModel.append(allPresets[i]);
            }
    }

    // Color options for icon picker
    property var colorOptions: [
        { name: "Blue", hex: "#00BFFF" },
        { name: "Red", hex: "#FF6B6B" },
        { name: "Green", hex: "#51CF66" },
        { name: "Purple", hex: "#A78BFA" },
        { name: "Orange", hex: "#FFA94D" },
        { name: "Pink", hex: "#FF99CC" },
        { name: "Teal", hex: "#20C997" },
        { name: "Yellow", hex: "#FFD43B" }
    ]

    // Icon options
    property var iconOptions: ["📱", "📡", "🌐", "🏠", "💼", "⚡", "🔌", "📶"]

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                text: qsTr("Neues Preset hinzufügen")
                onClicked: pageStack.push(presetEditorComponent, { isNewPreset: true })
            }
            MenuItem {
                text: qsTr("Standardwerte wiederherstellen")
                onClicked: resetRemorse.execute(qsTr("Einstellungen werden zurückgesetzt"), function() {
                    refreshIntervalConfig.value = 10800000  // 3 hours
                    retentionDaysConfig.value = 30          // 30 days
                })
            }
        }

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: qsTr("Einstellungen")
            }

            // ===== PRESETS SECTION =====
            SectionHeader {
                text: qsTr("Verbindungsprofile")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: qsTr("Verwalte verschiedene Datenverbindungen (z.B. SIM, WLAN) mit separaten Statistiken.")
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                wrapMode: Text.Wrap
            }

            ListView {
                id: presetsList
                width: parent.width
                height: contentHeight
                model: presetsModel
                interactive: false

                delegate: Item {
                    width: presetsList.width
                    height: presetDelegate.height + Theme.paddingMedium

                    Rectangle {
                        id: presetDelegate
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2*x
                        height: presetRow.height + Theme.paddingMedium
                        color: "transparent"
                        border.color: Theme.rgba(model.color, 0.3)
                        border.width: 1
                        radius: Theme.paddingSmall

                        Row {
                            id: presetRow
                            x: Theme.paddingMedium
                            y: Theme.paddingSmall
                            width: parent.width - 2*x
                            spacing: Theme.paddingMedium

                            Text {
                                id: iconText
                                text: model.icon
                                font.pixelSize: Theme.fontSizeExtraLarge
                                verticalAlignment: Text.AlignVCenter
                            }

                            Column {
                                width: parent.width - iconText.width - Theme.paddingMedium
                                spacing: Theme.paddingSmall

                                Label {
                                    text: model.name
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: Theme.primaryColor
                                    truncationMode: TruncationMode.Fade
                                }

                                Label {
                                    text: model.max_volume_bytes > 0 ?
                                        (model.max_volume_bytes / 1073741824).toFixed(1) + " GB" :
                                        qsTr("Automatische Erkennung")
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                    color: Theme.secondaryColor
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: pageStack.push(presetEditorComponent, {
                                isNewPreset: false,
                                presetId: model.id,
                                presetName: model.name,
                                presetMaxVolume: model.max_volume_bytes,
                                presetColor: model.color,
                                presetIcon: model.icon
                            })
                        }
                    }
                }
            }

            // Auto-switch setting
            TextSwitch {
                id: autoSwitchSwitch
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: qsTr("Automatisch Preset wechseln")
                description: qsTr("Wechselt automatisch zum passenden Preset wenn bekanntes Datenvolumen erkannt wird")
                automaticCheck: false
                checked: autoSwitchPresetsConfig.value
                onClicked: {
                    autoSwitchPresetsConfig.value = !autoSwitchPresetsConfig.value
                    checked = autoSwitchPresetsConfig.value
                }
            }

            // ===== PERFORMANCE SECTION =====
            SectionHeader {
                text: qsTr("Leistung")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: qsTr("Aktualisierungsintervall")
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.highlightColor
                wrapMode: Text.Wrap
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: qsTr("Wie oft die App neue Datennutzungsdaten vom Server abruft. Kürzere Intervalle verbrauchen mehr Akku und Datenvolumen.")
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                wrapMode: Text.Wrap
            }

            Slider {
                id: intervalSlider
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                minimumValue: minInterval
                maximumValue: maxInterval
                stepSize: 3600000  // 1 hour steps
                value: 10800000  // Default value, will be loaded from config onStatusChanged

                onValueChanged: {
                    refreshIntervalConfig.value = value
                }

                valueText: {
                    var hours = Math.round(value / 3600000)
                    var frequency = ""
                    if (hours === 1) frequency = qsTr("sehr häufig")
                    else if (hours <= 3) frequency = qsTr("häufig")
                    else if (hours <= 6) frequency = qsTr("moderat")
                    else frequency = qsTr("selten")

                    return hours + " " + qsTr("Std.") + " (" + frequency + ")"
                }
            }

            // ===== STORAGE SECTION =====
            SectionHeader {
                text: qsTr("Datenspeicherung")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: qsTr("Aufbewahrungsdauer")
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.highlightColor
                wrapMode: Text.Wrap
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: qsTr("Wie lange Datennutzungsdaten und tägliche Statistiken gespeichert werden. Ältere Daten werden automatisch gelöscht.")
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                wrapMode: Text.Wrap
            }

            Slider {
                id: retentionSlider
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                minimumValue: 7
                maximumValue: 60
                stepSize: 1
                value: 30  // Default value, will be loaded from config onStatusChanged

                onValueChanged: {
                    retentionDaysConfig.value = value
                }

                valueText: value + " " + qsTr("Tage")
            }

            // Database reset button
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: qsTr("Datenbank zurücksetzen")
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.highlightColor
                wrapMode: Text.Wrap
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: qsTr("Löscht alle gespeicherten Daten und setzt die Datenbank zurück. Kann nicht rückgängig gemacht werden!")
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                wrapMode: Text.Wrap
            }

            Button {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: qsTr("Datenbank zurücksetzen")
                color: Theme.errorColor
                onClicked: {
                    dbResetRemorse.execute(qsTr("Datenbank wird zurückgesetzt"), function() {
                        // Find MainPage instance using pageStack.find()
                        var mainPage = pageStack.find(function(page) {
                            return page.objectName === "mainPage";
                        });

                        if (mainPage !== null) {
                            mainPage.resetDatabase();
                            console.log("Database reset triggered from settings");
                            reloadPresetsModel();
                        } else {
                            console.log("Could not find MainPage instance");
                        }
                    })
                }
            }

            // Additional spacing at bottom
            Item {
                width: parent.width
                height: Theme.paddingLarge
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: qsTr("Hinweis: Einstellungen werden automatisch gespeichert.")
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }
        }
    }

    // Preset Editor Component
    Component {
        id: presetEditorComponent

        Page {
            id: editorPage
            allowedOrientations: defaultAllowedOrientations

            property bool isNewPreset: false
            property int presetId: -1
            property string presetName: ""
            property int presetMaxVolume: 0
            property string presetColor: "#00BFFF"
            property string presetIcon: "📱"

            SilicaFlickable {
                anchors.fill: parent
                contentHeight: editorColumn.height

                Column {
                    id: editorColumn
                    width: parent.width
                    spacing: Theme.paddingMedium

                    PageHeader {
                        title: editorPage.isNewPreset ? qsTr("Neues Profil") : qsTr("Profil bearbeiten")
                    }

                    // Name input
                    SectionHeader {
                        text: qsTr("Profilname")
                    }

                    TextField {
                        id: nameField
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2*x
                        placeholderText: qsTr("z.B. Handy SIM, WLAN Router")
                        text: editorPage.presetName
                    }

                    // Max Volume input
                    SectionHeader {
                        text: qsTr("Maximales Datenvolumen")
                    }

                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2*x
                        text: qsTr("Wird zur automatischen Erkennung verwendet. 0 = Automatische Erkennung deaktiviert.")
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryColor
                        wrapMode: Text.Wrap
                    }

                    TextField {
                        id: volumeField
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2*x
                        placeholderText: qsTr("z.B. 100 (GB)")
                        text: editorPage.presetMaxVolume > 0 ? (editorPage.presetMaxVolume / 1073741824).toFixed(0) : ""
                        inputMethodHints: Qt.ImhDigitsOnly
                    }

                    // Color picker
                    SectionHeader {
                        text: qsTr("Farbe")
                    }

                    Grid {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2*x
                        columns: 4
                        spacing: Theme.paddingSmall

                        Repeater {
                            model: settingsPage.colorOptions

                            delegate: Rectangle {
                                width: (parent.width - 3*Theme.paddingSmall) / 4
                                height: width
                                color: modelData.hex
                                radius: Theme.paddingSmall

                                border.color: editorPage.presetColor === modelData.hex ? Theme.highlightColor : "transparent"
                                border.width: editorPage.presetColor === modelData.hex ? 3 : 0

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: editorPage.presetColor = modelData.hex
                                }
                            }
                        }
                    }

                    // Icon picker
                    SectionHeader {
                        text: qsTr("Icon")
                    }

                    Grid {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2*x
                        columns: 4
                        spacing: Theme.paddingSmall

                        Repeater {
                            model: settingsPage.iconOptions

                            delegate: Rectangle {
                                width: (parent.width - 3*Theme.paddingSmall) / 4
                                height: width
                                color: editorPage.presetIcon === modelData ? Theme.highlightBackgroundColor : Theme.secondaryHighlightColor
                                radius: Theme.paddingSmall

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData
                                    font.pixelSize: Theme.fontSizeExtraLarge
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: editorPage.presetIcon = modelData
                                }
                            }
                        }
                    }

                    // Buttons
                    Row {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2*x
                        spacing: Theme.paddingMedium

                        Button {
                            width: parent.width / 2 - Theme.paddingSmall
                            text: qsTr("Speichern")
                            onClicked: {
                                var volumeGB = parseFloat(volumeField.text) || 0;
                                var volumeBytes = volumeGB * 1073741824;

                                // Validate input
                                if (nameField.text.length === 0) {
                                    console.log("Preset name cannot be empty");
                                    return;
                                }

                                // Find MainPage instance using pageStack.find()
                                var mainPage = pageStack.find(function(page) {
                                    return page.objectName === "mainPage";
                                });

                                if (mainPage === null) {
                                    console.log("Could not find MainPage instance");
                                    return;
                                }

                                if (editorPage.isNewPreset) {
                                    mainPage.createPreset(nameField.text, volumeBytes, editorPage.presetColor, editorPage.presetIcon);
                                    console.log("Created preset:", nameField.text);
                                } else {
                                    mainPage.updatePreset(editorPage.presetId, nameField.text, volumeBytes, editorPage.presetColor, editorPage.presetIcon);
                                    console.log("Updated preset:", editorPage.presetId);
                                }

                                // Update MainPage preset list
                                mainPage.reloadPresetsList();

                                pageStack.pop();
                                settingsPage.reloadPresetsModel();
                            }
                        }

                        Button {
                            width: parent.width / 2 - Theme.paddingSmall
                            text: qsTr("Abbrechen")
                            onClicked: pageStack.pop()
                        }
                    }

                    // Delete button for existing presets
                    Item {
                        width: parent.width
                        height: !editorPage.isNewPreset ? Theme.paddingLarge : 0
                        visible: !editorPage.isNewPreset
                    }

                    Button {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2*x
                        text: qsTr("Profil löschen")
                        color: Theme.highlightColor
                        visible: !editorPage.isNewPreset
                        onClicked: {
                            deleteRemorse.execute(qsTr("Profil wird gelöscht"), function() {
                                // Find MainPage instance using pageStack.find()
                                var mainPage = pageStack.find(function(page) {
                                    return page.objectName === "mainPage";
                                });

                                if (mainPage !== null) {
                                    var deleted = mainPage.deletePreset(editorPage.presetId);
                                    if (deleted) {
                                        console.log("Deleted preset:", editorPage.presetId);
                                        // Update MainPage preset list
                                        mainPage.reloadPresetsList();
                                    } else {
                                        console.log("Could not delete preset (last one?)");
                                    }
                                }

                                pageStack.pop();
                                settingsPage.reloadPresetsModel();
                            })
                        }
                    }

                    Item {
                        width: parent.width
                        height: Theme.paddingLarge
                    }
                }
            }

            RemorsePopup {
                id: deleteRemorse
            }
        }
    }

    RemorsePopup {
        id: resetRemorse
    }

    RemorsePopup {
        id: dbResetRemorse
    }
}
