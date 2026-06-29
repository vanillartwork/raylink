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
