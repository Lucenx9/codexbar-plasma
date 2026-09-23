import QtQuick

// The one localization table for AI Insights helper failures, shared by the
// popup card and the settings page. The helper returns only these reason codes.
QtObject {
    function providerName(provider) {
        return provider === "openrouter" ? "OpenRouter" : (provider === "openai" ? "OpenAI" : "Ollama")
    }

    function errorText(reason, provider) {
        var name = providerName(provider)
        switch (reason) {
        case "missing_key": return i18n("Set an API key in the AI Insights settings.")
        case "secret_unavailable": return i18n("The system wallet is unavailable. Unlock KWallet or check its Secret Service support.")
        case "auth": return i18n("%1 rejected the API key. Update it in the AI Insights settings.", name)
        case "credits": return i18n("The %1 account has insufficient credits or quota.", name)
        case "forbidden": return i18n("%1 refused access to this model.", name)
        case "rate_limited": return i18n("%1 is limiting requests. Try again later.", name)
        case "model": return i18n("The selected model is unavailable, or no endpoint meets the privacy settings.")
        case "request": return i18n("The model rejected the request. It may not support structured output.")
        case "routing": return i18n("No OpenRouter endpoint meets the model and privacy requirements right now.")
        case "timeout": return i18n("The request timed out.")
        case "network": return provider === "ollama" ? i18n("Could not reach Ollama. Check that it is running.")
            : i18n("Could not reach %1.", name)
        case "refused": return i18n("The model declined to answer.")
        case "truncated": return i18n("The answer was cut off. Try another model.")
        case "format": return i18n("The model returned an answer in an unexpected format.")
        case "endpoint": return i18n("Use an https:// Ollama address, or http:// only for this computer.")
        case "invalid_input": return i18n("Check the AI Insights model settings.")
        default: return i18n("%1 is temporarily unavailable.", name)
        }
    }
}
