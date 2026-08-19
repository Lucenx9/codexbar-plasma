.pragma library
.import "Guards.js" as Guards

var maximumProviderIDLength = 128

function hasOwnKey(item, key) {
    return Guards.hasOwnKey(item, key)
}

function providerKey(value, aliases) {
    var key = String(value || "codex").toLowerCase()
    if (hasOwnKey(aliases, key) && typeof aliases[key] === "string") {
        return aliases[key]
    }
    return key
}

function providerMapKey(value) {
    var key = String(value || "")
    if (key.length === 0 || key.length > maximumProviderIDLength) {
        return ""
    }
    if (key === "prototype" || Object.prototype.hasOwnProperty.call(Object.prototype, key)) {
        return ""
    }
    if (/[\u0000-\u001f\u007f]/.test(key)) {
        return ""
    }
    return key
}

// Provider identity tables shared by the popup and the provider-config page.
//
// Both surfaces render the same provider metadata, so these tables used to exist
// as two copies that only a drift test kept in sync; adding a provider meant
// editing two files and trusting that test to catch a miss. They live here once.
//
// Everything here must stay free of QML context: no `i18n`, `Qt` or `Kirigami`.
// That is why the brand colours are plain channel triples rather than colours,
// and why the icon and documentation lookups return a bare name or path that the
// QML caller resolves. The one provider table that cannot move is the display
// name map, because `i18n` needs literal strings in a file gettext scans.

var documentationBaseUrl = "https://github.com/steipete/CodexBar/blob/main/docs/"

// CLI aliases and historical spellings, mapped to the canonical provider key.
var providerAliases = {
    "11labs": "elevenlabs",
    "abacus-ai": "abacus",
    "abacusai": "abacus",
    "agy": "antigravity",
    "ai&": "aiand",
    "ai-and": "aiand",
    "alibaba-coding-plan": "alibaba",
    "alibaba-token": "alibabatokenplan",
    "alibaba-token-plan": "alibabatokenplan",
    "aoai": "azureopenai",
    "ark": "doubao",
    "aws-bedrock": "bedrock",
    "azure-openai": "azureopenai",
    "bailian": "alibaba",
    "bailian-token-plan": "alibabatokenplan",
    "bob": "ibmbob",
    "bobshell": "ibmbob",
    "bytedance": "doubao",
    "chutes.ai": "chutes",
    "claw-router": "clawrouter",
    "cm": "crossmodel",
    "command-code": "commandcode",
    "crofai": "crof",
    "deep-infra": "deepinfra",
    "deep-seek": "deepseek",
    "dg": "deepgram",
    "di": "deepinfra",
    "droid": "factory",
    "ds": "deepseek",
    "eleven": "elevenlabs",
    "fw": "fireworks",
    "gemini-cli": "gemini",
    "groq-api": "groq",
    "groqcloud": "groq",
    "ibm-bob": "ibmbob",
    "kilo-ai": "kilo",
    "kimi-ai": "kimi",
    "kimi-k2": "kimik2",
    "kiro-cli": "kiro",
    "lc": "longcat",
    "litellm-proxy": "litellm",
    "llm-api-key-proxy": "llmproxy",
    "llm-proxy": "llmproxy",
    "long-cat": "longcat",
    "manicode": "codebuff",
    "mini-max": "minimax",
    "mistral-ai": "mistral",
    "neural": "neuralwatt",
    "notion-ai": "notion",
    "notionai": "notion",
    "nw": "neuralwatt",
    "openai-api": "openai",
    "or": "openrouter",
    "qwen": "qwencloud",
    "qwen-cloud": "qwencloud",
    "qwen-token-plan": "qwencloud",
    "sakana-ai": "sakana",
    "sf": "stepfun",
    "step-fun": "stepfun",
    "sub-2-api": "sub2api",
    "synthetic.new": "synthetic",
    "t3": "t3chat",
    "t3-chat": "t3chat",
    "ven": "venice",
    "vertex": "vertexai",
    "volcengine": "doubao",
    "warp-ai": "warp",
    "warp-terminal": "warp",
    "wayfinder-router": "wayfinder",
    "xiaomi-mimo": "mimo",
    "z.ai": "zai",
    "zen-mux": "zenmux"
}

