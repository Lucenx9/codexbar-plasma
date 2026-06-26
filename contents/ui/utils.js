.pragma library

function capitalize(value) {
    var text = String(value || "")
    if (text.length === 0) {
        return ""
    }
    return text.charAt(0).toUpperCase() + text.slice(1)
}
