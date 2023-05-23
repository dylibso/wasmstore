PREFIX?=/usr/local

build:
	dune build

install:
	mkdir -p $(PREFIX)/bin
	cp _build/install/default/bin/wasmstore  $(PREFIX)/bin/wasmstore

uninstall:
	rm -f $(PREFIX)/bin/wasmstore 

service:
	mkdir -p ~/.config/systemd/user
	cp scripts/wasmstore.service ~/.config/systemd/user/wasmstore.service
	systemctl --user daemon-reload
	@echo 'To start the wasmstore service run: systemctml --user start wasmstore'