// Only providers whose CLI argument differs from their canonical key.
var providerCliArguments = {
    "abacus": "abacusai",
    "alibaba": "alibaba-coding-plan",
    "alibabatokenplan": "alibaba-token-plan",
    "azureopenai": "azure-openai",
    "groq": "groqcloud",
    "qwencloud": "qwen-cloud"
}

// Brand colours as red/green/blue channels in 0..1. Providers with no entry fall
// back to the theme highlight, which is the caller's decision to make.
var providerBrandChannels = {
    "abacus": [56 / 255, 189 / 255, 248 / 255],
    "aiand": [226 / 255, 92 / 255, 43 / 255],
    "alibaba": [1, 106 / 255, 0],
    "alibabatokenplan": [1, 106 / 255, 0],
    "amp": [220 / 255, 38 / 255, 38 / 255],
    "antigravity": [96 / 255, 186 / 255, 126 / 255],
    "augment": [99 / 255, 102 / 255, 241 / 255],
    "azureopenai": [0, 120 / 255, 212 / 255],
    "bedrock": [1, 0.6, 0],
    "chutes": [49 / 255, 132 / 255, 1],
    "claude": [204 / 255, 124 / 255, 94 / 255],
    "clawrouter": [89 / 255, 110 / 255, 246 / 255],
    "clinepass": [0.38, 0.64, 0.98],
    "codebuff": [68 / 255, 1, 0],
    "codex": [73 / 255, 163 / 255, 176 / 255],
    "commandcode": [160 / 255, 77 / 255, 253 / 255],
    "copilot": [168 / 255, 85 / 255, 247 / 255],
    "crof": [0.18, 0.67, 0.58],
    "crossmodel": [124 / 255, 58 / 255, 237 / 255],
    "cursor": [0, 191 / 255, 165 / 255],
    "deepgram": [100 / 255, 103 / 255, 242 / 255],
    "deepinfra": [42 / 255, 50 / 255, 117 / 255],
    "deepseek": [0.32, 0.49, 0.94],
    "devin": [70 / 255, 180 / 255, 130 / 255],
    "doubao": [51 / 255, 112 / 255, 1],
    "elevenlabs": [0.92, 0.92, 0.90],
    "factory": [1, 107 / 255, 53 / 255],
    "fireworks": [242 / 255, 91 / 255, 28 / 255],
    "gemini": [171 / 255, 135 / 255, 234 / 255],
    "grok": [16 / 255, 163 / 255, 127 / 255],
    "groq": [245 / 255, 104 / 255, 68 / 255],
    "ibmbob": [14 / 255, 97 / 255, 250 / 255],
    "jetbrains": [1, 51 / 255, 153 / 255],
    "kilo": [242 / 255, 112 / 255, 39 / 255],
    "kimi": [254 / 255, 96 / 255, 60 / 255],
    "kimik2": [76 / 255, 0, 1],
    "kiro": [1, 153 / 255, 0],
    "litellm": [76 / 255, 137 / 255, 240 / 255],
    "llmproxy": [36 / 255, 180 / 255, 126 / 255],
    "longcat": [1, 209 / 255, 0],
    "manus": [52 / 255, 50 / 255, 45 / 255],
    "mimo": [1, 105 / 255, 0],
    "minimax": [254 / 255, 96 / 255, 60 / 255],
    "mistral": [1, 80 / 255, 15 / 255],
    "moonshot": [32 / 255, 93 / 255, 235 / 255],
    "neuralwatt": [0.22, 0.85, 0.55],
    "notion": [51 / 255, 126 / 255, 169 / 255],
    "ollama": [136 / 255, 136 / 255, 136 / 255],
    "openai": [0.06, 0.51, 0.43],
    "opencode": [59 / 255, 130 / 255, 246 / 255],
    "opencodego": [59 / 255, 130 / 255, 246 / 255],
    "openrouter": [100 / 255, 103 / 255, 242 / 255],
    "perplexity": [32 / 255, 178 / 255, 170 / 255],
    "poe": [93 / 255, 92 / 255, 222 / 255],
    "qoder": [16 / 255, 185 / 255, 129 / 255],
    "qwencloud": [97 / 255, 92 / 255, 237 / 255],
    "sakana": [0.16, 0.46, 0.86],
    "stepfun": [0.13, 0.59, 0.95],
    "sub2api": [45 / 255, 198 / 255, 216 / 255],
    "synthetic": [20 / 255, 20 / 255, 20 / 255],
    "t3chat": [245 / 255, 102 / 255, 71 / 255],
    "venice": [0.2, 0.6, 1],
    "vertexai": [66 / 255, 133 / 255, 244 / 255],
    "warp": [147 / 255, 139 / 255, 180 / 255],
    "wayfinder": [16 / 255, 163 / 255, 127 / 255],
    "windsurf": [52 / 255, 232 / 255, 187 / 255],
    "xai": [142 / 255, 142 / 255, 147 / 255],
    "zai": [232 / 255, 90 / 255, 106 / 255],
    "zed": [8 / 255, 78 / 255, 1],
    "zenmux": [108 / 255, 92 / 255, 231 / 255],
    "zoommate": [11 / 255, 92 / 255, 1]
}

