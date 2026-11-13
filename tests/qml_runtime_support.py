"""Keep known Qt runtime diagnostics separate from applet warnings."""


def runtime_warnings(output):
    warnings = [line for line in output.splitlines() if "QWARN" in line]
    # A dynamically created empty WorkerScript reproduces this in Qt 6.11.1:
    # QtObject connects uiLanguageChanged with the worker's null QJSEngine.
    if "Config: Using QtTest library 6.11.1, Qt 6.11.1 (" in output:
        worker_warning = (
            "qt.core.qobject.connect: QObject::connect(QJSEngine, QtObject): invalid nullptr parameter")
        warnings = [line for line in warnings if not line.endswith(worker_warning)]
    return warnings
