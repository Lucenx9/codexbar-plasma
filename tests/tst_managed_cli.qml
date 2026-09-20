import QtQuick
import QtTest
import "../contents/ui/ManagedCli.js" as ManagedCli

TestCase {
    name: "ManagedCli"
    function test_boundedResponse() {
        var path = "/home/test/.local/share/codexbar-plasma/cli/current/codexbar"
        var valid = {status: "installed", version: "0.62.0", previous: "0.61.0", path: path}
        compare(ManagedCli.response(JSON.stringify(valid)).path, path)
        for (var value of [null, [], {}, {status: "installed"}, Object.assign({}, valid, {version: ["0.62.0"]}),
                          Object.assign({}, valid, {path: "/usr/bin/codexbar"}),
                          Object.assign({}, valid, {path: "/home/../" + path}),
                          Object.assign({}, valid, {version: "0.62.0-beta"})]) {
            compare(ManagedCli.response(JSON.stringify(value)).status, "error")
        }
        compare(ManagedCli.response("x".repeat(20000)).status, "error")
    }
    function test_authoritativeAndTransientResults() {
        var prior = {status: "ready", version: "0.62.0", previous: "0.61.0",
            path: "/home/test/.local/share/codexbar-plasma/cli/current/codexbar"}
        for (var item of [{status: "error"}, {status: "busy"}, {status: "external"}]) {
            var retained = ManagedCli.nextResponse(prior, JSON.stringify(item))
            compare(retained.path, prior.path)
            compare(retained.version, prior.version)
            compare(retained.previous, prior.previous)
        }
        var missingPrevious = ManagedCli.nextResponse(prior, '{"status":"no_previous"}')
        compare(missingPrevious.path, prior.path)
        compare(missingPrevious.previous, "")
        compare(ManagedCli.nextResponse(prior, JSON.stringify(Object.assign({}, prior,
            {status: "no_previous"}))).previous, "")
        for (var absent of [{status: "absent"}, Object.assign({}, prior, {status: "absent"})]) {
            var missing = ManagedCli.nextResponse(prior, JSON.stringify(absent))
            compare(missing.path, "")
            compare(missing.version, "")
            compare(missing.previous, "")
        }
        compare(ManagedCli.nextResponse({status: "ready", path: "/tmp/private"}, "").path, "")
        var cyclic = {}; cyclic.previous = cyclic
        compare(ManagedCli.nextResponse(cyclic, "").path, "")
    }
    function test_command() {
        compare(ManagedCli.command("file:///%ZZ", "install", "codexbar"), "")
        compare(ManagedCli.command("https://evil.test/helper", "install", "codexbar"), "")
        compare(ManagedCli.command("file:///tmp/helper.py", "delete", "codexbar"), "")
        var command = ManagedCli.command("file:///tmp/helper%20a.py", "update", "/tmp/cli ' $(touch nope)")
        verify(command.indexOf("'" + "/tmp/helper a.py" + "'") >= 0)
        verify(command.indexOf("--action 'update'") >= 0)
        verify(command.indexOf("'\\''") >= 0)
    }
}
