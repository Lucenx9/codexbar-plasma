.PHONY: check todo-gate smoke install restart package translations compile-translations update

PACKAGE_FILES := metadata.json contents docs/codexbar-plasma-overview.png docs/codexbar-plasma-codex.png docs/codexbar-plasma-usage-spend.png docs/codexbar-plasma-sessions.png docs/codexbar-plasma-panel-standard.png docs/codexbar-plasma-panel-minimal.png docs/codexbar-plasma-tour.gif scripts/update-widget.sh scripts/check-cli-update.py scripts/manage-cli.py scripts/ai-insights.py scripts/lib/cli_release.py scripts/lib/managed_cli.py scripts/lib/ai_insights.py LICENSE NOTICE.md README.md CHANGELOG.md

# Override on distros where Qt6 ships QML modules elsewhere (e.g. Debian/Ubuntu
# multiarch: make check QML_IMPORT_DIR=/usr/lib/x86_64-linux-gnu/qt6/qml).
QMLLINT ?= /usr/lib/qt6/bin/qmllint
# Empty when dpkg-architecture is absent: the `uname -m`-linux-gnu candidate
# below already covers that case, while a raw `uname -m` fallback would build
# a dead `/usr/lib/<arch>/qt6/qml` candidate that never exists.
DEB_HOST_MULTIARCH := $(shell dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || true)
QML_IMPORT_DIR ?= $(or $(wildcard /usr/lib/qt6/qml),$(wildcard /usr/lib/$(DEB_HOST_MULTIARCH)/qt6/qml),$(wildcard /usr/lib/$(shell uname -m)-linux-gnu/qt6/qml),$(firstword $(wildcard /usr/lib/*-linux-gnu/qt6/qml)),/usr/lib/qt6/qml)
# CI explicitly enables import warnings so the portable fallback in
# test_qml_hardening.sh cannot hide missing Plasma modules.
QMLLINT_FLAGS ?= --unqualified disable

# Checks are independent targets so one `make check` runs them concurrently.
# Override on a constrained machine: make check JOBS=2.
JOBS ?= $(shell nproc 2>/dev/null || echo 4)
# Only the check suite opts into parallelism, so `make smoke` and the packaging
# targets keep streaming their output. --output-sync keeps each check's lines
# together instead of interleaving them, so a failure stays readable. An empty
# goal list means the default goal, which is `check`.
ifneq (,$(if $(MAKECMDGOALS),$(filter check,$(MAKECMDGOALS)),check))
MAKEFLAGS += -j$(JOBS) --output-sync=target
endif
# Most `tests/test_*.py` modules start their own qmltestrunner, so the Python
# suite dominates the wall time when it runs as a single sequential command.
# One target per module lets those processes overlap. `wildcard` keeps the list
# free of a shell invocation, and these filenames are repository-controlled.
PYTHON_TEST_MODULES := $(patsubst tests/%.py,%,$(wildcard tests/test_*.py))
PYTHON_CHECK_TARGETS := $(addprefix check-python-,$(PYTHON_TEST_MODULES))
CHECK_TARGETS := \
	check-qml-logic \
	$(PYTHON_CHECK_TARGETS) \
	check-changelog \
	check-shellcheck \
	check-workflows \
	check-python-lint \
	check-feature-parity \
	check-refresh-nonce \
	check-process-lifecycle \
	check-ui-regressions \
	check-provider-icons \
	check-security-regressions \
	check-update-widget \
	check-theme-boundaries \
	check-i18n-catalog \
	check-cli-descriptor-contract \
	check-qml-hardening \
	check-config-schema \
	check-metadata \
	check-appstream

# The per-module Python targets stay out of .PHONY: make skips the implicit
# rule search for phony targets, and they are served by a pattern rule below.
# No file carries any of these names, so they always run.
.PHONY: $(filter-out $(PYTHON_CHECK_TARGETS),$(CHECK_TARGETS))

check: $(CHECK_TARGETS)

check-changelog:
	python3 scripts/changelog.py

check-shellcheck:
	scripts/test_shellcheck.sh

# actionlint is not packaged for every distribution; CI installs it. Like the
# appstream check below, an absent tool is reported as skipped, never as passed.
check-workflows:
	@if command -v actionlint >/dev/null 2>&1; then \
		set -x; actionlint; \
	else \
		echo "actionlint not found; skipping workflow lint"; \
	fi

# pyflakes reports undefined names and unused imports without reformatting
# anything, so it adds no style churn to the check suite.
check-python-lint:
	@if python3 -c 'import pyflakes' >/dev/null 2>&1; then \
		set -x; python3 -m pyflakes scripts tests; \
	else \
		echo "pyflakes not found; skipping Python lint"; \
	fi

check-feature-parity:
	scripts/test_feature_parity.sh

check-refresh-nonce:
	scripts/test_refresh_nonce.sh

check-process-lifecycle:
	scripts/test_process_lifecycle.sh

check-ui-regressions:
	scripts/test_ui_regressions.sh

check-provider-icons:
	scripts/test_provider_icons.sh

check-security-regressions:
	scripts/test_security_regressions.sh

check-update-widget:
	scripts/test_update_widget.sh

check-theme-boundaries:
	scripts/test_theme_boundaries.sh

check-i18n-catalog:
	scripts/test_i18n_catalog.sh

check-cli-descriptor-contract:
	scripts/test_cli_descriptor_contract.sh

check-qml-logic:
	scripts/test_qml_logic.sh

# `discover` with a single-module pattern keeps the import semantics of the
# whole-suite run: tests/ stays the top-level directory on the path.
check-python-%:
	python3 -m unittest discover -s tests -p '$*.py'

check-qml-hardening:
	scripts/test_qml_hardening.sh

check-config-schema:
	xmllint --noout contents/config/main.xml

check-metadata:
	jq . metadata.json >/dev/null

check-appstream:
	@if command -v kpackagetool6 >/dev/null 2>&1; then \
		kpackagetool6 --appstream-metainfo . | xmllint --noout -; \
	else \
		echo "kpackagetool6 not found; skipping appstream metainfo check"; \
	fi

todo-gate:
	python3 scripts/todo_gate.py $(GATE_ARGS)

smoke:
	python3 scripts/smoke_popup.py $(SMOKE_ARGS)

install: package
	kpackagetool6 -t Plasma/Applet -u dist/codexbar-plasma.plasmoid || kpackagetool6 -t Plasma/Applet -i dist/codexbar-plasma.plasmoid

restart:
	systemctl --user restart plasma-plasmashell.service

update:
	scripts/update-widget.sh --install

translations:
	scripts/update_translations.sh

compile-translations:
	python3 scripts/compile_translations.py

package:
	mkdir -p dist
	rm -f dist/codexbar-plasma.plasmoid dist/codexbar-plasma.plasmoid.sha256
	@if find $(PACKAGE_FILES) -type l -print -quit | grep -q .; then \
		echo "refusing to package symlinks from PACKAGE_FILES" >&2; \
		find $(PACKAGE_FILES) -type l -print >&2; \
		exit 1; \
	fi
	$(MAKE) compile-translations
	@if command -v cmake >/dev/null 2>&1; then \
		cmake -E tar cf dist/codexbar-plasma.plasmoid --format=zip $(PACKAGE_FILES); \
	elif command -v zip >/dev/null 2>&1; then \
		zip -qr dist/codexbar-plasma.plasmoid $(PACKAGE_FILES); \
	elif command -v python3 >/dev/null 2>&1; then \
		python3 -m zipfile -c dist/codexbar-plasma.plasmoid $(PACKAGE_FILES); \
	else \
		echo "missing required command: cmake, zip, or python3" >&2; \
		exit 127; \
	fi
	@command -v sha256sum >/dev/null 2>&1 || { \
		echo "missing required command: sha256sum" >&2; \
		exit 127; \
	}
	cd dist && sha256sum codexbar-plasma.plasmoid > codexbar-plasma.plasmoid.sha256
