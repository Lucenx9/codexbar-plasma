.pragma library
.import "Guards.js" as Guards

var maximumStampLength = 8192;

// Keep the checksum text stable: persisted usage contexts already include it.
function watchCommand() {
    var script = [
        "config=${CODEXBAR_CONFIG:-};",
        "case \"$config\" in '~/'*) config=\"$HOME/${config#\\~/}\";; esac;",
        "if [ -z \"$config\" ]; then",
        "xdg=${XDG_CONFIG_HOME:-};",
        "case \"$xdg\" in '~/'*) xdg=\"$HOME/${xdg#\\~/}\";; esac;",
        "case \"$xdg\" in",
        "/*) config=\"$xdg/codexbar/config.json\";;",
        "*) config=\"$HOME/.config/codexbar/config.json\"; if [ ! -e \"$config\" ] && [ -e \"$HOME/.codexbar/config.json\" ]; then config=\"$HOME/.codexbar/config.json\"; fi;;",
        "esac;",
        "fi;",
        "if [ -r \"$config\" ]; then cksum \"$config\"; else printf missing; fi"
    ].join(" ");
    return ["sh", "-c", Guards.shellQuote(script)].join(" ");
}

function observation(previousStamp, stdoutValue) {
    if (typeof stdoutValue !== "string" || stdoutValue.length > maximumStampLength) return null;
    var stamp = stdoutValue.trim();
    if (stamp.length === 0 || stamp === previousStamp) return null;
    return {stamp: stamp, initial: previousStamp.length === 0};
}
