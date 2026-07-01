# Getting started

This guide covers the parts shared by every node type: preparing a server,
connecting over SSH, importing the generated subscription into clients, and
downloading config to your computer. For node-specific install commands and
options, see [exit](exit.md) and [relay](relay.md).

## 1. Prepare a server

Any VPS with a public IP and SSH access works (AWS EC2, Google Cloud, Oracle
Cloud, Azure, …). Ubuntu Server (24.04+) is recommended; a small instance
is plenty for personal use. IPv6-only servers are supported (see
[configuration](configuration.md#public-ip-family--ipv6-only-servers)).

Open these inbound TCP ports in the cloud firewall / security group:

| Port | Source | Purpose |
|---|---|---|
| `22` | your IP | SSH |
| `443` | `0.0.0.0/0` (and `::/0` on IPv6) | the node (Xray VLESS Reality) |
| `8080` | your IP if possible | HTTP subscription (optional) |

Reality over TCP needs no UDP. The subscription URL contains your full client
config — do not publish it. For a relay, the exit's port is opened to the
relay's IP instead — see [relay](relay.md).

## 2. Connect via SSH

```bash
ssh -i key.pem ubuntu@SERVER_PUBLIC_IP
```

Ubuntu cloud images usually use the `ubuntu` user; other providers may use
`root`, `debian`, or `admin`.

## 3. Install a node

- **Exit** (entry/exit node): [exit](exit.md)
- **Relay** (forwards to an upstream exit): [relay](relay.md)

The installer prints your subscription URLs when it finishes (they are also
saved to `server-info.txt` in the install directory).

## 4. Import into clients

| Client | Import |
|---|---|
| Mihomo / Clash Meta / FlClash / Clash Verge Rev | the `…/sub/TOKEN/clash.yaml` URL |
| v2rayN / v2rayNG / Hiddify / Shadowrocket | the Universal URI-list URL (`…/sub/TOKEN`) or the direct VLESS link |

For Clash/Mihomo clients, import the `clash.yaml` URL, select your node under the
`GLOBAL` group, then enable system proxy or TUN mode. View the direct VLESS link
on the server (exit path shown; a relay uses `/opt/cloud-xray-relay`):

```bash
sudo cat /opt/cloud-xray-exit/vless-uri.txt
```

The Clash YAML and VLESS URI keep their own field names (`network: tcp`,
`reality-opts.public-key`, `type=tcp`, `pbk=…`). That is expected — do not rename
them to the Xray JSON field names.

## 5. Download config to your computer

```bash
scp -i key.pem ubuntu@SERVER_PUBLIC_IP:/opt/cloud-xray-exit/clash.yaml ./raylink-clash.yaml
scp -i key.pem ubuntu@SERVER_PUBLIC_IP:/opt/cloud-xray-exit/vless-uri.txt ./vless-uri.txt
```

## Next

- [exit.md](exit.md) / [relay.md](relay.md) — install and manage a node.
- [configuration.md](configuration.md) — every environment variable.
- [troubleshooting.md](troubleshooting.md) — common issues and uninstall.
