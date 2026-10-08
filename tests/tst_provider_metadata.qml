import QtQuick
import QtTest
import "../contents/ui/ProviderIdentity.js" as ProviderIdentity

TestCase {
    name: "ProviderMetadata"

    // Expected fallback metadata is independent of the production table layout.
    // Preserve the contracts formerly checked by parity and theme scripts.

    function test_docs_data() {
        return [
            {tag: "aiand", provider: "aiand", expected: "aiand.md"},
            {tag: "azureopenai", provider: "azureopenai", expected: "providers.md#azure-openai"},
            {tag: "clawrouter", provider: "clawrouter", expected: "clawrouter.md"},
            {tag: "coderabbit", provider: "coderabbit", expected: "coderabbit.md"},
            {tag: "copilot", provider: "copilot", expected: "copilot.md"},
            {tag: "crossmodel", provider: "crossmodel", expected: "crossmodel.md"},
            {tag: "deepinfra", provider: "deepinfra", expected: "deepinfra.md"},
            {tag: "fireworks", provider: "fireworks", expected: "fireworks.md"},
            {tag: "huggingface", provider: "huggingface", expected: "huggingface.md"},
            {tag: "ibmbob", provider: "ibmbob", expected: "ibm-bob.md"},
            {tag: "mistral", provider: "mistral", expected: "providers.md#mistral"},
            {tag: "muse", provider: "muse", expected: "muse.md"},
            {tag: "neuralwatt", provider: "neuralwatt", expected: "neuralwatt.md"},
            {tag: "nous", provider: "nous", expected: "nous.md"},
            {tag: "notion", provider: "notion", expected: "notion.md"},
            {tag: "openai", provider: "openai", expected: "openai.md"},
            {tag: "openrouter", provider: "openrouter", expected: "openrouter.md"},
            {tag: "perplexity", provider: "perplexity", expected: "providers.md#perplexity"},
            {tag: "poe", provider: "poe", expected: "poe.md"},
            {tag: "qoder", provider: "qoder", expected: "qoder.md"},
            {tag: "qwencloud", provider: "qwencloud", expected: "qwen-cloud.md"},
            {tag: "replicate", provider: "replicate", expected: "replicate.md"},
            {tag: "sakana", provider: "sakana", expected: "sakana.md"},
            {tag: "stepfun", provider: "stepfun", expected: "stepfun.md"},
            {tag: "sub2api", provider: "sub2api", expected: "sub2api.md"},
            {tag: "synthetic", provider: "synthetic", expected: "providers.md#synthetic"},
            {tag: "t3chat", provider: "t3chat", expected: "providers.md#t3-chat"},
            {tag: "venice", provider: "venice", expected: "venice.md"},
            {tag: "wayfinder", provider: "wayfinder", expected: "wayfinder.md"},
            {tag: "xai", provider: "xai", expected: "xai.md"},
            {tag: "zed", provider: "zed", expected: "zed.md"},
            {tag: "zenmux", provider: "zenmux", expected: "zenmux.md"},
            {tag: "zoommate", provider: "zoommate", expected: "zoommate.md"}
        ];
    }
    function test_docs(data) {
        compare(ProviderIdentity.providerDocsUrl(data.provider),
            "https://github.com/steipete/CodexBar/blob/main/docs/" + data.expected);
    }

    function test_aliases_data() {
        return [
            {tag: "11labs", provider: "11labs", expected: "elevenlabs"},
            {tag: "abacus-ai", provider: "abacus-ai", expected: "abacus"},
            {tag: "ai&", provider: "ai&", expected: "aiand"},
            {tag: "ai-and", provider: "ai-and", expected: "aiand"},
            {tag: "alibaba-token", provider: "alibaba-token", expected: "alibabatokenplan"},
            {tag: "aoai", provider: "aoai", expected: "azureopenai"},
            {tag: "azure-openai", provider: "azure-openai", expected: "azureopenai"},
            {tag: "bailian", provider: "bailian", expected: "alibaba"},
            {tag: "bailian-token-plan", provider: "bailian-token-plan", expected: "alibabatokenplan"},
            {tag: "bob", provider: "bob", expected: "ibmbob"},
            {tag: "bobshell", provider: "bobshell", expected: "ibmbob"},
            {tag: "chutes.ai", provider: "chutes.ai", expected: "chutes"},
            {tag: "claw-router", provider: "claw-router", expected: "clawrouter"},
            {tag: "cm", provider: "cm", expected: "crossmodel"},
            {tag: "command-code", provider: "command-code", expected: "commandcode"},
            {tag: "deep-infra", provider: "deep-infra", expected: "deepinfra"},
            {tag: "deep-seek", provider: "deep-seek", expected: "deepseek"},
            {tag: "fw", provider: "fw", expected: "fireworks"},
            {tag: "gk", provider: "gk", expected: "gitkraken"},
            {tag: "groq-api", provider: "groq-api", expected: "groq"},
            {tag: "hermes", provider: "hermes", expected: "nous"},
            {tag: "hf", provider: "hf", expected: "huggingface"},
            {tag: "ibm-bob", provider: "ibm-bob", expected: "ibmbob"},
            {tag: "muse-code", provider: "muse-code", expected: "muse"},
            {tag: "nous-portal", provider: "nous-portal", expected: "nous"},
            {tag: "notion-ai", provider: "notion-ai", expected: "notion"},
            {tag: "openai-api", provider: "openai-api", expected: "openai"},
            {tag: "qwen-cloud", provider: "qwen-cloud", expected: "qwencloud"},
            {tag: "r8", provider: "r8", expected: "replicate"},
            {tag: "step-fun", provider: "step-fun", expected: "stepfun"},
            {tag: "sub-2-api", provider: "sub-2-api", expected: "sub2api"},
            {tag: "synthetic.new", provider: "synthetic.new", expected: "synthetic"},
            {tag: "t3-chat", provider: "t3-chat", expected: "t3chat"},
            {tag: "warp-terminal", provider: "warp-terminal", expected: "warp"},
            {tag: "wayfinder-router", provider: "wayfinder-router", expected: "wayfinder"},
            {tag: "xiaomi-mimo", provider: "xiaomi-mimo", expected: "mimo"},
            {tag: "z.ai", provider: "z.ai", expected: "zai"},
            {tag: "zen-mux", provider: "zen-mux", expected: "zenmux"}
        ];
    }
    function test_aliases(data) {
        compare(ProviderIdentity.resolveProviderKey(data.provider), data.expected);
    }

    function test_brandColors_data() {
        return [
            {tag: "aiand", provider: "aiand", expected: [226 / 255, 92 / 255, 43 / 255]},
            {tag: "aixy", provider: "aixy", expected: [18 / 255, 54 / 255, 80 / 255]},
            {tag: "atlascloud", provider: "atlascloud", expected: [89 / 255, 117 / 255, 245 / 255]},
            {tag: "bifrost", provider: "bifrost", expected: [51 / 255, 192 / 255, 158 / 255]},
            {tag: "clawrouter", provider: "clawrouter", expected: [89 / 255, 110 / 255, 246 / 255]},
            {tag: "coderabbit", provider: "coderabbit", expected: [1, 92 / 255, 53 / 255]},
            {tag: "crossmodel", provider: "crossmodel", expected: [124 / 255, 58 / 255, 237 / 255]},
            {tag: "commandcode", provider: "commandcode", expected: [160 / 255, 77 / 255, 253 / 255]},
            {tag: "devpass", provider: "devpass", expected: [37 / 255, 99 / 255, 235 / 255]},
            {tag: "fireworks", provider: "fireworks", expected: [242 / 255, 91 / 255, 28 / 255]},
            {tag: "gitkraken", provider: "gitkraken", expected: [23 / 255, 146 / 255, 135 / 255]},
            {tag: "huggingface", provider: "huggingface", expected: [1, 210 / 255, 30 / 255]},
            {tag: "hyper", provider: "hyper", expected: [1, 96 / 255, 1]},
            {tag: "ibmbob", provider: "ibmbob", expected: [14 / 255, 97 / 255, 250 / 255]},
            {tag: "lithosai", provider: "lithosai", expected: [107 / 255, 114 / 255, 128 / 255]},
            {tag: "llmman", provider: "llmman", expected: [108 / 255, 197 / 255, 176 / 255]},
            {tag: "muse", provider: "muse", expected: [6 / 255, 104 / 255, 225 / 255]},
            {tag: "museai", provider: "museai", expected: [6 / 255, 104 / 255, 225 / 255]},
            {tag: "nous", provider: "nous", expected: [214 / 255, 165 / 255, 92 / 255]},
            {tag: "poe", provider: "poe", expected: [93 / 255, 92 / 255, 222 / 255]},
            {tag: "qoder", provider: "qoder", expected: [16 / 255, 185 / 255, 129 / 255]},
            {tag: "raycast", provider: "raycast", expected: [1, 99 / 255, 99 / 255]},
            {tag: "replicate", provider: "replicate", expected: [0, 0, 0]},
            {tag: "workbuddy", provider: "workbuddy", expected: [13 / 255, 200 / 255, 166 / 255]},
            {tag: "xkiro", provider: "xkiro", expected: [82 / 255, 201 / 255, 155 / 255]}
        ];
    }
    function test_brandColors(data) {
        compare(ProviderIdentity.providerBrandColorChannels(data.provider), data.expected);
    }

    function test_dashboards_data() {
        return [
            {tag: "aiand", provider: "aiand", expected: "https://console.aiand.com"},
            {tag: "aixy", provider: "aixy", expected: "https://dash.aixy-gateway.com"},
            {tag: "amp", provider: "amp", expected: "https://ampcode.com/settings/usage"},
            {tag: "atlascloud", provider: "atlascloud", expected: "https://www.atlascloud.ai/console"},
            {tag: "clawrouter", provider: "clawrouter", expected: "https://clawrouter.openclaw.ai/dashboard/access"},
            {tag: "claude", provider: "claude", expected: "https://console.anthropic.com/settings/billing"},
            {tag: "clinepass", provider: "clinepass", expected: "https://app.cline.bot/dashboard/subscription?personal=true"},
            {tag: "coderabbit", provider: "coderabbit", expected: "https://app.coderabbit.ai"},
            {tag: "crof", provider: "crof", expected: "https://crof.ai/dashboard"},
            {tag: "crossmodel", provider: "crossmodel", expected: "https://crossmodel.ai/console/usage"},
            {tag: "deepinfra", provider: "deepinfra", expected: "https://deepinfra.com/dash"},
            {tag: "devpass", provider: "devpass", expected: "https://devpass.llmgateway.io/dashboard"},
            {tag: "fireworks", provider: "fireworks", expected: "https://app.fireworks.ai"},
            {tag: "gitkraken", provider: "gitkraken", expected: "https://gitkraken.dev/account#ai-usage"},
            {tag: "groq", provider: "groq", expected: "https://console.groq.com/dashboard/usage"},
            {tag: "helmcode", provider: "helmcode", expected: "https://cloud.helmcode.com/dashboard"},
            {tag: "huggingface", provider: "huggingface", expected: "https://huggingface.co/settings/billing"},
            {tag: "hyper", provider: "hyper", expected: "https://hyper.charm.land"},
            {tag: "ibmbob", provider: "ibmbob", expected: "https://bob.ibm.com"},
            {tag: "llmman", provider: "llmman", expected: "http://127.0.0.1:17434"},
            {tag: "lithosai", provider: "lithosai", expected: "https://console.lithosai.cloud"},
            {tag: "muse", provider: "muse", expected: "https://dev.meta.ai"},
            {tag: "museai", provider: "museai", expected: "https://muse.ai/?settings_tab=general"},
            {tag: "nous", provider: "nous", expected: "https://portal.nousresearch.com/usage"},
            {tag: "wayfinder", provider: "wayfinder", expected: "http://127.0.0.1:8088/router"},
            {tag: "notion", provider: "notion", expected: "https://app.notion.com/"},
            {tag: "qoder", provider: "qoder", expected: "https://qoder.com/account/usage"},
            {tag: "raycast", provider: "raycast", expected: "https://www.raycast.com/settings"},
            {tag: "replicate", provider: "replicate", expected: "https://replicate.com/account/billing"},
            {tag: "sakana", provider: "sakana", expected: "https://console.sakana.ai/billing"},
            {tag: "typesafe", provider: "typesafe", expected: "https://console.typesafe.ai/settings/billing"},
            {tag: "v0", provider: "v0", expected: "https://v0.app/settings/billing"},
            {tag: "vercel", provider: "vercel", expected: "https://vercel.com/d?to=%2F%5Bteam%5D%2F%7E%2Fai-gateway"},
            {tag: "workbuddy", provider: "workbuddy", expected: "https://www.workbuddy.cn/profile/plans-usage"},
            {tag: "xai", provider: "xai", expected: "https://console.x.ai"},
            {tag: "xkiro", provider: "xkiro", expected: "https://xkiro.com"}
        ];
    }
    function test_dashboards(data) {
        compare(ProviderIdentity.providerDashboardUrl(data.provider), data.expected);
    }

    function test_loginUrls_data() {
        return [
            {tag: "opencode", provider: "opencode", expected: "https://opencode.ai/auth"},
            {tag: "opencodego", provider: "opencodego", expected: "https://opencode.ai/auth"},
            {tag: "v0", provider: "v0", expected: "https://v0.app/settings/keys"}
        ];
    }
    function test_loginUrls(data) {
        compare(ProviderIdentity.providerLoginUrl(data.provider), data.expected);
    }

    function test_statusUrls_data() {
        return [
            {tag: "augment", provider: "augment", expected: "https://status.augmentcode.com"},
            {tag: "coderabbit", provider: "coderabbit", expected: "https://status.coderabbit.ai"},
            {tag: "huggingface", provider: "huggingface", expected: "https://status.huggingface.co"},
            {tag: "ibmbob", provider: "ibmbob", expected: "https://status.bob.ibm.com"},
            {tag: "mistral", provider: "mistral", expected: "https://status.mistral.ai"}
        ];
    }
    function test_statusUrls(data) {
        compare(ProviderIdentity.providerStatusUrl(data.provider), data.expected);
    }

    function test_cliArguments_data() {
        var overrides = [
            {provider: "abacus", alias: "abacus-ai", expected: "abacusai"},
            {provider: "alibaba", alias: "bailian", expected: "alibaba-coding-plan"},
            {provider: "alibabatokenplan", alias: "bailian-token-plan", expected: "alibaba-token-plan"},
            {provider: "azureopenai", alias: "aoai", expected: "azure-openai"},
            {provider: "groq", alias: "groq-api", expected: "groqcloud"},
            {provider: "qwencloud", alias: "qwen", expected: "qwen-cloud"}
        ];
        var cases = [];
        for (var row of overrides) {
            for (var input of [row.provider, row.alias, row.provider.toUpperCase()]) {
                cases.push({tag: input, provider: input, expected: row.expected});
            }
        }
        return cases;
    }
    function test_cliArguments(data) {
        compare(ProviderIdentity.providerCliArgument(data.provider), data.expected);
    }

    function test_requiredBrandColors_data() {
        // Retain the existing official and compatibility color-presence set.
        var providers = [
            "codex", "openai", "azureopenai", "claude", "clinepass", "cursor", "opencode",
            "opencodego", "alibaba", "alibabatokenplan", "qwencloud", "factory", "fireworks", "gemini",
            "antigravity", "copilot", "devin", "zai", "minimax", "manus", "kimi",
            "kilo", "kiro", "vertexai", "augment", "jetbrains", "kimik2", "crossmodel",
            "moonshot", "amp", "t3chat", "ollama", "synthetic", "warp", "openrouter",
            "elevenlabs", "windsurf", "zed", "perplexity", "mimo", "doubao", "abacus",
            "mistral", "deepseek", "codebuff", "crof", "venice", "commandcode", "qoder",
            "stepfun", "bedrock", "grok", "groq", "llmproxy", "litellm", "deepgram",
            "poe", "chutes", "clawrouter", "sakana", "deepinfra", "neuralwatt", "longcat",
            "sub2api", "zenmux", "aiand", "zoommate", "wayfinder", "xai", "notion",
            "ibmbob"
        ];
        return providers.map(function(provider) {
            return {tag: provider, provider: provider};
        });
    }
    function test_requiredBrandColors(data) {
        var channels = ProviderIdentity.providerBrandColorChannels(data.provider);
        verify(Array.isArray(channels));
        compare(channels.length, 3);
        for (var channel of channels) {
            compare(typeof channel, "number");
            verify(isFinite(channel));
            verify(channel >= 0 && channel <= 1);
        }
    }
}
