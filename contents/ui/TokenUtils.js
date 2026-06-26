.pragma library

function sumTokenParts(inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens) {
    var total = 0
    var values = [inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens]
    for (var i = 0; i < values.length; i++) {
        if (isFinite(Number(values[i])) && Number(values[i]) > 0) {
            total += Number(values[i])
        }
    }
    return total > 0 ? total : Number.NaN
}
