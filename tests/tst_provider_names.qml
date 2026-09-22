import QtQuick
import QtTest
import "../contents/ui/components" as Components

// The bundled table is the fallback title when the CLI supplies no display
// name, so these tests are written from the names `codexbar config providers`
// emits, not from the table itself: a half-finished provider addition lands
// here without a title.
TestCase {
    name: "ProviderNames"

    // The catalog strings are stubbed the way the page harnesses stub i18n
    // itself, so the fallback titles read back in English.
    Components.ProviderNames {
        id: providerNames

        function i18n(text) {
            return text;
        }
    }

    function test_lateAddedProvidersHaveBundledFallbackTitles_data() {
        return [
            { tag: "clawrouter", key: "clawrouter", title: "ClawRouter" },
            { tag: "coderabbit", key: "coderabbit", title: "CodeRabbit" },
            { tag: "crossmodel", key: "crossmodel", title: "CrossModel" },
            { tag: "elevenlabs", key: "elevenlabs", title: "ElevenLabs" },
            { tag: "fireworks", key: "fireworks", title: "Fireworks" },
            { tag: "helmcode", key: "helmcode", title: "Helmcode" },
            { tag: "huggingface", key: "huggingface", title: "Hugging Face" },
            { tag: "ibmbob", key: "ibmbob", title: "IBM Bob" },
            { tag: "kimi", key: "kimi", title: "Kimi Code" },
            { tag: "minimax", key: "minimax", title: "MiniMax" },
            { tag: "moonshot", key: "moonshot", title: "Moonshot / Kimi Open Platform" },
            { tag: "muse", key: "muse", title: "Muse Code" },
            { tag: "nous", key: "nous", title: "Nous Portal" },
            { tag: "qoder", key: "qoder", title: "Qoder" },
            { tag: "replicate", key: "replicate", title: "Replicate" },
            { tag: "stepfun", key: "stepfun", title: "StepFun" },
            { tag: "typesafe", key: "typesafe", title: "TypeSafe" },
            { tag: "v0", key: "v0", title: "v0" },
            { tag: "wayfinder", key: "wayfinder", title: "Wayfinder" },
            { tag: "zai", key: "zai", title: "z.ai / GLM" }
        ];
    }

    function test_lateAddedProvidersHaveBundledFallbackTitles(data) {
        compare(providerNames.titleForKey(data.key, ""), data.title);
    }
}
