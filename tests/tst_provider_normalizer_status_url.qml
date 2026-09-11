import QtQuick
import QtTest
import "../contents/ui/ProviderNormalizer.js" as Normalizer

TestCase {
    name: "ProviderNormalizerStatusUrl"

    function test_malformedStatusUrlFallsBackWithoutThrowing() {
        var fallback = "https://status.openai.com/"
        var url = JSON.parse('{"toString":null}')
        compare(Normalizer.safeStatusUrl(fallback, url), fallback)
    }
}
