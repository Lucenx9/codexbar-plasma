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
}
