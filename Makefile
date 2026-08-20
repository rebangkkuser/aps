SHELL = sh
APSV = 2.0.1-r0
.PHONY: apspkg-tdeb syntax clean mgskins

.ONESHELL: apspkg-tdeb

apspkg-tdeb:
	cd ./package/termux
	dpkg-deb --build . ../aps_$(APSV)_termux.deb

syntax:
	sh -n aps.sh

clean:
	:

mgskins:
	su -c magisk install aps*.zip
