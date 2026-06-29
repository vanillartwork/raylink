# Troubleshooting

## Client shows timeout

```bash
sudo systemctl is-active xray
sudo ss -ltnp | grep -E ':(443|8080)'
sudo /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
```

If TCP `443` is not reachable from your computer, fix the cloud
firewall/security group first.

## Subscription URL cannot open

```bash
sudo cat /opt/cloud-xray-terminal/subscription.env
sudo systemctl status nginx --no-pager
sudo ss -ltnp | grep ':8080'
```

Confirm TCP `8080` is allowed by the cloud firewall/security group.

## Node worked before but suddenly fails

Reality targets can become unsuitable. Re-run and let the self-test/fallback
pick a working target, then re-import the subscription in your client:

```bash
sudo raylink terminal
```

## Public IP changed

The health check regenerates local client and subscription files with the new
IP. Run it manually if needed:

```bash
sudo raylink terminal --health-check
```

If your client's subscription URL uses the old raw IP, update the IP part of
the URL in the client (the token stays the same). Use a static IP (e.g. AWS
Elastic IP) or a domain to avoid this.

## Relay: client connects but no internet

The relay inbound is fine but the relay→terminal hop or the terminal itself is
broken. Check, on the relay:

```bash
sudo systemctl status raylink-relay.service --no-pager
sudo journalctl -u raylink-relay.service -n 80 --no-pager
sudo cat /opt/cloud-xray-relay/upstream.env
sudo raylink relay --health-check
```

Then verify the terminal is reachable from the relay (`TERMINAL_IP` / port from
`upstream.env`) and that the terminal's firewall allows the relay's IP:

```bash
nc -vz TERMINAL_IP 443
```

If the terminal's public IP changed and `UPSTREAM_SUBSCRIPTION_URL` points at
the old IP, update it and re-run `sudo raylink relay`, or use a static
IP/domain for the terminal.

## Relay: upstream parameters incomplete

```text
Error: upstream terminal parameters are incomplete.
```

Provide upstream params via `UPSTREAM_SUBSCRIPTION_URL`, `UPSTREAM_VLESS_URI`,
or the individual `UPSTREAM_ADDRESS` / `UPSTREAM_UUID` / `UPSTREAM_PUBLIC_KEY`
(plus `UPSTREAM_SERVER_NAME` / `UPSTREAM_SHORT_ID`). See [relay.md](relay.md).

## Relay uninstall

```bash
sudo systemctl disable --now raylink-relay-healthcheck.timer 2>/dev/null || true
sudo rm -f /etc/systemd/system/raylink-relay-healthcheck.{timer,service}
sudo rm -f /etc/raylink-relay-healthcheck.env
sudo systemctl disable --now raylink-relay.service
sudo rm -f /etc/systemd/system/raylink-relay.service
sudo systemctl daemon-reload
sudo rm -rf /opt/cloud-xray-relay /usr/local/etc/raylink/relay-xray
sudo rm -f /etc/nginx/sites-enabled/cloud-xray-relay-subscription
sudo rm -f /etc/nginx/sites-available/cloud-xray-relay-subscription
sudo systemctl reload nginx || true
```

## IPv6-only server

The installer auto-detects IPv6 when no IPv4 is available (`PUBLIC_IP_VERSION=auto`).
If detection fails, set it explicitly:

```bash
sudo env PUBLIC_IP_VERSION=6 raylink terminal
# or pin the address:
sudo env PUBLIC_IP=2001:db8::1 raylink terminal
```

Then check that the generated links bracket the address
(`vless://uuid@[2001:db8::1]:443`, `http://[2001:db8::1]:8080/sub/TOKEN`) and
that nginx listens on `[::]`:

```bash
sudo ss -ltnp | grep -E ':(443|8080)'
sudo cat /opt/cloud-xray-terminal/vless-uri.txt
```

If a client can't connect: confirm the client itself has IPv6, and that the
cloud firewall allows inbound TCP 443/8080 over IPv6 (`::/0`). An IPv6-only
server without NAT64 cannot reach IPv4-only Reality targets — let the
self-test/fallback pick a dual-stack one (Cloudflare/Apple/Microsoft).

## envsubst / template errors

The CLI renders systemd/nginx/xray/clash configs from `templates/` via
`envsubst` (package `gettext-base`). It is installed automatically by the full
install. If you see "envsubst not found", install it:

```bash
sudo apt install -y gettext-base
```

## CLI not found after install

```bash
ls -l /usr/local/bin/raylink            # should symlink into /usr/local/lib/raylink/
sudo ln -sf /usr/local/lib/raylink/raylink /usr/local/bin/raylink   # repair link
```

## Reinstall / update the CLI

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/install.sh | sudo bash
```

This re-downloads the source tree into `/usr/local/lib/raylink/`. Node state in
`/opt/cloud-xray-terminal/` is untouched.

## Uninstall

```bash
sudo systemctl disable --now raylink-terminal-healthcheck.timer 2>/dev/null || true
sudo rm -f /etc/systemd/system/raylink-terminal-healthcheck.{timer,service}
sudo rm -f /etc/raylink-terminal-healthcheck.env

sudo systemctl disable --now xray
sudo rm -f /etc/systemd/system/xray.service
sudo systemctl daemon-reload

sudo rm -rf /opt/cloud-xray-terminal /usr/local/etc/xray
sudo rm -f /etc/nginx/sites-enabled/cloud-xray-terminal-subscription
sudo rm -f /etc/nginx/sites-available/cloud-xray-terminal-subscription
sudo systemctl reload nginx || true

sudo rm -rf /usr/local/lib/raylink /usr/local/bin/raylink
# Remove the Xray binary only if nothing else uses it:
sudo rm -f /usr/local/bin/xray
```
