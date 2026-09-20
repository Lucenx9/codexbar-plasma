import QtQuick
import QtTest
import "../contents/ui/CliUpdate.js" as CliUpdate

TestCase {
    name: "CliUpdate"
    function test_boundedResults() {
        var result = CliUpdate.response(JSON.stringify({status: "available", version: "0.60.4",
            path: "/usr/bin/codexbar", manager: "pacman", latest: "0.62.0", tag: "v0.62.0"}))
        compare(result.manager, "pacman")
        compare(result.releaseUrl, "https://github.com/steipete/CodexBar/releases/tag/v0.62.0")
        compare(CliUpdate.response("x".repeat(20000)).status, "error")
        compare(CliUpdate.response("null").status, "error")
        compare(CliUpdate.response('{"status":"available","tag":"https://evil.test"}').status, "error")
        compare(CliUpdate.response('{"status":"local","version":{}}').status, "error")
        compare(CliUpdate.response('{"status":"unknown","manager":"<b>pacman</b>","path":"/tmp/\\nsecret"}').path, "")
        compare(CliUpdate.response('{"status":"unknown","manager":"<b>pacman</b>"}').manager, "external")
    }
    function test_pathsRemainBoundedAndRedacted() {
        var secret = "sk-abcdefghijklmnop"
        var value = {status: "local", version: "0.61.0", path: "/opt/token=" + secret + "/codexbar"}
        verify(CliUpdate.response(JSON.stringify(value)).path.indexOf(secret) < 0)
        value.path = "/opt/" + "x".repeat(2000)
        verify(CliUpdate.response(JSON.stringify(value)).path.length <= 1024)
        value.path = "/opt/CodexBar CLI/bin/codexbar"
        compare(CliUpdate.response(JSON.stringify(value)).path, value.path)
    }
    function test_commands() {
        compare(CliUpdate.command("file:///tmp/helper.py", " \t ", false), "")
        var command = CliUpdate.command("file:///tmp/check%20it.py", "/tmp/cli'$(nope)", true)
        verify(command.indexOf("'/tmp/check it.py'") >= 0)
        verify(command.indexOf("--local-only") >= 0)
        verify(command.indexOf("'\\''") >= 0)
        compare(CliUpdate.command("https://evil.test/helper", "codexbar", false), "")
        compare(CliUpdate.command("file:///%ZZ", "codexbar", false), "")
    }
}
