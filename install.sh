#!/usr/bin/env bash
# amnezia-wg-macos - production installer.
# Builds native binaries, installs them onto your PATH as real copies (so this
# folder can be moved or deleted afterwards), and creates the system config dir
# that awg-quick searches - so you can run `sudo awg-quick up <name>` with no path.
#
# Usage:   ./install.sh
# Intel:   PREFIX=/usr/local ./install.sh   (auto-detected if Homebrew is present)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say()  { printf '\033[1m>> %s\033[0m\n' "$*"; }
err()  { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; }

# --- 0. platform ----------------------------------------------------------
[[ "$(uname)" == "Darwin" ]] || { err "This installer is macOS-only."; exit 1; }

PREFIX="${PREFIX:-$(brew --prefix 2>/dev/null || echo /usr/local)}"
BINDIR="$PREFIX/bin"
CONFDIR="/etc/amnezia/amneziawg"   # one of awg-quick's built-in search paths

# --- 1. prerequisites -----------------------------------------------------
missing=0
if ! command -v go >/dev/null 2>&1; then
	err "Go compiler not found.   Install it:  brew install go"
	missing=1
fi
if ! xcode-select -p >/dev/null 2>&1; then
	err "Xcode Command Line Tools not found.   Install:  xcode-select --install"
	missing=1
fi
if [[ ! -d "$BINDIR" ]]; then
	err "Target bin dir '$BINDIR' does not exist. Is Homebrew installed? Override with PREFIX=..."
	missing=1
fi
[[ $missing -eq 0 ]] || { err "Fix the above, then re-run ./install.sh"; exit 1; }

# --- 2. build -------------------------------------------------------------
say "Building native binaries"
make -C "$ROOT" build

# helper: install a file, using sudo only if the target dir isn't writable
do_install() {  # <mode> <src> <dst>
	local mode="$1" src="$2" dst="$3"
	if [[ -w "$(dirname "$dst")" ]]; then
		install -m "$mode" "$src" "$dst"
	else
		sudo install -m "$mode" "$src" "$dst"
	fi
}

# --- 3. install binaries (real copies) ------------------------------------
say "Installing binaries into $BINDIR"
do_install 0755 "$ROOT/bin/amneziawg-go" "$BINDIR/amneziawg-go"
do_install 0755 "$ROOT/bin/awg"          "$BINDIR/awg"
do_install 0755 "$ROOT/bin/awg-quick"    "$BINDIR/awg-quick"

# --- 4. system config dir -------------------------------------------------
say "Creating config dir $CONFDIR (root-owned, 0700)"
sudo mkdir -p "$CONFDIR"
sudo chmod 700 "$CONFDIR"
# drop a reference template (never overwrite a real config)
if [[ ! -e "$CONFDIR/awg0.conf.example" ]]; then
	sudo install -m 0600 "$ROOT/conf/awg0.conf.example" "$CONFDIR/awg0.conf.example"
fi

# --- 5. done --------------------------------------------------------------
cat <<EOF

$(printf '\033[1;32m✓ Installed.\033[0m')

Binaries:   $BINDIR/{amneziawg-go, awg, awg-quick}
Config dir: $CONFDIR   (a template awg0.conf.example was placed there)

Next steps:
  1) Create your config (fill in your real keys/server):
       sudo cp $CONFDIR/awg0.conf.example $CONFDIR/awg0.conf
       sudo \${EDITOR:-nano} $CONFDIR/awg0.conf
       sudo chmod 600 $CONFDIR/awg0.conf

  2) Connect / disconnect - by name, no path needed:
       sudo awg-quick up awg0
       sudo awg-quick down awg0

  If you also use the Amnezia GUI on the same server/key, quit it first.

This repo folder is no longer needed at runtime - you may move or delete it.
To remove everything later:  ./uninstall.sh
EOF
