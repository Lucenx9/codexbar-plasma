import QtQuick
import QtTest
import "../contents/ui/ThemeContrast.js" as ThemeContrast

TestCase {
    name: "ThemeContrast"

    function verifyReadable(accent, background, themeTextColor) {
        var result = ThemeContrast.readableAccentColor(
            accent,
            background,
            themeTextColor)
        verify(ThemeContrast.contrastRatio(result, background) >= 3)
        return result
    }

    function test_preservesAlreadyReadableBrandColor() {
        var accent = Qt.rgba(73 / 255, 163 / 255, 176 / 255, 1)
        var background = Qt.rgba(0.08, 0.08, 0.11, 1)
        var result = verifyReadable(
            accent,
            background,
            Qt.rgba(0.94, 0.94, 0.96, 1))

        compare(result, accent)
    }

    function test_readableTextColor_data() {
        return [
            {tag: "breeze-blue", background: Qt.rgba(61 / 255, 174 / 255, 233 / 255, 1), preferred: "white", preserved: false},
            {tag: "orange-badge", background: Qt.rgba(1, 0.5, 0, 1), preferred: "white", preserved: false},
            {tag: "light-selection", background: "#eff0f1", preferred: "#232629", preserved: true},
            {tag: "dark-selection", background: "#232629", preferred: "#eff0f1", preserved: true},
            {tag: "mid-gray", background: "#777777", preferred: "#aaaaaa", preserved: false},
            {tag: "bright-selection", background: "#ffff00", preferred: "white", preserved: false},
            {tag: "dark-blue", background: "#152c70", preferred: "white", preserved: true}
        ]
    }

    function test_readableTextColor(data) {
        // Convert string fixtures to the color values used by QML bindings.
        var background = Qt.tint(data.background, "transparent")
        var preferred = Qt.tint(data.preferred, "transparent")
        var result = ThemeContrast.readableTextColor(preferred, background)
        verify(ThemeContrast.contrastRatio(result, background) >= 4.5)
        if (data.preserved)
            compare(result, preferred)
        var secondary = ThemeContrast.readableTextColor(
            ThemeContrast.interpolateColor(background, result, 0.7), background)
        verify(ThemeContrast.contrastRatio(secondary, background) >= 4.5)
    }

    function test_darkensVeryLightBrandColorOnLightTheme() {
        var accent = Qt.rgba(0.92, 0.92, 0.90, 1)
        var background = Qt.rgba(0.94, 0.94, 0.95, 1)
        var result = verifyReadable(
            accent,
            background,
            Qt.rgba(0.12, 0.12, 0.14, 1))

        verify(result.r < accent.r)
    }

    function test_lightensVeryDarkBrandColorOnDarkTheme() {
        var accent = Qt.rgba(0.08, 0.08, 0.08, 1)
        var background = Qt.rgba(0.06, 0.06, 0.08, 1)
        var result = verifyReadable(
            accent,
            background,
            Qt.rgba(0.94, 0.94, 0.96, 1))

        verify(result.r > accent.r)
    }

    function test_lowContrastThemeTextFallsBackSafely() {
        var background = Qt.rgba(0.5, 0.5, 0.5, 1)
        verifyReadable(
            Qt.rgba(0.52, 0.52, 0.52, 1),
            background,
            Qt.rgba(0.51, 0.51, 0.51, 1))
    }

    function test_unusableChannelsAndProgressStayFinite() {
        verify(ThemeContrast.linearColorChannel(undefined) === 0)
        verify(ThemeContrast.linearColorChannel(Number.NaN) === 0)
        var start = Qt.rgba(0, 0, 0, 1)
        var end = Qt.rgba(1, 1, 1, 1)
        var unusable = ThemeContrast.interpolateColor(start, end, Number.NaN)
        compare(unusable, start)
    }
}
