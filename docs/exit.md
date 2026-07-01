# Exit node

The exit command installs an Xray VLESS Reality entry node, optionally
publishes subscription files through nginx, runs a local Reality self-test, and
installs a periodic health check timer.

```text
Client → server public IP:443 → Xray VLESS Reality inbound → direct outbound → Internet
```

> New here? Start with [getting-started.md](getting-started.md) for server
> preparation, SSH, importing into clients, and downloading config — those steps
> are shared by all node types.

## Install and run

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/install.sh | sudo bash -s -- exit
```

Pass configuration through environment variables (full list in
[configuration.md](configuration.md)):

```bash
curl -fsSL .../install.sh | sudo env PORT=8443 ENABLE_SUBSCRIPTION=false bash -s -- exit
```

The installer prints your subscription URLs on completion (also saved to
`server-info.txt`). After install, the CLI manages the node:

```bash
sudo raylink exit                 # re-run / update (safe, reuses saved state)
sudo raylink exit --health-check  # lightweight health check
sudo raylink version
```

## What it does

The full install: installs packages, applies TCP tuning (BBR), detects the
public IP and DNS profile, installs Xray-core, loads or generates Reality
credentials, checks the Reality target, writes the Xray config and systemd unit,
runs the end-to-end Reality self-test with fallback target selection, generates
the Clash YAML and the universal subscription, and installs the health check
timer.

## Generated files

```text
/opt/cloud-xray-exit/server-info.txt
/opt/cloud-xray-exit/clash.yaml
/opt/cloud-xray-exit/vless-uri.txt
/opt/cloud-xray-exit/vless-uri-list
/opt/cloud-xray-exit/reality.env
/opt/cloud-xray-exit/subscription.env
/opt/cloud-xray-exit/public/
/usr/local/etc/xray/config.json
/etc/raylink-exit-healthcheck.env
/etc/systemd/system/raylink-exit-healthcheck.{service,timer}
```

The CLI itself lives under `/usr/local/lib/raylink/` and is linked at
`/usr/local/bin/raylink`.

## Re-running is safe

Re-running reuses saved values from `reality.env` and `subscription.env` (UUID,
key pair, shortId, Reality target, fingerprint, subscription token):

```bash
sudo env RESET_REALITY_CREDENTIALS=true raylink exit   # regenerate Reality keys
sudo env RESET_SUB_TOKEN=true raylink exit             # regenerate sub token only
```

## Health check

A systemd timer runs `raylink exit --health-check` (10 min after boot, then
every 24 h). It does not reinstall Xray, update apt, or reset credentials. It
re-detects the current public IP, verifies Xray, runs the Reality self-test,
applies a fallback target if the current one fails, and regenerates
client/subscription files when needed.

```bash
sudo systemctl status raylink-exit-healthcheck.timer --no-pager
sudo journalctl -u raylink-exit-healthcheck.service -n 80 --no-pager
```

## See also

- [getting-started.md](getting-started.md) — server prep, SSH, client import.
- [configuration.md](configuration.md) — every environment variable (ports,
  Reality target & candidates, DNS profiles, IPv6, metrics, downloads).
- [troubleshooting.md](troubleshooting.md) — common issues, IPv6, uninstall.
