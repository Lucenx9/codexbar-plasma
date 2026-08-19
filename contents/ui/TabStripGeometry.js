.pragma library

// Where the provider tab strip has to scroll to.
//
// The tab strip is a Flickable whose content is wider than its viewport. Two
// decisions drive every scroll it performs, and both are arithmetic the QML
// around them cannot express clearly:
//
//   * a requested position has to stay inside the flickable range, including
//     the case where the content is narrower than the viewport and the only
//     valid position is 0;
//   * revealing a tab has to distinguish "already visible" from "off the left
//     edge" from "off the right edge", and answer with a position rather than
//     scrolling twice.
//
// The rest of the strip stays in QML: walking the parent chain to recognise a
// tab, and moving focus along the focus chain, both need a live scene and are
// not arithmetic.

// Flickables accept any `contentX`, including one that leaves blank space past
// the end. Content narrower than its viewport has exactly one valid position,
// so the lower clamp has to win over the upper one.
function boundedPosition(position, contentWidth, viewportWidth) {
    var span = Number(contentWidth) - Number(viewportWidth)
    var upper = isFinite(span) && span > 0 ? span : 0
    var requested = Number(position)
    if (!isFinite(requested)) {
        return 0
    }
    return Math.max(0, Math.min(upper, requested))
}

// Returns the `contentX` that brings the item fully into view with `margin` of
// breathing room, or null when it is already visible and must not be scrolled.
//
// Returning null rather than the current position is what keeps a tab that is
// already on screen from restarting the scroll animation every time the strip
// re-reports its selection.
function revealPosition(itemLeft, itemWidth, contentX, viewportWidth, margin) {
    var left = Number(itemLeft)
    var width = Number(itemWidth)
    var origin = Number(contentX)
    var viewport = Number(viewportWidth)
    var gap = Number(margin)
    if (!isFinite(left) || !isFinite(width) || !isFinite(origin)
            || !isFinite(viewport) || !isFinite(gap)) {
        return null
    }

    var right = left + width
    if (left - gap < origin) {
        return left - gap
    }
    if (right + gap > origin + viewport) {
        return right + gap - viewport
    }
    return null
}
