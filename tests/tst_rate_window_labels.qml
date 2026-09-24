import QtQuick
import QtTest
import "../contents/ui/components" as Components

// Every usage row the popup and panel render is titled by this table. A
// provider-specific label that silently fell back to the generic lane name
// would still look plausible, so each case pins one real provider entry.
TestCase {
    name: "RateWindowLabels"

    // Catalog strings are stubbed so the labels read back in English.
    Components.RateWindowLabels {
        id: labels

        function i18n(text) {
            return text;
        }
    }

    function test_providerSpecificLabels_data() {
        return [
            { tag: "alibaba-primary", key: "alibaba", lane: "primary", label: "5-hour" },
            { tag: "amp-primary", key: "amp", lane: "primary", label: "Amp Free" },
            { tag: "antigravity-secondary", key: "antigravity", lane: "secondary", label: "Claude and GPT" },
            { tag: "amp-secondary", key: "amp", lane: "secondary", label: "Balance" },
            { tag: "cursor-secondary", key: "cursor", lane: "secondary", label: "Auto" },
            // Official 0.66.0 descriptors: DevPass plan credits and premium
            // weekly lanes, and llmman's daemon memory, which is not a session.
            { tag: "devpass-primary", key: "devpass", lane: "primary", label: "Plan credits" },
            { tag: "devpass-secondary", key: "devpass", lane: "secondary", label: "Premium weekly" },
            { tag: "llmman-primary", key: "llmman", lane: "primary", label: "Memory" },
            { tag: "opencodego-tertiary", key: "opencodego", lane: "tertiary", label: "Monthly" },
            { tag: "claude-tertiary", key: "claude", lane: "tertiary", label: "Sonnet" },
            { tag: "cursor-tertiary", key: "cursor", lane: "tertiary", label: "API" },
            { tag: "gemini-tertiary", key: "gemini", lane: "tertiary", label: "Flash Lite" }
        ];
    }

    function test_providerSpecificLabels(data) {
        compare(labels.labelForLane(data.key, data.lane), data.label);
    }

    // A provider added upstream has no entry yet; it must still get a
    // readable generic name for each lane rather than an empty title.
    function test_unknownProvidersFallBackToGenericLaneNames_data() {
        return [
            { tag: "primary", lane: "primary", label: "Session" },
            { tag: "secondary", lane: "secondary", label: "Weekly" },
            { tag: "tertiary", lane: "tertiary", label: "Opus" },
            { tag: "other", lane: "quaternary", label: "Usage" }
        ];
    }

    function test_unknownProvidersFallBackToGenericLaneNames(data) {
        compare(labels.labelForLane("future-provider", data.lane), data.label);
    }
}
