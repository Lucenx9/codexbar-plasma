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

    // Brand hues close to a theme's warning or critical color fall back to
    // their muted version; distinct hues and grays keep their own color, and
    // so does a brand whose muted version would sit closer to a pale warning.
    // Colors are real Breeze, Catppuccin Mocha, and bundled brand values.
    function test_distinctAccentColor_data() {
        var breeze = [Qt.rgba(218 / 255, 68 / 255, 83 / 255, 1), Qt.rgba(246 / 255, 116 / 255, 0, 1)]
        var mocha = [Qt.rgba(243 / 255, 139 / 255, 168 / 255, 1), Qt.rgba(249 / 255, 226 / 255, 175 / 255, 1)]
        var zai = Qt.rgba(232 / 255, 90 / 255, 106 / 255, 1)
        var claude = Qt.rgba(217 / 255, 119 / 255, 87 / 255, 1)
        var codex = Qt.rgba(73 / 255, 163 / 255, 176 / 255, 1)
        var huggingface = Qt.rgba(1, 210 / 255, 30 / 255, 1)
        return [
            {tag: "zai-breeze-critical", accent: zai, reserved: breeze, kept: false},
            {tag: "zai-mocha-critical", accent: zai, reserved: mocha, kept: false},
            {tag: "claude-breeze-warning", accent: claude, reserved: breeze, kept: false},
            {tag: "claude-mocha", accent: claude, reserved: mocha, kept: true},
            {tag: "codex-breeze", accent: codex, reserved: breeze, kept: true},
            {tag: "yellow-beside-pale-cream-warning", accent: huggingface, reserved: mocha, kept: true},
            {tag: "gray-accent", accent: Qt.rgba(0.5, 0.5, 0.5, 1), reserved: breeze, kept: true},
            {tag: "gray-reserved", accent: zai, reserved: [Qt.rgba(0.8, 0.8, 0.8, 1)], kept: true},
            {tag: "hue-wraps-at-zero", accent: Qt.rgba(0.9, 0.3, 0.45, 1),
                reserved: [Qt.rgba(0.9, 0.35, 0.3, 1)], kept: false},
            {tag: "no-reserved-colors", accent: zai, reserved: undefined, kept: true}
        ]
    }

    function test_distinctAccentColor(data) {
        var fallback = ThemeContrast.desaturatedColor(data.accent, 0.75)
        var result = ThemeContrast.distinctAccentColor(data.accent, data.reserved, fallback)
        compare(result, data.kept ? data.accent : fallback)
    }

    // A clashing hue alone does not justify a fallback that is perceptually
    // closer to the reserved color than the accent already was.
    function test_distinctAccentColorRejectsCloserFallback() {
        var accent = Qt.rgba(232 / 255, 90 / 255, 106 / 255, 1)
        var critical = Qt.rgba(218 / 255, 68 / 255, 83 / 255, 1)
        compare(ThemeContrast.distinctAccentColor(accent, [critical], critical), accent)
        verify(ThemeContrast.colorDistance(accent, accent) < 1e-9)
        verify(ThemeContrast.colorDistance(accent, critical) > 0)
    }

    // A fallback that lands as close to any reserved color as the accent was
    // to its nearest one is rejected, even when its nearest color changed.
    // Moving away from the nearest color while staying far from every other
    // reserved color is the muting the function exists for.
    function test_distinctAccentColorComparesEveryReservedColor() {
        var accent = Qt.rgba(0.86, 0.28, 0.38, 1)
        var near = Qt.rgba(0.855, 0.27, 0.42, 1)
        var far = Qt.rgba(0.18, 0.34, 0.62, 1)
        compare(ThemeContrast.distinctAccentColor(accent, [near, far], far), accent)
        var fallback = Qt.rgba(0.76, 0.18, 0.48, 1)
        verify(ThemeContrast.hueDistance(ThemeContrast.oklch(accent).hue, ThemeContrast.oklch(near).hue)
            < ThemeContrast.minimumSeverityHueSeparationDegrees)
        verify(ThemeContrast.colorDistance(fallback, near) > ThemeContrast.colorDistance(accent, near))
        verify(ThemeContrast.colorDistance(fallback, far) > ThemeContrast.colorDistance(accent, near))
        compare(ThemeContrast.distinctAccentColor(accent, [near, far], fallback), fallback)
    }

    // A fixed reduction leaves very saturated brands such as Amp and Mistral
    // above the severity hue threshold, so the reduction adapts to the accent.
    // Muted results stay under the threshold and readable on real themes; the
    // contrast correction must not raise the chroma back over it.
    function test_verySaturatedBrandMutesBelowHueThreshold_data() {
        var amp = Qt.rgba(220 / 255, 38 / 255, 38 / 255, 1)
        var mistral = Qt.rgba(1, 80 / 255, 15 / 255, 1)
        var breezeLight = {
            tag: "amp-breeze-light", accent: amp,
            background: Qt.rgba(239 / 255, 240 / 255, 241 / 255, 1), text: Qt.rgba(35 / 255, 38 / 255, 41 / 255, 1)
        }
        var breezeDark = {
            tag: "mistral-breeze-dark", accent: mistral,
            background: Qt.rgba(35 / 255, 38 / 255, 41 / 255, 1), text: Qt.rgba(252 / 255, 252 / 255, 252 / 255, 1)
        }
        var mocha = {
            tag: "amp-catppuccin-mocha", accent: amp,
            background: Qt.rgba(30 / 255, 30 / 255, 46 / 255, 1), text: Qt.rgba(205 / 255, 214 / 255, 244 / 255, 1)
        }
        return [breezeLight, breezeDark, mocha]
    }

    function test_verySaturatedBrandMutesBelowHueThreshold(data) {
        verify(ThemeContrast.oklch(data.accent).chroma * 0.25 >= ThemeContrast.minimumHueChroma)
        var muted = ThemeContrast.mutedAccentColor(
            data.accent,
            Math.max(0.75, ThemeContrast.chromaReduction(data.accent)),
            data.background, data.text)
        verify(ThemeContrast.oklch(muted).chroma < ThemeContrast.minimumHueChroma)
        verify(ThemeContrast.contrastRatio(muted, data.background) >= 3)
    }

    // Muting keeps lightness, hue, and alpha while removing the requested
    // share of chroma; the ends of the range are identity and gray.
    function test_desaturatedColorKeepsLightnessAndHue() {
        var zai = Qt.rgba(232 / 255, 90 / 255, 106 / 255, 0.8)
        var original = ThemeContrast.oklch(zai)
        var muted = ThemeContrast.desaturatedColor(zai, 0.75)
        var result = ThemeContrast.oklch(muted)
        verify(Math.abs(result.lightness - original.lightness) < 0.005)
        verify(Math.abs(result.chroma - original.chroma * 0.25) < 0.005)
        verify(ThemeContrast.hueDistance(result.hue, original.hue) < 2)
        compare(muted.a, zai.a)
        verify(ThemeContrast.oklch(ThemeContrast.desaturatedColor(zai, 1)).chroma < 0.002)
        var same = ThemeContrast.desaturatedColor(zai, 0)
        verify(Math.abs(same.r - zai.r) < 0.004 && Math.abs(same.g - zai.g) < 0.004
            && Math.abs(same.b - zai.b) < 0.004)
        var clamped = ThemeContrast.desaturatedColor(zai, "invalid")
        verify(Math.abs(clamped.r - zai.r) < 0.004)
    }

    // Muting can lower luminance contrast on a light panel; the muted accent
    // is corrected like any other accent. Colors are Z.ai's brand and Breeze
    // Light, where plain desaturation measured 2.83:1.
    function test_mutedAccentColorKeepsNonTextContrast() {
        var background = Qt.rgba(239 / 255, 240 / 255, 241 / 255, 1)
        var text = Qt.rgba(35 / 255, 38 / 255, 41 / 255, 1)
        var accent = ThemeContrast.readableAccentColor(
            Qt.rgba(232 / 255, 90 / 255, 106 / 255, 1), background, text)
        verify(ThemeContrast.contrastRatio(ThemeContrast.desaturatedColor(accent, 0.75), background) < 3)
        var muted = ThemeContrast.mutedAccentColor(accent, 0.75, background, text)
        verify(ThemeContrast.contrastRatio(muted, background) >= 3)
        verify(ThemeContrast.oklch(muted).chroma < ThemeContrast.minimumHueChroma)
    }
}

