.pragma library

function globalViewIsAvailable(viewID, globalViews) {
    var candidate = String(viewID || "")
    if (!globalViews) {
        return false
    }
    return (candidate === "overview" && globalViews.overview === true)
        || (candidate === "spend" && globalViews.spend === true)
        || (candidate === "sessions" && globalViews.sessions === true)
}

function globalSelectionNeedsReconciliation(current, globalViews) {
    return current !== null
        && current !== undefined
        && current.initialized === true
        && String(current.providerID || "").length === 0
        && !globalViewIsAvailable(current.globalView, globalViews)
}

function reconcile(current, options) {
    var providerID = String(current && current.providerID || "")
    var globalView = String(current && current.globalView || "overview")
    var initialized = current && current.initialized === true
    var firstProviderID = String(options && options.firstProviderID || "")
    var automaticProviderID = String(options && options.automaticProviderID || "")
    var globalViews = options && options.globalViews || ({})
    var explicitGlobalSelection = initialized && providerID.length === 0

    if (firstProviderID.length === 0) {
        return explicitGlobalSelection && globalViewIsAvailable(globalView, globalViews)
            ? { providerID: "", globalView: globalView, initialized: true }
            : { providerID: "", globalView: globalView, initialized: false }
    }

    if (options && options.autoSelect === true) {
        if (explicitGlobalSelection && globalViewIsAvailable(globalView, globalViews)) {
            return { providerID: "", globalView: globalView, initialized: true }
        }
        return {
            providerID: automaticProviderID.length > 0 ? automaticProviderID : firstProviderID,
            globalView: globalView,
            initialized: true
        }
    }

    if (!initialized) {
        return globalViewIsAvailable("overview", globalViews)
            ? { providerID: "", globalView: "overview", initialized: true }
            : { providerID: firstProviderID, globalView: "overview", initialized: true }
    }

    if ((providerID.length > 0 && options && options.currentProviderExists === true)
            || (explicitGlobalSelection && globalViewIsAvailable(globalView, globalViews))) {
        return { providerID: providerID, globalView: globalView, initialized: true }
    }

    return { providerID: firstProviderID, globalView: globalView, initialized: true }
}
