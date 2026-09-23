.pragma library

var minimumNonTextContrastRatio = 3
// A colored accent closer than this to a warning color reads as that warning.
var minimumSeverityHueSeparationDegrees = 20
// OKLCH chroma below this is effectively gray and carries no hue to confuse.
var minimumHueChroma = 0.05

function linearColorChannel(channel) {
    var numeric = Number(channel)
    var value = isFinite(numeric) ? Math.max(0, Math.min(1, numeric)) : 0
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
    var numeric = Number(progress)
    var amount = isFinite(numeric) ? Math.max(0, Math.min(1, numeric)) : 0
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

function readableTextColor(preferred, background) {
    return contrastRatio(preferred, background) >= 4.5
        ? preferred
        : maximumContrastColor(background)
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

// OKLab lightness, chroma, and hue in degrees; see https://bottosson.github.io/posts/oklab/.
function oklch(color) {
    var r = linearColorChannel(color.r)
    var g = linearColorChannel(color.g)
    var b = linearColorChannel(color.b)
    var l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    var m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    var s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    var a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    var bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return {
        lightness: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        chroma: Math.sqrt(a * a + bb * bb),
        hue: (Math.atan2(bb, a) * 180 / Math.PI + 360) % 360
    }
}

function encodedColorChannel(value) {
    var linear = Math.max(0, Math.min(1, value))
    return linear <= 0.0031308
        ? linear * 12.92
        : 1.055 * Math.pow(linear, 1 / 2.4) - 0.055
}

// Keeps the color's OKLab lightness and hue while removing the given share of
// its chroma, so a muted brand color stays recognizable without its vividness.
function desaturatedColor(color, amount) {
    var numeric = Number(amount)
    var keep = 1 - (isFinite(numeric) ? Math.max(0, Math.min(1, numeric)) : 0)
    var r = linearColorChannel(color.r)
    var g = linearColorChannel(color.g)
    var b = linearColorChannel(color.b)
    var l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    var m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    var s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    var lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    var a = (1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s) * keep
    var bb = (0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s) * keep
    var l2 = Math.pow(lightness + 0.3963377774 * a + 0.2158037573 * bb, 3)
    var m2 = Math.pow(lightness - 0.1055613458 * a - 0.0638541728 * bb, 3)
    var s2 = Math.pow(lightness - 0.0894841775 * a - 1.2914855480 * bb, 3)
    return Qt.rgba(
        encodedColorChannel(4.0767416621 * l2 - 3.3077115913 * m2 + 0.2309699292 * s2),
        encodedColorChannel(-1.2684380046 * l2 + 2.6097574011 * m2 - 0.3413193965 * s2),
        encodedColorChannel(-0.0041960863 * l2 - 0.7034186147 * m2 + 1.7076147010 * s2),
        color.a)
}

function hueDistance(first, second) {
    var difference = Math.abs(first - second) % 360
    return Math.min(difference, 360 - difference)
}

// Returns the fallback when the accent's hue could be mistaken for one of the
// reserved warning colors; gray accents and gray reserved colors never clash.
function distinctAccentColor(accent, reservedColors, fallback) {
    var accentColor = oklch(accent)
    if (accentColor.chroma < minimumHueChroma) {
        return accent
    }
    var reserved = Array.isArray(reservedColors) ? reservedColors : []
    for (var i = 0; i < reserved.length; i++) {
        var reservedColor = oklch(reserved[i])
        if (reservedColor.chroma >= minimumHueChroma
                && hueDistance(accentColor.hue, reservedColor.hue) < minimumSeverityHueSeparationDegrees) {
            return fallback
        }
    }
    return accent
}

