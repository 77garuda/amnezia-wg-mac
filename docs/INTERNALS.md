# Internals - why macOS `awg-quick` failed and how it's fixed

## Symptom

`sudo awg-quick up ./awg0.conf` printed:

```
[#] amneziawg-go utun
[#] rm -f /var/run/wireguard/awg0.name
```

...and returned to the prompt. The engine launched, then the script immediately
rolled back. `awg setconf` / address / route steps never ran. No tunnel.

## What actually happens in the script

`add_if()` runs the engine and then calls `get_real_interface()`:

```bash
add_if() {
    export WG_TUN_NAME_FILE="/var/run/amneziawg/$INTERFACE.name"   # name file -> amneziawg
    mkdir -p "/var/run/amneziawg/"
    cmd "${WG_QUICK_USERSPACE_IMPLEMENTATION:-amneziawg-go}" utun
    get_real_interface
}
```

`get_real_interface()` confirms the interface by comparing mtimes of the UAPI
socket and the name file, requiring them within +/-2 seconds:

```bash
diff=$(( $(stat -f %m "/var/run/amneziawg/$interface.sock" ...) \
       - $(stat -f %m "/var/run/wireguard/$INTERFACE.name" ...) ))   # <- WRONG DIR
[[ $diff -ge 2 || $diff -le -2 ]] && return 1
```

The name file is written to **`/var/run/amneziawg/`** (see `WG_TUN_NAME_FILE`
above), but this line `stat`s it under **`/var/run/wireguard/`**. That `stat`
fails, falls back to the literal `100`, the diff explodes past +/-2, and
`get_real_interface` returns 1 -> bring-up aborts -> `del_if` cleanup runs.

## Root cause

The three components disagreed on the runtime directory:

| Component        | Socket / name dir     | Source of truth |
|------------------|-----------------------|-----------------|
| `amneziawg-go`   | `/var/run/amneziawg`  | `ipc/uapi_unix.go:29` `socketDirectory = "/var/run/amneziawg"` |
| `awg` (C tool)   | `/var/run/amneziawg`  | `ipc-uapi-unix.h:17` `#define SOCK_PATH RUNSTATEDIR "/amneziawg/"` |
| `awg-quick` bash | **mixed** (`amneziawg` *and* `wireguard`) | leftover from the `wireguard-tools` fork |

So the engine and the C tool were already correct and consistent. Only the
Darwin bash script carried three stale `/var/run/wireguard/` references from when
it was forked off `wireguard-tools` (the maintainers search-and-replaced most
paths but missed these).

## The patch

In `src/amneziawg-tools/src/wg-quick/darwin.bash`:

- **line 116** - mtime check: `/var/run/wireguard/$INTERFACE.name` -> `/var/run/amneziawg/$INTERFACE.name`
- **line 156** - `del_if`: `/var/run/wireguard/$REAL_INTERFACE.sock` -> `/var/run/amneziawg/$REAL_INTERFACE.sock`
- **line 157** - `del_if`: `/var/run/wireguard/$INTERFACE.name` -> `/var/run/amneziawg/$INTERFACE.name`

Plus a cosmetic/safety rename so nothing impersonates WireGuard's `wg`:

- script tool calls `wg show|setconf|showconf` -> `awg show|setconf|showconf`
- the C binary is installed as `awg` (the build still produces `wg`; the Makefile
  copies it to `bin/awg`).

The engine (`amneziawg-go`) and the C tool source are otherwise **unmodified**
upstream.

## Verified

- `amneziawg-go` standalone: creates `utunN`, "Interface state ... now Up".
- After the patch: `sudo awg-quick up ./awg0.conf` brings the tunnel up and
  traffic egresses via the AmneziaWG server.

## `ExcludeIPs` extension

A custom `[Interface]` directive added to `darwin.bash` (not upstream). It lets a
full-tunnel config (`AllowedIPs = 0.0.0.0/0`) carve out subnets that should
bypass the VPN.

### Why it lives in the bash script, not the Go engine

`AllowedIPs` is **cryptokey routing** - the engine must know which peer to
encrypt to / accept from, so it's parsed in `amneziawg-go` (`device/allowedips.go`).
But which packets ever reach `utun` is decided by the **OS routing table**, not
the engine. The engine only sees packets the OS already routed into the tunnel.
So excluding a subnet is purely an OS-routing decision - it belongs exactly where
`Address`, `DNS`, and the `AllowedIPs`->route mirroring already live: `awg-quick`.
A hypothetical `excludeips.go` could at most refuse to encrypt those packets; the
OS would still send them to `utun` and they'd be dropped, not routed around. The
route via the real gateway is mandatory, and only the script installs it.

### Implementation (all in `src/amneziawg-tools/src/wg-quick/darwin.bash`)

- `EXCLUDED_IPS=( )` global, parsed in `parse_options()` (`ExcludeIPs)` case),
  alongside `DNS`/`Address`.
- `add_excluded_routes()` - for each subnet, `route add <cidr> -gateway $GATEWAY4/6`
  (the real default gateway, already collected by `collect_gateways`). Skips a
  family if no gateway. Called from `cmd_up()` after `set_endpoint_direct_route`.
- `del_excluded_routes()` - removes them; called from `del_routes()`, so teardown
  happens wherever routes are cleaned (down + the route-monitor exit trap).
- Re-point on gateway change: `set_endpoint_direct_route()` re-runs del+add when
  it detects the default gateway changed (`remove_all_old`), keeping the bypass
  valid across Wi-Fi/network switches.

### Caveat

Routing-level only: traffic to excluded subnets leaves via your LAN gateway in
the clear (as it would without any VPN). If an excluded subnet equals your local
link subnet, macOS already has a link route and the bypass is redundant/harmless.

## Fallback (if the script ever regresses)

The engine + UAPI work on their own, so a tunnel can be raised without the
script at all:

1. `sudo amneziawg-go utun` (note the real `utunN` from `/var/run/amneziawg/<if>.name`)
2. `sudo awg setconf utunN <(awg-quick strip ./awg0.conf)`
3. `sudo ifconfig utunN inet 10.11.0.6/32 10.11.0.6 up; sudo ifconfig utunN mtu 1280`
4. add default route via `utunN`, set DNS to 1.1.1.1
