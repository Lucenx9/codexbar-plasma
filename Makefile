.PHONY: check install restart package

# Override on distros where Qt6 ships QML modules elsewhere (e.g. Debian/Ubuntu
# multiarch: make check QML_IMPORT_DIR=/usr/lib/x86_64-linux-gnu/qt6/qml).
QMLLINT ?= /usr/lib/qt6/bin/qmllint
QML_IMPORT_DIR ?= /usr/lib/qt6/qml
# Extra qmllint flags. CI without the Plasma QML modules sets these to downgrade
# the type/import-resolution categories that would otherwise cascade into
# failures; locally (modules present) they are no-ops, so the check stays full.
QMLLINT_FLAGS ?= --unqualified disable

check:
	scripts/test_feature_parity.sh
	scripts/test_refresh_nonce.sh
	scripts/test_provider_icons.sh
	scripts/test_security_regressions.sh
	scripts/test_qml_hardening.sh
	$(QMLLINT) $(QMLLINT_FLAGS) -I $(QML_IMPORT_DIR) contents/ui/main.qml contents/ui/configGeneral.qml contents/ui/configProviders.qml contents/ui/configDisplay.qml contents/ui/configAdvanced.qml contents/ui/configAbout.qml contents/ui/configDebug.qml
	xmllint --noout contents/config/main.xml
	jq . metadata.json >/dev/null
	@if command -v kpackagetool6 >/dev/null 2>&1; then \
		kpackagetool6 --appstream-metainfo . | xmllint --noout -; \
	else \
		echo "kpackagetool6 not found; skipping appstream metainfo check"; \
	fi

install:
	kpackagetool6 -t Plasma/Applet -u . || kpackagetool6 -t Plasma/Applet -i .

restart:
	systemctl --user restart plasma-plasmashell.service

package:
	mkdir -p dist
	cmake -E tar cf dist/codexbar-plasma.plasmoid --format=zip metadata.json contents docs LICENSE NOTICE.md README.md
