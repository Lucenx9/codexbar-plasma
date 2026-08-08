.pragma library

var minimumNonTextContrastRatio = 3

function linearColorChannel(channel) {
    var value = Math.max(0, Math.min(1, Number(channel)))
    return value <= 0.04045
        ? value / 12.92
        : Math.pow((value + 0.055) / 1.055, 2.4)
}

function relativeLuminance(color) {
    return (0.2126 * linearColorChannel(color.r))
        + (0.7152 * linearColorChannel(color.g))
        + (0.0722 * linearColorChannel(color.b))
}

function contrastRatio(foreground, background) {
    var foregroundLuminance = relativeLuminance(foreground)
    var backgroundLuminance = relativeLuminance(background)
    var lighter = Math.max(foregroundLuminance, backgroundLuminance)
    var darker = Math.min(foregroundLuminance, backgroundLuminance)
    return (lighter + 0.05) / (darker + 0.05)
}

function interpolateColor(start, end, progress) {
    var amount = Math.max(0, Math.min(1, Number(progress)))
    return Qt.rgba(
        start.r + ((end.r - start.r) * amount),
        start.g + ((end.g - start.g) * amount),
        start.b + ((end.b - start.b) * amount),
        start.a + ((end.a - start.a) * amount))
}

function maximumContrastColor(background) {
    var dark = Qt.rgba(0, 0, 0, 1)
    var light = Qt.rgba(1, 1, 1, 1)
    return contrastRatio(dark, background) >= contrastRatio(light, background)
        ? dark
        : light
}

function readableAccentColor(accent, background, themeTextColor) {
    if (contrastRatio(accent, background) >= minimumNonTextContrastRatio) {
        return accent
    }

    for (var step = 1; step <= 10; step++) {
        var candidate = interpolateColor(accent, themeTextColor, step / 10)
        if (contrastRatio(candidate, background) >= minimumNonTextContrastRatio) {
            return candidate
        }
    }
    return maximumContrastColor(background)
}
