PATH := "$(NVM_BIN):$(PATH)"
UID := $(shell id -u)
NVM_BINARY := $(shell which node)

.PHONY: install-deps
install-deps:
	which npm
	which npx
	chmod +x ~/.nvm/nvm.sh
	cd .. && npm i
	cd .. && npm i playwright@latest
	cd .. && npx playwright install-deps
	cd .. && ./generate_api_json.sh
	cd .. && ./generate_perl_modules.pl

.PHONY: install-service
install-service:
	test $(PORT)
	test $(NVM_BINARY)
	make install-deps
	[ ! -f /etc/redhat-release ] || make enable-systemd-user-mode
	mkdir -p ~/.config/systemd/user
	cp playwright.unit ~/.config/systemd/user/playwright.service
	sed -i 's#__REPLACEME__#$(shell pwd)#g' ~/.config/systemd/user/playwright.service
	sed -i 's#__PORT__#$(PORT)#g' ~/.config/systemd/user/playwright.service
	sed -i 's#!/usr/bin/node#!$(NVM_BINARY)#g' ../bin/playwright_server
	systemctl --user daemon-reload
	systemctl --user enable playwright
	systemctl --user start playwright
	sudo loginctl enable-linger $(USER)

.PHONY: enable-systemd-user-mode
enable-systemd-user-mode:
	sudo cp systemd/centos-user-mode.unit /etc/systemd/system/user@$(UID).service
	sudo systemctl daemon-reload
	sudo systemctl enable user@$(UID).service
	sudo systemctl start user@$(UID).service
