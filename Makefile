# amnezia-wg-macos - build & install the patched AmneziaWG CLI for macOS
# Engine + C tool are vanilla upstream; only the Darwin awg-quick script is patched.

PREFIX  ?= /opt/homebrew
BINDIR  := $(PREFIX)/bin
ROOT    := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BIN     := $(ROOT)/bin

GO_SRC    := $(ROOT)/src/amneziawg-go
TOOLS_SRC := $(ROOT)/src/amneziawg-tools/src

.PHONY: all build install uninstall dev-install clean

all: build

build:
	@echo ">> building amneziawg-go (engine)"
	$(MAKE) -C $(GO_SRC)
	@echo ">> building awg (C tool)"
	$(MAKE) -C $(TOOLS_SRC)
	@mkdir -p $(BIN)
	cp $(GO_SRC)/amneziawg-go              $(BIN)/amneziawg-go
	cp $(TOOLS_SRC)/wg                      $(BIN)/awg
	cp $(TOOLS_SRC)/wg-quick/darwin.bash   $(BIN)/awg-quick
	chmod +x $(BIN)/amneziawg-go $(BIN)/awg $(BIN)/awg-quick
	@echo ">> built into $(BIN)"

# Production install: real copies into $PREFIX/bin + system config dir.
# Delegates to install.sh (handles prereqs, sudo, config dir). Recommended.
install:
	PREFIX=$(PREFIX) $(ROOT)/install.sh

uninstall:
	PREFIX=$(PREFIX) $(ROOT)/uninstall.sh

# Dev-only: symlink the freshly built bin/ into $PREFIX/bin (repo must stay put).
dev-install: build
	@echo ">> symlinking into $(BINDIR) (dev mode - keep this repo in place)"
	ln -sf $(BIN)/amneziawg-go $(BINDIR)/amneziawg-go
	ln -sf $(BIN)/awg          $(BINDIR)/awg
	ln -sf $(BIN)/awg-quick    $(BINDIR)/awg-quick

clean:
	rm -rf $(BIN)
	-$(MAKE) -C $(GO_SRC) clean
	-$(MAKE) -C $(TOOLS_SRC) clean
