.PHONY: check install restart package translations update

PACKAGE_FILES := metadata.json contents docs/codexbar-plasma-overview.png docs/codexbar-plasma-codex.png scripts/update-widget.sh LICENSE NOTICE.md README.md

# Override on distros where Qt6 ships QML modules elsewhere (e.g. Debian/Ubuntu
# multiarch: make check QML_IMPORT_DIR=/usr/lib/x86_64-linux-gnu/qt6/qml).
QMLLINT ?= /usr/lib/qt6/bin/qmllint
QML_IMPORT_DIR ?= /usr/lib/qt6/qml
# Extra qmllint flags. CI without the Plasma QML modules sets these to downgrade
# the type/import-resolution categories that would otherwise cascade into
# failures; locally (modules present) they are no-ops, so the check stays full.
QMLLINT_FLAGS ?= --unqualified disable
# Read from the one source list in scripts/lib/qml_surfaces.py so adding or
# moving a QML file does not need an edit here, in the hardening check, and in
# the gettext extraction. `check` fails loudly if that lookup produced nothing.
QML_FILES := $(shell python3 scripts/lib/qml_surfaces.py files all)

check:
	@test -n "$(QML_FILES)" || { echo "QML_FILES is empty: scripts/lib/qml_surfaces.py failed" >&2; exit 1; }
	scripts/test_feature_parity.sh
	scripts/test_refresh_nonce.sh
	scripts/test_process_lifecycle.sh
	scripts/test_ui_regressions.sh
	scripts/test_provider_icons.sh
	scripts/test_security_regressions.sh
	scripts/test_update_widget.sh
	scripts/test_theme_boundaries.sh
	scripts/test_i18n_catalog.sh
	scripts/test_cli_descriptor_contract.sh
	scripts/test_qml_logic.sh
	scripts/test_qml_hardening.sh
	$(QMLLINT) $(QMLLINT_FLAGS) -I $(QML_IMPORT_DIR) $(QML_FILES)
	xmllint --noout contents/config/main.xml
	jq . metadata.json >/dev/null
	@if command -v kpackagetool6 >/dev/null 2>&1; then \
		kpackagetool6 --appstream-metainfo . | xmllint --noout -; \
	else \
		echo "kpackagetool6 not found; skipping appstream metainfo check"; \
	fi

install: package
	kpackagetool6 -t Plasma/Applet -u dist/codexbar-plasma.plasmoid || kpackagetool6 -t Plasma/Applet -i dist/codexbar-plasma.plasmoid

restart:
	systemctl --user restart plasma-plasmashell.service

update:
	scripts/update-widget.sh --install

translations:
	scripts/update_translations.sh

package:
	mkdir -p dist
	rm -f dist/codexbar-plasma.plasmoid dist/codexbar-plasma.plasmoid.sha256
	@if find $(PACKAGE_FILES) -type l -print -quit | grep -q .; then \
		echo "refusing to package symlinks from PACKAGE_FILES" >&2; \
		find $(PACKAGE_FILES) -type l -print >&2; \
		exit 1; \
	fi
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
