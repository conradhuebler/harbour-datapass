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
        }
    }

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

    // Settings range constraints
    property int minInterval: 3600000   // 1 h in ms
    property int maxInterval: 43200000  // 12 h in ms

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
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

    RemorsePopup {
        id: resetRemorse
    }
}
