.pragma library
.import "SafeText.js" as SafeText

// Panel text is a composition of the optional segments enabled in settings:
// the provider name, the usage figure, and the credit balance. A horizontal
// panel keeps a bounded width, so a crowded meter row can leave the label less
// room than the full composition needs.
//
// Eliding the composition is the wrong degradation: it cuts mid-value, so
// "Claude 82% used 125cr" becomes "Claude 82% u..." and the credit balance is
// not merely shortened but silently replaced by a fragment that reads as a
// different value. Whole segments are surrendered instead, in a fixed priority
// order, so every rendered segment stays complete and truthful. The provider
// icon sits beside the label and already identifies the provider, so the name
// is surrendered first; the credit balance is a secondary reading; the usage
// figure is the reading the widget exists for, so it is kept last. Callers
// keep the full composition for tooltips and accessible names.
var segmentIDs = ["name", "usage", "credits"];

// Ascending importance: the first entry present is surrendered first.
var dropOrder = ["name", "credits", "usage"];

// The provider name leads that order only while the icon beside the label is
// distinctive. A provider the widget has no bundled icon for renders as one
// generic icon in the theme highlight, shared with every other such provider,
// so its name is the only identification the panel has left. Callers mark the
// name segment `identifying` in that case and it then outlives the balance.
var identifyingNameDropOrder = ["credits", "name", "usage"];

var maximumSegmentLength = 200;

function normalizedSegments(value) {
    var source = Array.isArray(value) ? value.slice(0, segmentIDs.length * 2) : [];
    var result = [];
    var seen = ({});

    for (var i = 0; i < source.length; i++) {
        var entry = source[i];
        if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
            continue;
        }
        var id = String(entry.id || "");
        if (segmentIDs.indexOf(id) === -1 || seen[id] === true) {
            continue;
        }
        var text = SafeText.boundedDisplayText(entry.text, maximumSegmentLength);
        if (text.length === 0) {
            continue;
        }
        seen[id] = true;
        result.push({ id: id, text: text, identifying: entry.identifying === true });
    }
    return result;
}

function surrenderOrder(segments) {
    for (var i = 0; i < segments.length; i++) {
        if (segments[i].id === "name" && segments[i].identifying) {
            return identifyingNameDropOrder;
        }
    }
    return dropOrder;
}

// Progressively smaller compositions, widest first, each keeping the caller's
// display order. One segment is surrendered per step, so a caller measuring
// candidates gets at most one composition per known segment id. The empty composition is never offered: a label that cannot
// fit even its most important segment is elided by the caller rather than
// dropped, so an enabled segment never disappears without a trace.
function compositions(value) {
    var segments = normalizedSegments(value);
    if (segments.length === 0) {
        return [];
    }

    var result = [segments];
    var remaining = segments;
    var order = surrenderOrder(segments);
    for (var i = 0; i < order.length && remaining.length > 1; i++) {
        var dropped = order[i];
        var next = remaining.filter(function(segment) {
            return segment.id !== dropped;
        });
        if (next.length === remaining.length) {
            continue;
        }
        remaining = next;
        result.push(remaining);
    }
    return result;
}

function texts(value) {
    var source = Array.isArray(value) ? value : [];
    var result = [];
    for (var i = 0; i < source.length; i++) {
        var composition = Array.isArray(source[i]) ? source[i] : [];
        var parts = [];
        for (var j = 0; j < composition.length; j++) {
            parts.push(composition[j].text);
        }
        result.push(parts.join(" "));
    }
    return result;
}

function segmentTexts(value) {
    return texts(compositions(value));
}

// The whole label, for tooltips, accessible names, and every caller that is not
// bound by the panel width.
function fullText(value) {
    var composed = segmentTexts(value);
    return composed.length > 0 ? composed[0] : "";
}

// The index of the widest composition that fits, or the narrowest one when
// none does. Returns -1 only when there is nothing to render, so the caller
// can distinguish "no text" from "the last resort, elided".
function fittedIndex(widths, availableWidth) {
    var source = Array.isArray(widths) ? widths : [];
    if (source.length === 0) {
        return -1;
    }
    var available = Number(availableWidth);
    if (!isFinite(available) || available < 0) {
        available = 0;
    }
    for (var i = 0; i < source.length; i++) {
        var width = source[i];
        if (typeof width === "number" && isFinite(width) && width >= 0 && width <= available) {
            return i;
        }
    }
    return source.length - 1;
}
