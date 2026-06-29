# Terminal node

The terminal command installs an Xray VLESS Reality entry node, optionally
publishes subscription files through nginx, runs a local Reality self-test, and
installs a periodic health check timer.

## Install and run

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/install.sh | sudo bash -s -- terminal
```

Pass configuration through environment variables:

```bash
curl -fsSL .../install.sh | sudo env PORT=8443 ENABLE_SUBSCRIPTION=false bash -s -- terminal
```

After install, the CLI is available on the server:

```bash
sudo raylink terminal                 # re-run / update (safe, reuses saved state)
sudo raylink terminal --health-check  # lightweight health check
sudo raylink version
```

## What it does

The full install runs in 12 steps: install packages, apply TCP tuning (BBR),
prepare directories, detect public IPv4 and DNS profile, stop conflicting
services, install Xray-core, load or generate Reality credentials, check the
Reality target, write the Xray config and systemd unit, run the end-to-end
Reality self-test with fallback target selection, generate the Clash YAML and
VLESS URI-list subscription, and install the health check timer.

## Generated files

```text
/opt/cloud-xray-terminal/server-info.txt
/opt/cloud-xray-terminal/clash.yaml
/opt/cloud-xray-terminal/vless-uri.txt
/opt/cloud-xray-terminal/vless-uri-list
/opt/cloud-xray-terminal/reality.env
/opt/cloud-xray-terminal/subscription.env
/opt/cloud-xray-terminal/public/
/usr/local/etc/xray/config.json
/etc/raylink-terminal-healthcheck.env
/etc/systemd/system/raylink-terminal-healthcheck.service
/etc/systemd/system/raylink-terminal-healthcheck.timer
```

The RayLink CLI itself is installed under `/usr/local/lib/raylink/` and linked
at `/usr/local/bin/raylink`.

## Re-running is safe

Re-running reuses saved values from `reality.env` and `subscription.env`
(UUID, key pair, shortId, Reality target, fingerprint, subscription token).

```bash
sudo raylink terminal RESET_REALITY_CREDENTIALS=true   # regenerate Reality keys
sudo env RESET_SUB_TOKEN=true raylink terminal         # regenerate sub token only
```

## Health check

The timer runs `raylink terminal --health-check`. It does not reinstall Xray,
update apt, or reset credentials. It detects the current public IPv4, verifies
Xray, runs the Reality self-test, applies a fallback target if the current one
fails, and regenerates client/subscription files when needed.

```bash
sudo systemctl status raylink-terminal-healthcheck.timer --no-pager
sudo journalctl -u raylink-terminal-healthcheck.service -n 80 --no-pager
```