var providerDashboardUrls = {
    "abacus": "https://apps.abacus.ai/chatllm/admin/compute-points-usage",
    "aiand": "https://console.aiand.com",
    "alibaba": "https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=coding-plan#/efm/coding_plan",
    "alibabatokenplan": "https://bailian.console.aliyun.com/cn-beijing?tab=plan#/efm/subscription/token-plan",
    "amp": "https://ampcode.com/settings/usage",
    "augment": "https://app.augmentcode.com/account/subscription",
    "azureopenai": "https://ai.azure.com",
    "bedrock": "https://console.aws.amazon.com/bedrock",
    "chutes": "https://chutes.ai",
    "claude": "https://console.anthropic.com/settings/billing",
    "clawrouter": "https://clawrouter.openclaw.ai/dashboard/access",
    "clinepass": "https://app.cline.bot/dashboard/subscription?personal=true",
    "codebuff": "https://www.codebuff.com/usage",
    "codex": "https://chatgpt.com/codex/settings/usage",
    "commandcode": "https://commandcode.ai/studio",
    "copilot": "https://github.com/settings/copilot",
    "crof": "https://crof.ai/dashboard",
    "crossmodel": "https://crossmodel.ai/console/usage",
    "cursor": "https://cursor.com/dashboard?tab=usage",
    "deepgram": "https://console.deepgram.com/project/",
    "deepinfra": "https://deepinfra.com/dash",
    "deepseek": "https://platform.deepseek.com/usage",
    "devin": "https://app.devin.ai",
    "doubao": "https://console.volcengine.com/ark/region:ark+cn-beijing/openManagement?LLM=%7B%7D&advancedActiveKey=subscribe",
    "elevenlabs": "https://elevenlabs.io/app/developers/usage",
    "factory": "https://app.factory.ai/settings/billing",
    "fireworks": "https://app.fireworks.ai",
    "gemini": "https://gemini.google.com",
    "grok": "https://grok.com/?_s=usage",
    "groq": "https://console.groq.com/dashboard/usage",
    "ibmbob": "https://bob.ibm.com",
    "kilo": "https://app.kilo.ai/usage",
    "kimi": "https://www.kimi.com/code/console",
    "kiro": "https://app.kiro.dev/account/usage",
    "longcat": "https://longcat.chat/platform/",
    "manus": "https://manus.im",
    "mimo": "https://platform.xiaomimimo.com/#/console/balance",
    "minimax": "https://platform.minimax.io/user-center/payment/coding-plan?cycle_type=3",
    "mistral": "https://admin.mistral.ai/organization/usage",
    "moonshot": "https://platform.moonshot.ai/console/account",
    "neuralwatt": "https://portal.neuralwatt.com/dashboard",
    "notion": "https://app.notion.com/",
    "ollama": "https://ollama.com/settings",
    "openai": "https://platform.openai.com/usage",
    "opencode": "https://opencode.ai/auth",
    "opencodego": "https://opencode.ai/auth",
    "openrouter": "https://openrouter.ai/settings/credits",
    "perplexity": "https://www.perplexity.ai/account/usage",
    "poe": "https://poe.com/api/keys",
    "qoder": "https://qoder.com/account/usage",
    "qwencloud": "https://home.qwencloud.com/billing/subscription/token-plan-individual",
    "sakana": "https://console.sakana.ai/billing",
    "stepfun": "https://platform.stepfun.com/plan-usage",
    "t3chat": "https://t3.chat/settings/customization",
    "venice": "https://venice.ai/settings/api",
    "vertexai": "https://console.cloud.google.com/vertex-ai",
    "warp": "https://docs.warp.dev/reference/cli/api-keys",
    "wayfinder": "http://127.0.0.1:8088/router",
    "windsurf": "https://windsurf.com/subscription/usage",
    "xai": "https://console.x.ai",
    "zai": "https://z.ai/manage-apikey/coding-plan/personal/my-plan",
    "zenmux": "https://zenmux.ai/platform/management",
    "zoommate": "https://zoommate.zoom.us/#/?settings=credit-usage"
}

