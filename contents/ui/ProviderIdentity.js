.pragma library

var maximumProviderIDLength = 128

function hasOwnKey(item, key) {
    return item ? Object.prototype.hasOwnProperty.call(item, key) : false
}

function providerKey(value, aliases) {
    var key = String(value || "codex").toLowerCase()
    if (hasOwnKey(aliases, key) && typeof aliases[key] === "string") {
        return aliases[key]
    }
    return key
}

function providerMapKey(value) {
    var key = String(value || "")
    if (key.length === 0 || key.length > maximumProviderIDLength) {
        return ""
    }
    if (key === "prototype" || Object.prototype.hasOwnProperty.call(Object.prototype, key)) {
        return ""
    }
    if (/[\u0000-\u001f\u007f]/.test(key)) {
        return ""
    }
    return key
}
