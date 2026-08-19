.pragma library

// The guards every surface needs before it touches CLI-controlled data.
//
// QML and JS files share no function scope, so each file that calls one of
// these unqualified still has to declare the name. What it no longer has to
// carry is the body: a declaration here is a one-line delegation, so the
// prototype-pollution guard and the shell-quoting rule exist once and are tested
// once, instead of being copied into four or five files and asserted by
// searching each copy for the right fragment.
//
// `scripts/test_security_regressions.sh` still requires the declaration in every
// calling file through `require_definition_where_used`; the fragment it pins is
// now the delegation rather than a repeated guard.

// Own properties only, read through `Object.prototype` so a payload carrying its
// own `hasOwnProperty` key cannot answer for itself.
function hasOwnKey(item, key) {
    return item ? Object.prototype.hasOwnProperty.call(item, key) : false
}

// The key is coerced first: a non-string key that stringifies to `__proto__`
// reaches the same slot as the string would.
function isUnsafeObjectKey(key) {
    var value = String(key || "")
    return value === "__proto__" || value === "constructor" || value === "prototype"
}

function copyObject(item) {
    var copy = ({})
    for (var key in item) {
        if (!hasOwnKey(item, key) || isUnsafeObjectKey(key)) {
            continue
        }
        copy[key] = item[key]
    }
    return copy
}

// Single-quote the whole value and close, escape, reopen around each embedded
// quote. Inside single quotes a POSIX shell expands nothing, so this is the only
// escaping the value needs, and it is the reason no CLI-controlled string can
// grow into a second command.
function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
}
