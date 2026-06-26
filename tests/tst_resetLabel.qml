import QtQuick
import QtTest
import "../contents/ui/utils.js" as Logic

TestCase {
    name: "ResetLabelTests"

    // Mock i18n
    function i18n(text, arg1) {
        if (arg1 !== undefined) {
            return text.replace("%1", arg1);
        }
        return text;
    }

    function resetLabel(value) {
        return Logic.resetLabel(value, i18n);
    }

    function test_resetLabel() {
        // Edge cases
        compare(resetLabel(""), "");
        compare(resetLabel(null), "");
        compare(resetLabel(undefined), "");

        // Basic formatting
        compare(resetLabel("10am"), "Resets 10 am");
        compare(resetLabel("10pm"), "Resets 10 pm");
        compare(resetLabel("10AM"), "Resets 10 AM");
        compare(resetLabel("10PM"), "Resets 10 PM");

        // "Resets" prefix replacement
        compare(resetLabel("Resets 10am"), "Resets 10 am");
        compare(resetLabel("resets 10am"), "Resets 10 am");
        compare(resetLabel("RESETS 10am"), "Resets 10 am");
        compare(resetLabel("resets10am"), "Resets 10 am");

        // Complex spacing/bracket replacements
        compare(resetLabel("10am(UTC)"), "Resets 10 am (UTC)");
        compare(resetLabel("10pm(PST)"), "Resets 10 pm (PST)");

        // Extra spaces
        compare(resetLabel("  10am  "), "Resets 10 am");
        compare(resetLabel("10 am"), "Resets 10 am");
        compare(resetLabel("  resets   10am  "), "Resets 10 am");

        // Complex inputs representing realistic API responses
        compare(resetLabel("tomorrow at 10am"), "Resets tomorrow at 10 am");
        compare(resetLabel("11:59pm"), "Resets 11:59 pm");
    }
}
