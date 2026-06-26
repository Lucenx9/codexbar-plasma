.pragma library

function scaledTokenCount(value) {
    if (value >= 10) {
        return Number(value).toFixed(0)
    }
    var text = Number(value).toFixed(1)
    return text.replace(/\.0$/, "")
}
