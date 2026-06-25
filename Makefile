.PHONY: check install restart package

check:
	scripts/test_feature_parity.sh
	scripts/test_refresh_nonce.sh
	/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml contents/ui/main.qml contents/ui/configGeneral.qml contents/ui/configProviders.qml
	xmllint --noout contents/config/main.xml
	jq . metadata.json >/dev/null
	kpackagetool6 --appstream-metainfo . | xmllint --noout -

install:
	kpackagetool6 -t Plasma/Applet -u . || kpackagetool6 -t Plasma/Applet -i .

restart:
	systemctl --user restart plasma-plasmashell.service

package:
	mkdir -p dist
	zip -r dist/codexbar-plasma.plasmoid metadata.json contents LICENSE NOTICE.md README.md
