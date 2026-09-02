.pragma library
.import "Guards.js" as Guards

function validResponseContext(context) {
    return !!context && typeof context === "object" && !Array.isArray(context)
        && Guards.hasOwnKey(context, "commandSource")
        && typeof context.commandSource === "string"
        && context.commandSource.length > 0
        && Guards.hasOwnKey(context, "revision")
        && typeof context.revision === "number"
        && isFinite(context.revision)
        && context.revision >= 0
        && Math.floor(context.revision) === context.revision
        && Guards.hasOwnKey(context, "stamp")
        && typeof context.stamp === "string"
}

function validContext(context) {
    return validResponseContext(context) && context.stamp.length > 0
}

function contextValuesMatch(left, right) {
    return left.commandSource === right.commandSource
        && left.revision === right.revision
        && left.stamp === right.stamp
}

function contextsMatch(left, right) {
    return validContext(left) && validContext(right)
        && contextValuesMatch(left, right)
}

function responseContextsMatch(left, right) {
    return validResponseContext(left) && validResponseContext(right)
        && contextValuesMatch(left, right)
}

function copyProviderIDs(providerIDs) {
    if (!Array.isArray(providerIDs)) {
        return null
    }
    var copy = []
    for (var i = 0; i < providerIDs.length; i++) {
        if (typeof providerIDs[i] !== "string" || providerIDs[i].length === 0) {
            return null
        }
        copy.push(providerIDs[i])
    }
    return copy
}

function remember(providerIDs, context) {
    var copiedProviderIDs = copyProviderIDs(providerIDs)
    if (copiedProviderIDs === null || !validContext(context)) {
        return null
    }
    return {
        context: {
            commandSource: context.commandSource,
            revision: context.revision,
            stamp: context.stamp
        },
        providerIDs: copiedProviderIDs
    }
}

function read(cache, currentContext) {
    if (!cache || typeof cache !== "object" || Array.isArray(cache)
            || !Guards.hasOwnKey(cache, "context")
            || !Guards.hasOwnKey(cache, "providerIDs")
            || !contextsMatch(cache.context, currentContext)) {
        return null
    }
    return copyProviderIDs(cache.providerIDs)
}