var providerLoginUrls = {
    "claude": "https://claude.ai",
    "codex": "https://chatgpt.com",
    "copilot": "https://github.com/login",
    "cursor": "https://cursor.com/settings",
    "devin": "https://app.devin.ai/settings/usage",
    "factory": "https://app.factory.ai",
    "gemini": "https://aistudio.google.com",
    "manus": "https://manus.im",
    "mimo": "https://platform.xiaomimimo.com/api/v1/genLoginUrl?currentPath=%2F%23%2Fconsole%2Fbalance",
    "openai": "https://chatgpt.com",
    "opencode": "https://opencode.ai/auth",
    "opencodego": "https://opencode.ai/auth",
    "perplexity": "https://www.perplexity.ai"
}

var providerStatusUrls = {
    "alibaba": "https://status.aliyun.com",
    "alibabatokenplan": "https://status.aliyun.com",
    "antigravity": "https://www.google.com/appsstatus/dashboard/products/npdyhgECDJ6tB66MxXyo/history",
    "augment": "https://status.augmentcode.com",
    "azureopenai": "https://azure.status.microsoft/en-us/status",
    "bedrock": "https://health.aws.amazon.com/health/status",
    "claude": "https://status.claude.com/",
    "codex": "https://status.openai.com/",
    "copilot": "https://www.githubstatus.com/",
    "cursor": "https://status.cursor.com",
    "deepgram": "https://status.deepgram.com",
    "deepinfra": "https://status.deepinfra.com",
    "deepseek": "https://status.deepseek.com",
    "elevenlabs": "https://status.elevenlabs.io",
    "factory": "https://status.factory.ai",
    "gemini": "https://www.google.com/appsstatus/dashboard/products/npdyhgECDJ6tB66MxXyo/history",
    "grok": "https://status.x.ai",
    "groq": "https://status.groq.com",
    "ibmbob": "https://status.bob.ibm.com",
    "kiro": "https://health.aws.amazon.com/health/status",
    "mistral": "https://status.mistral.ai",
    "notion": "https://status.notion.so/",
    "openai": "https://status.openai.com/",
    "openrouter": "https://status.openrouter.ai/",
    "perplexity": "https://status.perplexity.com/",
    "qwencloud": "https://status.alibabacloud.com",
    "vertexai": "https://status.cloud.google.com",
    "xai": "https://status.x.ai",
    "zoommate": "https://www.zoomstatus.com/"
}

