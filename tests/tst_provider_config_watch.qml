import QtQuick
import QtTest
import "../contents/ui/ProviderConfigWatch.js" as ConfigWatch

TestCase {
    name: "ProviderConfigWatch"

    function test_firstObservation_data() {
        return [
            {
                tag: "filename-whitespace",
                stdout: "123 42 /synthetic/space name\twith\na newline.json\n",
                stamp: "123 42 /synthetic/space name\twith\na newline.json"
            },
            {
                tag: "missing",
                stdout: "missing",
                stamp: "missing"
            },
            {
                tag: "checksum",
                stdout: "  123 42 /synthetic/config.json\n",
                stamp: "123 42 /synthetic/config.json"
            }
        ];
    }

    function test_firstObservation(data) {
        compare(ConfigWatch.observation("", data.stdout), {
            stamp: data.stamp,
            initial: true
        });
    }

    function test_unchangedChecksumDoesNotPublish() {
        compare(ConfigWatch.observation("123 42 /synthetic/config.json", "123 42 /synthetic/config.json\n"), null);
        compare(ConfigWatch.observation("missing", "missing"), null);
    }

    function test_changedObservation_data() {
        return [
            {
                tag: "edit",
                previous: "123 42 /synthetic/config.json",
                next: "456 42 /synthetic/config.json"
            },
            {
                tag: "created",
                previous: "missing",
                next: "123 42 /synthetic/config.json"
            },
            {
                tag: "removed",
                previous: "123 42 /synthetic/config.json",
                next: "missing"
            },
            {
                tag: "path",
                previous: "123 42 /synthetic/a.json",
                next: "123 42 /synthetic/b.json"
            }
        ];
    }

    function test_changedObservation(data) {
        compare(ConfigWatch.observation(data.previous, data.next), {
            stamp: data.next,
            initial: false
        });
    }

    function test_invalidObservation_data() {
        return [
            {
                tag: "garbage",
                value: "checksum unavailable"
            },
            {
                tag: "missing-prefix",
                value: "missing /synthetic/config.json"
            },
            {
                tag: "invalid-checksum",
                value: "abc 42 /synthetic/config.json"
            },
            {
                tag: "negative-checksum",
                value: "-1 42 /synthetic/config.json"
            },
            {
                tag: "invalid-byte-count",
                value: "123 size /synthetic/config.json"
            },
            {
                tag: "negative-byte-count",
                value: "123 -1 /synthetic/config.json"
            },
            {
                tag: "missing-filename",
                value: "123 42 "
            },
            {
                tag: "multiline-header",
                value: "123\n42 /synthetic/config.json"
            },
            {
                tag: "undefined",
                value: undefined
            },
            {
                tag: "null",
                value: null
            },
            {
                tag: "number",
                value: 123
            },
            {
                tag: "array",
                value: ["missing"]
            },
            {
                tag: "object",
                value: {
                    toString: null
                }
            },
            {
                tag: "empty",
                value: ""
            },
            {
                tag: "blank",
                value: " \n\t"
            },
            {
                tag: "oversized",
                value: "123 42 " + "x".repeat(ConfigWatch.maximumStampLength)
            }
        ];
    }

    function test_invalidObservation(data) {
        compare(ConfigWatch.observation("", data.value), null);
        compare(ConfigWatch.observation("previous", data.value), null);
    }

    function test_stampBoundIsInclusive() {
        var stamp = "123 42 " + "x".repeat(ConfigWatch.maximumStampLength - 7);
        compare(ConfigWatch.observation("", stamp), {
            stamp: stamp,
            initial: true
        });
    }
}
