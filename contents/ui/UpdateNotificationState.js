.import "Guards.js" as Guards
.import "ProviderNormalizer.js" as Normalizer

function safeReleaseUrl(url) {
    var candidate = typeof url === "string" ? url.trim() : ""
    return candidate.length <= 2048 && Normalizer.httpsUrlHost(candidate) === "github.com" ? candidate : ""
}

function widgetCandidate(version, assetUrl, lastVersion) {
    var cleanVersion = String(version || "").trim()
    var memoKey = cleanVersion.length > 0 ? cleanVersion : assetUrl
    if (!memoKey || memoKey.length === 0 || memoKey === lastVersion) return null
    return { version: cleanVersion, memoKey: memoKey }
}

function usableSource(sourceName) {
    return typeof sourceName === "string" && sourceName.length > 0 && !Guards.isUnsafeObjectKey(sourceName)
}

function register(pending, sourceName, releaseUrl) {
    var nextPending = Guards.copyObject(pending)
    var url = safeReleaseUrl(releaseUrl)
    if (usableSource(sourceName) && url.length > 0) nextPending[sourceName] = url
    return nextPending
}

function consume(pending, sourceName) {
    var nextPending = Guards.copyObject(pending)
    var releaseUrl = ""
    if (usableSource(sourceName) && Guards.hasOwnKey(nextPending, sourceName)) {
        releaseUrl = safeReleaseUrl(nextPending[sourceName])
        delete nextPending[sourceName]
    }
    return { nextPending: nextPending, releaseUrl: releaseUrl }
}
