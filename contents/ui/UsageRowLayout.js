// A safety band prevents a changing countdown from repeatedly moving the reset.
function nextInlineReset(previous, eligible, spareWidth, safetyBand) {
    if (eligible !== true || typeof spareWidth !== "number" || !isFinite(spareWidth)
        || typeof safetyBand !== "number" || !isFinite(safetyBand) || safetyBand < 0) {
        return false
    }
    return spareWidth >= (previous === true ? 0 : safetyBand)
}
