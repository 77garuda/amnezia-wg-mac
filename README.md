# amnezia-wg-macos

**AmneziaWG on macOS from the command line - without the Amnezia GUI client.**

AmneziaWG (obfuscated WireGuard) ships an official **GUI** client for macOS, but
no working **CLI**. The upstream `amneziawg-tools` `awg-quick` script is broken on
macOS - it never brings the tunnel up, it just rolls back. This repo is a patched,
self-contained build that makes the plain command work:

```sh
sudo awg-quick up ./awg0.conf
sudo awg-quick down ./awg0.conf
```

No GUI. No `wireguard-tools`. No Homebrew packages at runtime. Just the engine,
the config tool, and the script - built from source, native (Apple Silicon & Intel).

> **It does NOT "just work" after `git clone`.** You must install two build
> prerequisites and create your own config file. Follow the steps below in order
> and it will work the first time. Every known failure is covered in
> **[Troubleshooting](#troubleshooting)**.

---

## TL;DR (the whole thing, in order)

```sh
# 1. prerequisites (skip any you already have)
xcode-select --install            # C toolchain
brew install go                   # Go compiler (build-time only)

# 2. get the code and run the installer (builds + installs everything)
git clone https://github.com/<you>/amnezia-wg-macos.git
cd amnezia-wg-macos
./install.sh                      # Intel: PREFIX=/usr/local ./install.sh (auto-detected)

# 3. create your config in the system dir, fill in YOUR values
sudo cp /etc/amnezia/amneziawg/awg0.conf.example /etc/amnezia/amneziawg/awg0.conf
sudo ${EDITOR:-nano} /etc/amnezia/amneziawg/awg0.conf
sudo chmod 600 /etc/amnezia/amneziawg/awg0.conf

# 4. connect / disconnect - by name, no path, from anywhere
sudo awg-quick up awg0
sudo awg-quick down awg0
```

If anything goes wrong, jump straight to **[Troubleshooting](#troubleshooting)**.

---

## Prerequisites (required - not installed automatically)

You need TWO things before building. The build **will fail** without them.

| Need | Install | Verify |
|------|---------|--------|
| Xcode Command Line Tools (clang/make) | `xcode-select --install` | `clang --version` prints a version |
| Go compiler | `brew install go` | `go version` prints a version |

Go is only needed to **build**. Once built, the tunnel runs without Go - you can
`brew uninstall go` afterwards if you want.

This repo assumes **Homebrew** is installed (that's where the commands get linked).
- Apple Silicon: Homebrew lives in `/opt/homebrew` (the default `PREFIX`).
- Intel Mac: Homebrew lives in `/usr/local` -> pass `PREFIX=/usr/local` (see Install).

---

## Install

```sh
git clone https://github.com/<you>/amnezia-wg-macos.git
cd amnezia-wg-macos
./install.sh
```

`./install.sh` is the production installer. It:
1. **Checks prerequisites** (Go, Xcode CLT) and stops with a clear message if any
   are missing.
2. **Builds** native binaries (auto-detects Apple Silicon vs Intel).
3. **Installs real copies** of `amneziawg-go`, `awg`, `awg-quick` into your
   Homebrew `bin` (on your `PATH`). Because they're copies - **not** symlinks -
   you can move or delete this repo afterwards.
4. **Creates the system config dir** `/etc/amnezia/amneziawg/` (root-owned, `0700`)
   and drops a template there. `awg-quick` searches this dir, so you run tunnels
   **by name** (`awg-quick up awg0`) from anywhere - no path, no `cd`.

**Intel Macs** are auto-detected via Homebrew. If detection fails, force it:

```sh
PREFIX=/usr/local ./install.sh
```

Verify:

```sh
which awg-quick awg amneziawg-go      # 3 paths in your Homebrew bin
```

If `which` finds nothing, your Homebrew `bin` isn't on `PATH` - see Troubleshooting.

> `make install` / `make uninstall` are thin wrappers around these scripts.
> `make dev-install` is an alternative that symlinks the build in place (for
> hacking on the repo) - there the repo must stay put.

---

## Configure (you must create your own config)

The repo ships only a template - `conf/awg0.conf.example` - because a real config
contains your **private key**, which must never be committed or shared. The
installer copies that template to the system config dir; create your real config
there:

```sh
sudo cp /etc/amnezia/amneziawg/awg0.conf.example /etc/amnezia/amneziawg/awg0.conf
sudo ${EDITOR:-nano} /etc/amnezia/amneziawg/awg0.conf
sudo chmod 600 /etc/amnezia/amneziawg/awg0.conf
```

(You can also keep a config anywhere and pass it by path: `sudo awg-quick up
./awg0.conf`. The system dir is just what lets you run it **by name**.)

Fill in every `<...>` placeholder. Where the values come from:

| Field | What it is |
|-------|------------|
| `PrivateKey` | Your client private key (from your AmneziaWG provider / server) |
| `Address` | The client IP the server assigned you, e.g. `10.11.0.6/32` |
| `DNS` | DNS server to use while connected, e.g. `1.1.1.1` |
| `MTU` | Interface MTU, e.g. `1280` |
| `Jc Jmin Jmax S1 S2 H1 H2 H3 H4` | AmneziaWG obfuscation params - **must match the server exactly** |
| `PublicKey` (in `[Peer]`) | The server's public key |
| `Endpoint` | The server `IP:port`, e.g. `203.0.113.7:443` |
| `AllowedIPs` | `0.0.0.0/0` for a full tunnel |
| `PersistentKeepalive` | `25` is fine |

Rules:
- The **filename before `.conf` is the interface name** and must be <=15 characters
  (`awg0` is fine). Keep it simple. That name is what you pass to `awg-quick`.
- Keep it private (`chmod 600`), or you'll see a harmless "world accessible" warning.

### Optional: `ExcludeIPs` (custom extension)

Carve out subnets that should **bypass** the tunnel (go out your normal gateway)
while everything else stays in the VPN. Add to the `[Interface]` section:

```ini
[Interface]
...
ExcludeIPs = 172.48.0.0/24, 192.168.0.0/24
```

This is a **routing-level** split: for each subnet, `awg-quick` adds a route via
your real default gateway, so those packets never enter the tunnel. `AllowedIPs`
stays `0.0.0.0/0`. Routes are removed on `down` and re-pointed automatically if
your default gateway changes. Not an upstream feature - see `docs/INTERNALS.md`.
Omit the line entirely for a plain full tunnel.

---

## Usage

```sh
sudo awg-quick up awg0              # connect (config from /etc/amnezia/amneziawg/awg0.conf)
sudo awg show                       # check handshake + transfer
sudo awg-quick down awg0            # disconnect
```

(Prefer a config outside the system dir? Pass it by path instead of by name:
`sudo awg-quick up ./awg0.conf`.)

- **`sudo` is required** - creating the `utun` interface and routes needs root.
  This is normal for any VPN, not a quirk of this tool.
- **If you also run the Amnezia GUI against the same server/key, turn it OFF first.**
  A WireGuard server keeps one endpoint per public key, so two clients with the
  same key fight over the session and neither stays up.

Confirm it actually works:

```sh
route -n get 8.8.8.8                 # interface: utunN   -> traffic goes through VPN
curl ifconfig.me                     # should show the server's IP
```

With `ExcludeIPs = 172.48.0.0/24`:

```sh
route -n get 172.48.0.50             # interface: en0, gateway: <your router> -> bypassing VPN
```

(`gateway: 192.168.x.1` there is correct - that's your router; off-LAN traffic
always goes to the default gateway first.)

---

## Uninstall

```sh
./uninstall.sh              # remove the installed binaries (keeps your configs)
./uninstall.sh --purge      # also delete /etc/amnezia/amneziawg and its configs
```

Configs are kept by default because they hold your keys. No daemons, no
LaunchDaemons, no kernel extensions are installed - nothing else to clean up.

---

## Troubleshooting

**`make` fails with `clang: command not found` or `go: command not found`**
You skipped a prerequisite. Run `xcode-select --install` and `brew install go`,
then `make install` again.

**`sudo: awg-quick: command not found`**
Your Homebrew `bin` isn't on `PATH`, or you're on Intel and installed to the wrong
prefix. Check: `ls -l $(brew --prefix)/bin/awg-quick`. If it's missing, re-run
`./install.sh` (Intel: `PREFIX=/usr/local ./install.sh`). If it exists but isn't
found, add Homebrew to your shell: `eval "$(brew shellenv)"` (and add that line to
`~/.zprofile`).

**`awg-quick up` runs `amneziawg-go utun` then immediately `rm ... .name` and exits**
That's the *original upstream* bug this repo fixes - it means you're running a
stock `awg-quick`, not this one. Make sure `which awg-quick` points into this
repo's `bin/`, not somewhere else.

**Tunnel comes up but no internet / no handshake**
Almost always the Amnezia **GUI is still connected with the same key**. Quit it
fully and retry. Also double-check `Endpoint`, `PublicKey`, and the `H1-H4`/`S1/S2`
obfuscation params match the server exactly - a single wrong value = no handshake.

**`Warning: '.../awg0.conf' is world accessible`**
Harmless, but fix with `chmod 600 conf/awg0.conf`.

**Commands broke after I moved/deleted the folder**
Only happens if you used `make dev-install` (symlinks into the repo). The normal
`./install.sh` copies the binaries, so moving/deleting the repo is fine. If you
used dev mode, put the repo back or run `./install.sh` for a real install.

**Installed into `/opt/homebrew` but I'm on Intel**
Run `./uninstall.sh`, then `PREFIX=/usr/local ./install.sh`.

---

## Layout

```
install.sh    production installer (build + copy onto PATH + system config dir)
uninstall.sh  remove binaries (--purge also removes configs)
Makefile      build / clean; install/uninstall delegate to the scripts
bin/          build outputs (git-ignored): amneziawg-go, awg, awg-quick
conf/         awg0.conf.example (real *.conf git-ignored)
src/          vendored, patched sources: amneziawg-go, amneziawg-tools
docs/         INTERNALS.md - full root-cause + fix + ExcludeIPs writeup
```

## What was patched

- `amneziawg-tools` Darwin `awg-quick`: socket directory aligned to
  `/var/run/amneziawg` (upstream left three stale `/var/run/wireguard` paths that
  broke bring-up); tool calls renamed `wg`->`awg`; added the `ExcludeIPs` directive.
- `amneziawg-go` engine and the `awg` C tool are **vanilla upstream**, unmodified.

Full writeup: `docs/INTERNALS.md`.

## Credits & License

Built on [amnezia-vpn/amneziawg-go](https://github.com/amnezia-vpn/amneziawg-go)
and [amnezia-vpn/amneziawg-tools](https://github.com/amnezia-vpn/amneziawg-tools),
themselves forks of Jason A. Donenfeld's WireGuard. `amneziawg-go` is **MIT**,
`amneziawg-tools` (incl. the patched `awg-quick`) is **GPL-2.0**. See `LICENSE`
and the per-component license files under `src/`. All original copyrights retained.
