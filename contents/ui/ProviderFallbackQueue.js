.pragma library
.import "Guards.js" as Guards

// Pure scheduler for provider-scoped usage fallbacks. The caller owns command
// construction, process effects, payload normalization, and user-facing text;
// this module owns only bounded queue transitions and final provider ordering.
function begin(requests, options) {
    var maximumSnapshots = positiveInteger(options && options.maximumSnapshots, 1)
    var maximumConcurrent = Math.min(
        positiveInteger(options && options.maximumConcurrent, 1),
        maximumSnapshots)
    var validRequests = normalizedRequests(requests, maximumSnapshots)
    var queue = validRequests.slice()
    var sourcesToStart = queue.splice(0, maximumConcurrent)
    return {
        state: {
            queue: queue,
            active: sourcesToStart.slice(),
            resultsByProvider: ({}),
            order: validRequests.map(function(request) { return request.providerID }),
            maximumConcurrent: maximumConcurrent,
            maximumSnapshots: maximumSnapshots
        },
        sourcesToStart: sourcesToStart,
        finished: validRequests.length === 0,
        orderedItems: []
    }
}

function positiveInteger(value, fallback) {
    if (typeof value !== "number") {
        return fallback
    }
    var number = Math.floor(value)
    return isFinite(number) && number > 0 ? number : fallback
}

function normalizedRequests(requests, maximumRequests) {
    var items = Array.isArray(requests) ? requests : []
    var validRequests = []
    var seenSources = []
    var seenProviders = []
    var itemLimit = Math.min(items.length, maximumRequests)
    for (var i = 0; i < itemLimit; i++) {
        var item = items[i]
        if (!item || typeof item !== "object" || Array.isArray(item)
                || !Guards.hasOwnKey(item, "sourceName")
                || !Guards.hasOwnKey(item, "providerID")
                || typeof item.sourceName !== "string"
                || typeof item.providerID !== "string"
                || item.sourceName.trim().length === 0
                || item.providerID.trim().length === 0
                || Guards.isUnsafeObjectKey(item.providerID)
                || seenSources.indexOf(item.sourceName) !== -1
                || seenProviders.indexOf(item.providerID) !== -1) {
            continue
        }
        seenSources.push(item.sourceName)
        seenProviders.push(item.providerID)
        validRequests.push({
            sourceName: item.sourceName,
            providerID: item.providerID
        })
    }
    return validRequests
}

function complete(state, result) {
    if (!result || typeof result !== "object" || Array.isArray(result)
            || !Guards.hasOwnKey(result, "sourceName")
            || !Guards.hasOwnKey(result, "item")
            || typeof result.sourceName !== "string"
            || (result.item !== null
                && (typeof result.item !== "object" || Array.isArray(result.item)))) {
        return unchangedTransition(state)
    }
    var active = state.active.slice()
    var completedIndex = -1
    for (var i = 0; i < active.length; i++) {
        if (active[i].sourceName === result.sourceName) {
            completedIndex = i
            break
        }
    }
    if (completedIndex === -1) {
        return unchangedTransition(state)
    }

    var completedRequest = active.splice(completedIndex, 1)[0]
    var resultsByProvider = Guards.copyObject(state.resultsByProvider)
    if (result.item !== null) {
        resultsByProvider[completedRequest.providerID] = result.item
    }

    var queue = state.queue.slice()
    var sourcesToStart = []
    while (active.length < state.maximumConcurrent && queue.length > 0) {
        var nextRequest = queue.shift()
        active.push(nextRequest)
        sourcesToStart.push(nextRequest)
    }

    var nextState = {
        queue: queue,
        active: active,
        resultsByProvider: resultsByProvider,
        order: state.order.slice(),
        maximumConcurrent: state.maximumConcurrent,
        maximumSnapshots: state.maximumSnapshots
    }
    var finished = queue.length === 0 && active.length === 0
    return {
        state: nextState,
        sourcesToStart: sourcesToStart,
        finished: finished,
        orderedItems: finished ? finalItems(nextState) : []
    }
}

function unchangedTransition(state) {
    var finished = state.queue.length === 0 && state.active.length === 0
    return {
        state: state,
        sourcesToStart: [],
        finished: finished,
        orderedItems: finished ? finalItems(state) : []
    }
}

function finalItems(state) {
    var orderedItems = []
    for (var i = 0; i < state.order.length
            && orderedItems.length < state.maximumSnapshots; i++) {
        var providerID = state.order[i]
        if (Guards.hasOwnKey(state.resultsByProvider, providerID)) {
            orderedItems.push(state.resultsByProvider[providerID])
        }
    }
    return orderedItems
}
