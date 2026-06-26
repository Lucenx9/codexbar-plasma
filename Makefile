.PHONY: check install restart package

# Override on distros where Qt6 ships QML modules elsewhere (e.g. Debian/Ubuntu
# multiarch: make check QML_IMPORT_DIR=/usr/lib/x86_64-linux-gnu/qt6/qml).
QMLLINT ?= /usr/lib/qt6/bin/qmllint
QML_IMPORT_DIR ?= /usr/lib/qt6/qml

check:
	scripts/test_feature_parity.sh
	scripts/test_refresh_nonce.sh
	scripts/test_provider_icons.sh
	$(QMLLINT) -I $(QML_IMPORT_DIR) contents/ui/main.qml contents/ui/configGeneral.qml contents/ui/configProviders.qml
	xmllint --noout contents/config/main.xml
	jq . metadata.json >/dev/null
	kpackagetool6 --appstream-metainfo . | xmllint --noout -

install:
	kpackagetool6 -t Plasma/Applet -u . || kpackagetool6 -t Plasma/Applet -i .

restart:
	systemctl --user restart plasma-plasmashell.service

package:
	mkdir -p dist
	cmake -E tar cf dist/codexbar-plasma.plasmoid --format=zip metadata.json contents LICENSE NOTICE.md README.md
