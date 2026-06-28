#!/usr/bin/env bash
# amnezia-wg-macos - uninstaller. Removes the installed binaries. By default it
# KEEPS your configs in /etc/amnezia/amneziawg (they contain your keys). Pass
# --purge to delete the config dir too.
set -euo pipefail

say() { printf '\033[1m>> %s\033[0m\n' "$*"; }

PREFIX="${PREFIX:-$(brew --prefix 2>/dev/null || echo /usr/local)}"
BINDIR="$PREFIX/bin"
CONFDIR="/etc/amnezia/amneziawg"

PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1

rm_path() {  # <path>
	[[ -e "$1" || -L "$1" ]] || return 0
	if [[ -w "$(dirname "$1")" ]]; then rm -f "$1"; else sudo rm -f "$1"; fi
	echo "  removed $1"
}

say "Removing binaries from $BINDIR"
rm_path "$BINDIR/amneziawg-go"
rm_path "$BINDIR/awg"
rm_path "$BINDIR/awg-quick"

if [[ $PURGE -eq 1 ]]; then
	say "Purging config dir $CONFDIR"
	sudo rm -rf "$CONFDIR"
	echo "  removed $CONFDIR"
else
	say "Keeping configs in $CONFDIR (use --purge to delete them)"
fi

printf '\033[1;32m✓ Uninstalled.\033[0m\n'