// Paths under `documentationBaseUrl`.
var providerDocsPaths = {
    "abacus": "abacus.md",
    "aiand": "aiand.md",
    "alibaba": "alibaba-coding-plan.md",
    "alibabatokenplan": "alibaba-token-plan.md",
    "amp": "amp.md",
    "antigravity": "antigravity.md",
    "augment": "augment.md",
    "azureopenai": "providers.md#azure-openai",
    "bedrock": "bedrock.md",
    "chutes": "chutes.md",
    "claude": "claude.md",
    "clawrouter": "clawrouter.md",
    "codebuff": "codebuff.md",
    "codex": "codex.md",
    "commandcode": "command-code.md",
    "copilot": "copilot.md",
    "crof": "crof.md",
    "crossmodel": "crossmodel.md",
    "cursor": "cursor.md",
    "deepgram": "deepgram.md",
    "deepinfra": "deepinfra.md",
    "deepseek": "deepseek.md",
    "devin": "devin.md",
    "doubao": "doubao.md",
    "elevenlabs": "elevenlabs.md",
    "factory": "factory.md",
    "fireworks": "fireworks.md",
    "gemini": "gemini.md",
    "grok": "grok.md",
    "groq": "groqcloud.md",
    "ibmbob": "ibm-bob.md",
    "jetbrains": "jetbrains.md",
    "kilo": "kilo.md",
    "kimi": "kimi.md",
    "kimik2": "kimi-k2.md",
    "kiro": "kiro.md",
    "litellm": "litellm.md",
    "llmproxy": "llm-proxy.md",
    "manus": "manus.md",
    "mimo": "mimo.md",
    "minimax": "minimax.md",
    "mistral": "providers.md#mistral",
    "moonshot": "moonshot.md",
    "neuralwatt": "neuralwatt.md",
    "notion": "notion.md",
    "ollama": "ollama.md",
    "openai": "openai.md",
    "opencode": "opencode.md",
    "opencodego": "opencode.md",
    "openrouter": "openrouter.md",
    "perplexity": "providers.md#perplexity",
    "poe": "poe.md",
    "qoder": "qoder.md",
    "qwencloud": "qwen-cloud.md",
    "sakana": "sakana.md",
    "stepfun": "stepfun.md",
    "sub2api": "sub2api.md",
    "synthetic": "providers.md#synthetic",
    "t3chat": "providers.md#t3-chat",
    "venice": "venice.md",
    "vertexai": "vertexai.md",
    "warp": "warp.md",
    "wayfinder": "wayfinder.md",
    "windsurf": "windsurf.md",
    "xai": "xai.md",
    "zai": "zai.md",
    "zed": "zed.md",
    "zenmux": "zenmux.md",
    "zoommate": "zoommate.md"
}

// Keyed by the resolved provider key, so CLI aliases are already normalized
// before this lookup. Only providers whose icon file name differs from their key.
var providerIconFiles = {
    "gemini": "gemini-white.png"
}

function resolveProviderKey(value) {
    return providerKey(value, providerAliases)
}

function providerTableValue(table, value) {
    var key = resolveProviderKey(value)
    return hasOwnKey(table, key) ? table[key] : ""
}

function providerCliArgument(value) {
    var key = resolveProviderKey(value)
    return hasOwnKey(providerCliArguments, key) ? providerCliArguments[key] : key
}

// [] when the provider has no brand colour, so the caller supplies the fallback.
function providerBrandColorChannels(value) {
    var key = resolveProviderKey(value)
    return hasOwnKey(providerBrandChannels, key) ? providerBrandChannels[key] : []
}

function providerDashboardUrl(value) {
    return providerTableValue(providerDashboardUrls, value)
}

function providerLoginUrl(value) {
    return providerTableValue(providerLoginUrls, value)
}

function providerStatusUrl(value) {
    return providerTableValue(providerStatusUrls, value)
}

function providerDocsUrl(value) {
    var path = providerTableValue(providerDocsPaths, value)
    return path.length > 0 ? documentationBaseUrl + path : ""
}

// "" when the key cannot name a bundled asset, so the caller falls back to a
// generic icon rather than resolving an attacker-influenced path.
function providerIconFileName(value) {
    var key = providerMapKey(resolveProviderKey(value))
    if (!/^[a-z0-9][a-z0-9._-]*$/.test(key) || key.indexOf("..") !== -1) {
        return ""
    }
    var fileName = providerKey(key, providerIconFiles)
    return fileName.indexOf(".") === -1 ? fileName + ".svg" : fileName
}
