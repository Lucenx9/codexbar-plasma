import QtQuick
import "../Guards.js" as Guards

// The one provider display-name table. The names are literal i18n() strings
// because gettext scans this file; they cannot live in a .pragma library
// module, whose scope never sees Plasma's localized context. Pages keep
// their own wrappers for CLI-preferred names and privacy fallbacks.
QtObject {
    id: root

    // Bundled fallback title for a resolved provider key. `privateFallback`
    // is an already-localized privacy label the page supplies; it wins only
    // when the key is missing from the table, so bundled names keep masking
    // it. Unknown and future providers degrade to their capitalized key.
    function titleForKey(key, privateFallback) {
        var names = {
            "abacus": i18n("Abacus AI"),
            "aiand": i18n("ai&"),
            "alibaba": i18n("Alibaba"),
            "alibabatokenplan": i18n("Alibaba Token Plan"),
            "amp": i18n("Amp"),
            "antigravity": i18n("Antigravity"),
            "augment": i18n("Augment"),
            "azureopenai": i18n("Azure OpenAI"),
            "bedrock": i18n("AWS Bedrock"),
            "chutes": i18n("Chutes"),
            "claude": i18n("Claude"),
            "clawrouter": i18n("ClawRouter"),
            "clinepass": i18n("ClinePass"),
            "codebuff": i18n("Codebuff"),
            "coderabbit": i18n("CodeRabbit"),
            "codex": i18n("Codex"),
            "commandcode": i18n("Command Code"),
            "copilot": i18n("Copilot"),
            "crof": i18n("Crof"),
            "crossmodel": i18n("CrossModel"),
            "cursor": i18n("Cursor"),
            "deepgram": i18n("Deepgram"),
            "deepinfra": i18n("DeepInfra"),
            "deepseek": i18n("DeepSeek"),
            "devin": i18n("Devin"),
            "doubao": i18n("Doubao"),
            "elevenlabs": i18n("ElevenLabs"),
            "factory": i18n("Droid"),
            "fireworks": i18n("Fireworks"),
            "gemini": i18n("Gemini"),
            "grok": i18n("Grok"),
            "groq": i18n("Groq"),
            "huggingface": i18n("Hugging Face"),
            "ibmbob": i18n("IBM Bob"),
            "jetbrains": i18n("JetBrains AI"),
            "kilo": i18n("Kilo"),
            "kimi": i18n("Kimi Code"),
            "kimik2": i18n("Kimi K2 (unofficial)"),
            "kiro": i18n("Kiro"),
            "litellm": i18n("LiteLLM"),
            "llmproxy": i18n("LLM Proxy"),
            "longcat": i18n("LongCat"),
            "manus": i18n("Manus"),
            "mimo": i18n("Xiaomi MiMo"),
            "minimax": i18n("MiniMax"),
            "mistral": i18n("Mistral"),
            "moonshot": i18n("Moonshot / Kimi Open Platform"),
            "muse": i18n("Muse Code"),
            "neuralwatt": i18n("Neuralwatt"),
            "nous": i18n("Nous Portal"),
            "notion": i18n("Notion AI"),
            "ollama": i18n("Ollama"),
            "openai": i18n("OpenAI"),
            "opencode": i18n("OpenCode"),
            "opencodego": i18n("OpenCode Go"),
            "openrouter": i18n("OpenRouter"),
            "perplexity": i18n("Perplexity"),
            "poe": i18n("Poe"),
            "qoder": i18n("Qoder"),
            "qwencloud": i18n("Qwen Cloud"),
            "replicate": i18n("Replicate"),
            "sakana": i18n("Sakana AI"),
            "stepfun": i18n("StepFun"),
            "sub2api": i18n("sub2api"),
            "synthetic": i18n("Synthetic"),
            "t3chat": i18n("T3 Chat"),
            "venice": i18n("Venice"),
            "vertexai": i18n("Vertex AI"),
            "warp": i18n("Warp"),
            "wayfinder": i18n("Wayfinder"),
            "windsurf": i18n("Windsurf"),
            "xai": i18n("xAI"),
            "zai": i18n("z.ai / GLM"),
            "zed": i18n("Zed"),
            "zenmux": i18n("ZenMux"),
            "zoommate": i18n("ZoomMate")
        }

        if (Guards.hasOwnKey(names, key)) {
            return names[key]
        }
        if (privateFallback !== undefined && String(privateFallback).length > 0) {
            return privateFallback
        }
        var words = String(key).replace(/[_-]/g, " ").split(" ")
        for (var i = 0; i < words.length; i++) {
            if (words[i].length > 0) {
                words[i] = words[i].charAt(0).toUpperCase() + words[i].slice(1)
            }
        }
        return words.join(" ")
    }
}
