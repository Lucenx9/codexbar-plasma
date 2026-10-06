import QtQuick

// Clock times and short dates in the user's regional format. Qt.formatDateTime
// with a literal pattern always writes English day and month names and a fixed
// hour cycle, so every displayed time goes through here instead. The word order
// is a catalog string, so a translation can place the day before the month.
QtObject {
    id: root

    property var locale: Qt.locale()

    function clockTime(timestampMs) {
        return new Date(timestampMs).toLocaleTimeString(root.locale, Locale.ShortFormat)
    }

    function weekdayTime(timestampMs) {
        return i18nc("Abbreviated weekday %1 and clock time %2, such as Wed 14:30",
            "%1 %2",
            root.locale.toString(new Date(timestampMs), "ddd"),
            root.clockTime(timestampMs))
    }

    function monthDayTime(timestampMs) {
        var date = new Date(timestampMs)
        return i18nc("Abbreviated month %1, day of the month %2 and clock time %3, such as Oct 7, 14:30",
            "%1 %2, %3",
            root.locale.toString(date, "MMM"),
            root.locale.toString(date, "d"),
            root.clockTime(timestampMs))
    }
}
