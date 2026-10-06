import QtQuick
import QtTest
import "../contents/ui/components" as Components

// Displayed times must follow the regional format, not Qt.formatDateTime's
// English names and fixed hour cycle. Explicit locales keep the cases
// independent of the host; the catalog stub keeps the English word order.
TestCase {
    name: "TimeLabels"

    readonly property double sample: new Date(2026, 9, 7, 14, 30).getTime()

    function i18nc(context, source) {
        var text = source;
        for (var i = 2; i < arguments.length; i++)
            text = text.replace("%" + (i - 1), String(arguments[i]));
        return text;
    }

    Components.TimeLabels {
        id: italian

        locale: Qt.locale("it_IT")
    }

    Components.TimeLabels {
        id: american

        locale: Qt.locale("en_US")
    }

    // A translation places the day before the month.
    Components.TimeLabels {
        id: reordered

        locale: Qt.locale("it_IT")

        function i18nc(context, source, first, second, third) {
            return third === undefined ? second + " " + first : second + " " + first + ", " + third;
        }
    }

    function test_italianNamesAndTwentyFourHourClock() {
        compare(italian.clockTime(sample), "14:30");
        compare(italian.weekdayTime(sample), "mer 14:30");
        compare(italian.monthDayTime(sample), "ott 7, 14:30");
    }

    function test_twelveHourClockFollowsTheLocale() {
        var time = american.clockTime(sample);
        verify(time.indexOf("2:30") === 0, time);
        verify(time.indexOf("PM") > 0, time);
        compare(american.weekdayTime(sample), "Wed " + time);
        compare(american.monthDayTime(sample), "Oct 7, " + time);
    }

    Components.TimeLabels {
        id: posix

        locale: Qt.locale("C")
    }

    function test_catalogOrdersTheParts() {
        compare(reordered.weekdayTime(sample), "14:30 mer");
        compare(reordered.monthDayTime(sample), "7 ott, 14:30");
    }

    // C's ShortFormat is HH:mm:ss; compact labels still omit seconds.
    function test_posixShortClockOmitsSeconds() {
        compare(posix.clockTime(sample), "14:30");
        compare(posix.weekdayTime(sample), "Wed 14:30");
        compare(posix.monthDayTime(sample), "Oct 7, 14:30");
    }
}
