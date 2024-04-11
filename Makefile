PREFIX?=/usr/local
VERSION?=main
TARGET?=$(shell uname -m)
UNAME_S:=$(shell uname -s | tr '[:upper:]' '[:lower:]')
ifeq ($(UNAME_S),darwin)
	UNAME_S=macos
endif
RELEASE_DIR=wasmstore-$(TARGET)-$(UNAME_S)-$(VERSION)

build:
	dune build

clean:
	cargo clean
	dune clean

install:
	mkdir -p $(PREFIX)/bin
	cp _build/default/bin/main.exe $(PREFIX)/bin/wasmstore

uninstall:
	rm -f $(PREFIX)/bin/wasmstore 

service:
	mkdir -p ~/.config/systemd/user
	cp scripts/wasmstore.service ~/.config/systemd/user/wasmstore.service
	systemctl --user daemon-reload
	@echo 'To start the wasmstore service run: systemctml --user start wasmstore'

release: build
	rm -rf $(RELEASE_DIR)
	mkdir -p $(RELEASE_DIR)
	cp _build/install/default/bin/wasmstore $(RELEASE_DIR)
	cp scripts/wasmstore.service  $(RELEASE_DIR)
	cp README.md $(RELEASE_DIR)
	cp LICENSE $(RELEASE_DIR)
	tar czfv $(RELEASE_DIR).tar.gz $(RELEASE_DIR)
	shasum -a 256 $(RELEASE_DIR).tar.gz > $(RELEASE_DIR).checksum.txt
