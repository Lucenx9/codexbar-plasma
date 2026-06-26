.pragma library

function resetLabel(value, i18n_func) {
    var text = String(value || "").trim()
    if (text.length === 0) {
        return ""
    }
    text = text
        .replace(/([A-Za-z])(\d)/g, "$1 $2")
        .replace(/(\d)([A-Za-z])/g, "$1 $2")
        .replace(/\)([A-Za-z])/g, ") $1")
        .replace(/(am|pm)\(/ig, "$1 (")
        .replace(/\s+/g, " ")
    if (/^resets\b/i.test(text)) {
        return text.replace(/^resets\s*/i, i18n_func("Resets "))
    }
    return i18n_func("Resets %1", text)
}
