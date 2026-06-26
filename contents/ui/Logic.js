.pragma library

function costSparklineSummary(points, i18nProvider, amountStringProvider) {
    if (!points || points.length === 0) {
        return ""
    }
    var last = points[points.length - 1]
    var label = last.label && last.label.length > 0 ? last.label : i18nProvider("Latest")
    return i18nProvider("%1: %2", label, amountStringProvider(last.cost, last.currency || "USD"))
}
