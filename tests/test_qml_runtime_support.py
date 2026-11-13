"""Keep the Qt worker diagnostic exception exact and version-specific."""

import unittest

from qml_runtime_support import runtime_warnings


class RuntimeWarningsTests(unittest.TestCase):
    worker_warning = (
        "QWARN  : qmltestrunner::Worker::test_create() qt.core.qobject.connect: "
        "QObject::connect(QJSEngine, QtObject): invalid nullptr parameter")

    def test_only_the_reproduced_qt_version_is_exempt(self):
        for version in ("6.8.2", "6.11.0", "6.11.1", "6.11.2"):
            with self.subTest(version=version):
                output = f"Config: Using QtTest library {version}, Qt {version} (build)\n{self.worker_warning}"
                expected = [] if version == "6.11.1" else [self.worker_warning]
                self.assertEqual(runtime_warnings(output), expected)

    def test_other_warnings_survive_on_affected_qt(self):
        warnings = [
            "QWARN  : qmltestrunner::Worker::test_create() ReferenceError: missing value",
            self.worker_warning.replace("QtObject", "OtherObject"),
            self.worker_warning + " extra diagnostic",
        ]
        output = "Config: Using QtTest library 6.11.1, Qt 6.11.1 (build)\n"
        output += "\n".join([self.worker_warning] + warnings)
        self.assertEqual(runtime_warnings(output), warnings)

    def test_missing_version_does_not_hide_warnings(self):
        self.assertEqual(runtime_warnings(self.worker_warning), [self.worker_warning])
