import QtQuick

// Clock times and short dates in the user's regional format. Qt.formatDateTime
// with a literal pattern always writes English day and month names and a fixed
// hour cycle, so every displayed time goes through here instead. The word order
// is a catalog string, so a translation can place the day before the month.
QtObject {
    id: root

    property var locale: Qt.locale()

    function clockTime(timestampMs) {
        // ShortFormat follows the regional 12/24-hour clock. Drop seconds so
        // compact labels stay HH:mm / h:mm AP even when a locale's short form
        // is HH:mm:ss (notably C).
        var format = root.locale.timeFormat(Locale.ShortFormat).replace(/:?ss/, "")
        return new Date(timestampMs).toLocaleString(root.locale, format)
    }

    function weekdayTime(timestampMs) {
        return i18nc("Abbreviated weekday %1 and clock time %2, such as Wed 14:30",
            "%1 %2",
            new Date(timestampMs).toLocaleString(root.locale, "ddd"),
            root.clockTime(timestampMs))
    }

    function monthDayTime(timestampMs) {
        var date = new Date(timestampMs)
        return i18nc("Abbreviated month %1, day of the month %2 and clock time %3, such as Oct 7, 14:30",
            "%1 %2, %3",
            date.toLocaleString(root.locale, "MMM"),
            date.toLocaleString(root.locale, "d"),
            root.clockTime(timestampMs))
    }
}
