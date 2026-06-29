# Configuration reference

All configuration is passed as environment variables. Defaults live in
`src/defaults/terminal.env` and `src/defaults/legacy.env` and use
`${VAR:=default}` assignment, so any value you export takes priority and is
preserved across re-runs.

```bash
curl -fsSL .../install.sh | sudo env KEY=value KEY2=value2 bash -s -- terminal
# or, once installed:
sudo env KEY=value raylink terminal
```

## Node basics

| Variable | Default | Purpose |
|---|---|---|
| `PORT` | `443` | Xray VLESS Reality listen port |
| `NODE_NAME` | `Terminal-Reality` | Node display name in clients |
| `INSTALL_DIR` | `/opt/cloud-xray-terminal` | Generated-files directory |
| `LISTEN_ADDRESS` | `0.0.0.0` | Xray inbound bind address |
| `ENABLE_TFO` | `false` | TCP Fast Open in Xray + client config |

## Xray service identity

| Variable | Default |
|---|---|
| `XRAY_BIN` | `/usr/local/bin/xray` |
| `XRAY_CONFIG_DIR` | `/usr/local/etc/xray` |
| `XRAY_CONFIG` | `${XRAY_CONFIG_DIR}/config.json` |
| `XRAY_SERVICE` | `xray.service` |
| `XRAY_SERVICE_USER` / `XRAY_SERVICE_GROUP` | `xray` / `xray` |

## Reality target, credentials, self-test

| Variable | Default | Purpose |
|---|---|---|
| `REALITY_DEST` | _(auto)_ `www.cloudflare.com:443` | Reality target `host:port` |
| `REALITY_SERVER_NAME` | _(derived from dest)_ | SNI / serverName |
| `CLIENT_FINGERPRINT` | _(random from pool)_ | uTLS fingerprint |
| `CLIENT_FINGERPRINT_POOL` | `chrome` | Pool to pick from when unset |
| `FLOW` | `xtls-rprx-vision` | VLESS flow |
| `RESET_REALITY_CREDENTIALS` | `false` | Regenerate UUID/keys/shortId |
| `UUID` / `PRIVATE_KEY` / `PUBLIC_KEY` / `SHORT_ID` | _(generated)_ | Supply to pin values |
| `CHECK_REALITY_TARGET` | `true` | TLS 1.3 probe of the target |
| `REALITY_CHECK_STRICT` | `false` | Abort if the probe fails |
| `REALITY_SELF_TEST` | `true` | End-to-end local Reality test |
| `REALITY_SELF_TEST_URL` | `http://example.com` | Self-test fetch URL |
| `REALITY_SELF_TEST_TIMEOUT` | `10` | Self-test timeout (s) |
| `REALITY_SELF_TEST_SOCKS_PORT` | `10808` | Preferred local SOCKS port |
| `REALITY_AUTO_FALLBACK` | `true` | Try candidates on self-test failure |
| `REALITY_TARGET_CANDIDATES` | _(5 defaults)_ | `dest|serverName|fingerprint` list |

## DNS profile (Clash YAML)

| Variable | Default | Values |
|---|---|---|
| `DNS_PROFILE` | `mixed` | `mixed`, `foreign`, `domestic`, `minimal`, `auto` |
| `SERVER_COUNTRY` | _(detected)_ | Override country for `auto` |
| `AUTO_DNS_DOMESTIC_COUNTRIES` | `CN` | Countries treated as domestic for `auto` |

Aliases: `global`/`world`/`overseas` → `foreign`; `return`/`home`/`backhome`
→ `domestic`; `cn`/`china` → `mixed`.

## HTTP subscription

| Variable | Default | Purpose |
|---|---|---|
| `ENABLE_SUBSCRIPTION` | `true` | Host subscription files via nginx |
| `SUB_PORT` | `8080` | Subscription HTTP port (must differ from `PORT`) |
| `SUB_TOKEN` | _(random 24-byte hex)_ | Subscription path token |
| `RESET_SUB_TOKEN` | `false` | Regenerate the token |
| `SUB_RATE_LIMIT` | `30r/m` | nginx `limit_req` rate |
| `SUB_RATE_BURST` | `10` | nginx `limit_req` burst |

## Health check timer

| Variable | Default |
|---|---|
| `ENABLE_HEALTHCHECK_TIMER` | `true` |
| `RAYLINK_CLI` | `/usr/local/bin/raylink` |
| `HEALTHCHECK_ENV_FILE` | `/etc/raylink-terminal-healthcheck.env` |
| `HEALTHCHECK_ON_BOOT_SEC` | `10min` |
| `HEALTHCHECK_ON_UNIT_ACTIVE_SEC` | `24h` |

## Installer (bootstrap) variables

These affect `install.sh`, not the node itself:

| Variable | Default | Purpose |
|---|---|---|
| `RAYLINK_REPO` | `vanillartwork/raylink` | GitHub `owner/repo` |
| `RAYLINK_REF` | `main` | Branch/tag to download |
| `RAYLINK_TARBALL_URL` | _(empty)_ | Explicit release tarball URL |
| `RAYLINK_LIB_DIR` | `/usr/local/lib/raylink` | Install location |
| `RAYLINK_BIN_LINK` | `/usr/local/bin/raylink` | CLI symlink |
