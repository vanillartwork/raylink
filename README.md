# RayLink

[English](#english) | [中文](#中文)

---

# English

RayLink is a small one-script deployment helper for a personal Xray VLESS Reality terminal node.

It installs Xray on a Linux VPS, writes a systemd service, generates persistent VLESS Reality credentials, creates client subscriptions, and runs an end-to-end Reality self-test before publishing the generated client configuration.

Use it only for legal and compliant network access. Cloud servers and data transfer may incur charges.

## What it deploys

Default deployment:

| Item | Default |
|---|---|
| Protocol | VLESS Reality |
| Transport | TCP |
| Server port | `443` |
| Subscription port | `8080` |
| Xray service user | `xray:xray` |
| Install directory | `/opt/cloud-xray-terminal` |
| Xray config | `/usr/local/etc/xray/config.json` |
| Client config | Mihomo/Clash YAML and base64 URI-list |
| Reality target | Automatically self-tested, default starts with `www.cloudflare.com:443` |
| TCP Fast Open | Disabled by default |

Traffic path:

```text
Client
→ VPS public IP:443
→ Xray VLESS Reality inbound
→ VPS direct outbound
→ Internet
```

## Requirements

Recommended server environment:

- Ubuntu 22.04 / 24.04 / 26.04 or a Debian-like system with `apt` and `systemd`
- Root access through `sudo`
- A public IPv4 address
- Cloud firewall/security group access

This script is designed for normal VPS providers, AWS EC2, Google Cloud, Oracle Cloud, Azure, and similar Linux servers. It is not designed for OpenWrt directly.

## Firewall rules

Open these inbound TCP ports:

| Port | Protocol | Purpose | Recommended source |
|---:|---|---|---|
| `22` | TCP | SSH | Your own IP |
| `443` | TCP | VLESS Reality node | `0.0.0.0/0` |
| `8080` | TCP | HTTP subscription | Your own IP if possible |

Notes:

- Reality over TCP does not need UDP `443`.
- The subscription URL contains your full client configuration. Do not publish it.
- Long-term, restrict TCP `8080` to your own IP or disable subscription hosting after importing the config.

## Quick install

SSH into the server, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo bash
```

After installation, the script prints two subscription URLs:

```text
Universal URI-list:
http://SERVER_IP:8080/sub/TOKEN

Mihomo / Clash Meta:
http://SERVER_IP:8080/sub/TOKEN/clash.yaml
```

Use the `clash.yaml` URL for Mihomo/Clash-based clients. Use the universal URI-list URL for clients such as v2rayN, v2rayNG, Hiddify, and Shadowrocket when supported.

## Client import

### Mihomo / Clash Meta / FlClash / Clash Verge Rev

Import this URL:

```text
http://SERVER_IP:8080/sub/TOKEN/clash.yaml
```

Then select:

```text
GLOBAL → Terminal-Reality
```

Enable system proxy or TUN mode in your client.

### Shadowrocket / v2rayN / v2rayNG / Hiddify

Import the universal URI-list URL:

```text
http://SERVER_IP:8080/sub/TOKEN
```

You can also copy the direct VLESS link from the server:

```bash
sudo cat /opt/cloud-xray-terminal/vless-uri.txt
```

The direct link is useful for troubleshooting, but the subscription URLs are easier to update.

## Generated files

After installation, files are saved here:

```text
/opt/cloud-xray-terminal/server-info.txt
/opt/cloud-xray-terminal/clash.yaml
/opt/cloud-xray-terminal/vless-uri.txt
/opt/cloud-xray-terminal/vless-uri-list
/opt/cloud-xray-terminal/reality.env
/opt/cloud-xray-terminal/subscription.env
/usr/local/etc/xray/config.json
```

Useful commands:

```bash
sudo cat /opt/cloud-xray-terminal/server-info.txt
sudo cat /opt/cloud-xray-terminal/subscription.env
sudo cat /opt/cloud-xray-terminal/vless-uri.txt
sudo cat /opt/cloud-xray-terminal/clash.yaml
```

## Re-running the script

Re-running the script is safe. By default it reuses:

- UUID
- Reality private/public key pair
- shortId
- Reality target
- client fingerprint
- subscription token

This keeps existing client subscriptions stable unless you explicitly reset them.

To regenerate Reality credentials:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo env RESET_REALITY_CREDENTIALS=true bash
```

To regenerate only the subscription token:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo env RESET_SUB_TOKEN=true bash
```

## Reality target self-test and fallback

Reality depends on a suitable TLS target. A target may pass a simple TLS check but still fail real Reality handshakes.

The script performs two checks:

1. A basic TLS 1.3 probe against the selected target.
2. An end-to-end local Reality self-test by starting a temporary local Xray SOCKS client and connecting back to the local Reality inbound.

If the self-test fails and fallback is enabled, the script tries the configured candidate list and saves the first working target.

Default candidate format:

```text
dest|serverName|clientFingerprint
```

Default candidate list:

```text
www.cloudflare.com:443|www.cloudflare.com|chrome
www.apple.com:443|www.apple.com|safari
addons.mozilla.org:443|addons.mozilla.org|firefox
www.speedtest.net:443|www.speedtest.net|chrome
www.microsoft.com:443|www.microsoft.com|chrome
```

Manually choose a target:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo env \
REALITY_DEST=www.cloudflare.com:443 \
REALITY_SERVER_NAME=www.cloudflare.com \
CLIENT_FINGERPRINT=chrome \
bash
```

Custom candidate list:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo env \
REALITY_TARGET_CANDIDATES='www.cloudflare.com:443|www.cloudflare.com|chrome www.apple.com:443|www.apple.com|safari' \
bash
```

Disable self-test only when you know what you are doing:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo env REALITY_SELF_TEST=false bash
```

## Common options

Use environment variables before `bash`:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo env KEY=value bash
```

| Variable | Default | Meaning |
|---|---|---|
| `PORT` | `443` | Xray Reality inbound port |
| `SUB_PORT` | `8080` | HTTP subscription port |
| `NODE_NAME` | `Terminal-Reality` | Client node name |
| `ENABLE_SUBSCRIPTION` | `true` | Enable nginx subscription hosting |
| `ENABLE_TFO` | `false` | Enable TCP Fast Open in Xray and generated client config |
| `DNS_PROFILE` | `mixed` | DNS profile for generated Mihomo/Clash YAML |
| `REALITY_DEST` | auto/default | Reality target, such as `www.cloudflare.com:443` |
| `REALITY_SERVER_NAME` | target host | Reality SNI/serverName |
| `CLIENT_FINGERPRINT` | `chrome` by default pool | Client fingerprint used by generated config |
| `REALITY_SELF_TEST` | `true` | Run local end-to-end Reality self-test |
| `REALITY_AUTO_FALLBACK` | `true` | Try fallback targets when self-test fails |
| `RESET_REALITY_CREDENTIALS` | `false` | Regenerate UUID/key/shortId |
| `RESET_SUB_TOKEN` | `false` | Regenerate subscription token |
| `PUBLIC_IP` | auto-detected | Override public IPv4 detection |

Examples:

Custom port:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo env PORT=8443 bash
```

Disable HTTP subscription hosting:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo env ENABLE_SUBSCRIPTION=false bash
```

Use a domestic DNS profile in generated Mihomo config:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo env DNS_PROFILE=domestic bash
```

## DNS profiles

The DNS profile only affects the generated Mihomo/Clash YAML.

| Profile | Use case |
|---|---|
| `mixed` | Default general-purpose profile |
| `foreign` | Mostly global/overseas sites |
| `domestic` | China-oriented or return-home style usage |
| `minimal` | Compatibility-first redir-host DNS |
| `auto` | Selects domestic/foreign based on server country list |

If a Clash/Mihomo client imports successfully but Global mode cannot open websites, try:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo env DNS_PROFILE=domestic bash
```

Then delete the old profile in the client and import the new subscription again.

## Useful server commands

Check service status:

```bash
sudo systemctl status xray --no-pager
sudo systemctl status nginx --no-pager
```

Check listening ports:

```bash
sudo ss -ltnp | grep -E ':(443|8080)'
```

Test Xray config:

```bash
sudo /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
```

View logs:

```bash
sudo journalctl -u xray -n 100 --no-pager
sudo journalctl -u nginx -n 100 --no-pager
```

Follow Xray logs:

```bash
sudo journalctl -u xray -f
```

## Troubleshooting

### Client shows timeout

Check the server first:

```bash
sudo systemctl is-active xray
sudo ss -ltnp | grep ':443'
sudo /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
```

From Windows PowerShell:

```powershell
Test-NetConnection SERVER_IP -Port 443
```

If TCP `443` is not reachable, check cloud firewall/security group rules and the server public IP.

### Subscription URL cannot be opened

Check nginx and port `8080`:

```bash
sudo systemctl is-active nginx
sudo ss -ltnp | grep ':8080'
sudo cat /opt/cloud-xray-terminal/subscription.env
```

Make sure TCP `8080` is allowed by the cloud firewall if you want to access subscriptions from outside.

### It worked before but suddenly fails

Reality targets can become unsuitable over time. Re-run the script. It will self-test the saved target and try fallback targets if needed:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo bash
```

If needed, manually choose a known working target:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo env \
REALITY_DEST=www.cloudflare.com:443 \
REALITY_SERVER_NAME=www.cloudflare.com \
CLIENT_FINGERPRINT=chrome \
bash
```

### Imported node works in one client but not another

Check whether the client supports:

```text
VLESS
Reality
XTLS Vision / flow=xtls-rprx-vision
uTLS / client fingerprint
```

For Mihomo/Clash-based clients, use the `/clash.yaml` subscription.

For clients that support URI-list imports, use `/sub/TOKEN`.

### Server IP changed

If the VPS public IP changes, re-run the script so the generated subscription points to the new IP:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo bash
```

Then update or re-import the client subscription.

## Uninstall

Stop and remove the Xray service and generated files:

```bash
sudo systemctl disable --now xray 2>/dev/null || true
sudo rm -f /etc/systemd/system/xray.service
sudo rm -rf /opt/cloud-xray-terminal
sudo rm -f /usr/local/etc/xray/config.json
sudo systemctl daemon-reload
```

Remove the managed nginx subscription site:

```bash
sudo rm -f /etc/nginx/sites-enabled/cloud-xray-terminal-subscription
sudo rm -f /etc/nginx/sites-available/cloud-xray-terminal-subscription
sudo nginx -t && sudo systemctl reload nginx
```

The commands above do not uninstall nginx or the Xray binary in `/usr/local/bin/xray`.

## Security notes

- Keep SSH port `22` restricted to your own IP.
- Do not share `server-info.txt`, `reality.env`, `subscription.env`, or the subscription URLs publicly.
- The HTTP subscription contains your complete client configuration.
- Restrict TCP `8080` when possible.
- Do not commit generated server files, keys, or subscriptions to GitHub.

## License

MIT License.

---

# 中文

RayLink 是一个用于个人 Linux VPS 的 Xray VLESS Reality terminal 节点部署脚本。

它会安装 Xray，写入 systemd 服务，生成持久化 VLESS Reality 参数，创建客户端订阅，并在输出订阅前执行端到端 Reality 自测。

请仅用于合法、合规的网络访问。云服务器和流量可能产生费用。

## 部署内容

默认部署：

| 项目 | 默认值 |
|---|---|
| 协议 | VLESS Reality |
| 传输 | TCP |
| 节点端口 | `443` |
| 订阅端口 | `8080` |
| Xray 服务用户 | `xray:xray` |
| 安装目录 | `/opt/cloud-xray-terminal` |
| Xray 配置 | `/usr/local/etc/xray/config.json` |
| 客户端配置 | Mihomo/Clash YAML 和 Base64 URI-list |
| Reality target | 自动自测，默认从 `www.cloudflare.com:443` 开始 |
| TCP Fast Open | 默认关闭 |

流量路径：

```text
客户端
→ VPS 公网 IP:443
→ Xray VLESS Reality 入站
→ VPS 直连出站
→ Internet
```

## 环境要求

推荐环境：

- Ubuntu 22.04 / 24.04 / 26.04，或带 `apt` 和 `systemd` 的 Debian-like 系统
- 可使用 `sudo`
- 有公网 IPv4
- 可以修改云防火墙或安全组

这个脚本适合普通 VPS、AWS EC2、Google Cloud、Oracle Cloud、Azure 等 Linux 服务器。不适合直接跑在 OpenWrt 上。

## 防火墙 / 安全组

需要开放这些 TCP 入站端口：

| 端口 | 协议 | 用途 | 建议来源 |
|---:|---|---|---|
| `22` | TCP | SSH | 你的 IP |
| `443` | TCP | VLESS Reality 节点 | `0.0.0.0/0` |
| `8080` | TCP | HTTP 订阅 | 尽量只允许你的 IP |

说明：

- Reality over TCP 不需要 UDP `443`。
- 订阅 URL 包含完整客户端配置，不要公开。
- 长期使用建议限制 TCP `8080` 来源 IP，或导入客户端后关闭订阅服务。

## 一键安装

SSH 登录服务器后运行：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo bash
```

安装完成后会输出两个订阅 URL：

```text
Universal URI-list:
http://SERVER_IP:8080/sub/TOKEN

Mihomo / Clash Meta:
http://SERVER_IP:8080/sub/TOKEN/clash.yaml
```

Mihomo/Clash 类客户端使用 `/clash.yaml`。v2rayN、v2rayNG、Hiddify、Shadowrocket 等客户端可尝试使用通用 URI-list。

## 客户端导入

### Mihomo / Clash Meta / FlClash / Clash Verge Rev

导入这个 URL：

```text
http://SERVER_IP:8080/sub/TOKEN/clash.yaml
```

然后选择：

```text
GLOBAL → Terminal-Reality
```

并开启系统代理或 TUN 模式。

### Shadowrocket / v2rayN / v2rayNG / Hiddify

导入通用 URI-list：

```text
http://SERVER_IP:8080/sub/TOKEN
```

也可以从服务器复制直连 VLESS 链接：

```bash
sudo cat /opt/cloud-xray-terminal/vless-uri.txt
```

直连链接适合排错，日常使用订阅更方便更新。

## 生成文件

安装后会生成：

```text
/opt/cloud-xray-terminal/server-info.txt
/opt/cloud-xray-terminal/clash.yaml
/opt/cloud-xray-terminal/vless-uri.txt
/opt/cloud-xray-terminal/vless-uri-list
/opt/cloud-xray-terminal/reality.env
/opt/cloud-xray-terminal/subscription.env
/usr/local/etc/xray/config.json
```

常用查看命令：

```bash
sudo cat /opt/cloud-xray-terminal/server-info.txt
sudo cat /opt/cloud-xray-terminal/subscription.env
sudo cat /opt/cloud-xray-terminal/vless-uri.txt
sudo cat /opt/cloud-xray-terminal/clash.yaml
```

## 重跑脚本

重复运行脚本是安全的。默认会复用：

- UUID
- Reality 私钥/公钥
- shortId
- Reality target
- 客户端 fingerprint
- 订阅 token

这样旧客户端订阅不会因为重跑脚本而失效，除非你主动重置。

重新生成 Reality 凭据：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo env RESET_REALITY_CREDENTIALS=true bash
```

只重新生成订阅 token：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo env RESET_SUB_TOKEN=true bash
```

## Reality target 自测和自动切换

Reality 依赖合适的 TLS target。有些 target 可以通过普通 TLS 检查，但实际 Reality 握手会失败。

脚本会做两层检查：

1. 用 `openssl` 检查目标是否支持 TLS 1.3。
2. 启动临时本地 Xray SOCKS 客户端，连接回本机 Reality 入站，做端到端自测。

如果自测失败并且 fallback 开启，脚本会尝试候选 target，并保存第一个可用的组合。

候选格式：

```text
dest|serverName|clientFingerprint
```

默认候选：

```text
www.cloudflare.com:443|www.cloudflare.com|chrome
www.apple.com:443|www.apple.com|safari
addons.mozilla.org:443|addons.mozilla.org|firefox
www.speedtest.net:443|www.speedtest.net|chrome
www.microsoft.com:443|www.microsoft.com|chrome
```

手动指定 target：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo env \
REALITY_DEST=www.cloudflare.com:443 \
REALITY_SERVER_NAME=www.cloudflare.com \
CLIENT_FINGERPRINT=chrome \
bash
```

自定义候选列表：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo env \
REALITY_TARGET_CANDIDATES='www.cloudflare.com:443|www.cloudflare.com|chrome www.apple.com:443|www.apple.com|safari' \
bash
```

仅在明确知道原因时关闭自测：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo env REALITY_SELF_TEST=false bash
```

## 常用参数

环境变量写在 `bash` 前面：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo env KEY=value bash
```

| 参数 | 默认值 | 说明 |
|---|---|---|
| `PORT` | `443` | Xray Reality 入站端口 |
| `SUB_PORT` | `8080` | HTTP 订阅端口 |
| `NODE_NAME` | `Terminal-Reality` | 客户端节点名称 |
| `ENABLE_SUBSCRIPTION` | `true` | 是否启用 nginx 订阅服务 |
| `ENABLE_TFO` | `false` | 是否在 Xray 和生成的客户端配置中启用 TCP Fast Open |
| `DNS_PROFILE` | `mixed` | 生成 Mihomo/Clash YAML 时使用的 DNS 配置 |
| `REALITY_DEST` | 自动/默认 | Reality target，例如 `www.cloudflare.com:443` |
| `REALITY_SERVER_NAME` | target 主机名 | Reality SNI/serverName |
| `CLIENT_FINGERPRINT` | 默认从 `chrome` 开始 | 客户端 fingerprint |
| `REALITY_SELF_TEST` | `true` | 是否执行本地端到端 Reality 自测 |
| `REALITY_AUTO_FALLBACK` | `true` | 自测失败时是否尝试候选 target |
| `RESET_REALITY_CREDENTIALS` | `false` | 是否重新生成 UUID/key/shortId |
| `RESET_SUB_TOKEN` | `false` | 是否重新生成订阅 token |
| `PUBLIC_IP` | 自动检测 | 手动指定公网 IPv4 |

示例：

自定义节点端口：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo env PORT=8443 bash
```

关闭 HTTP 订阅：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo env ENABLE_SUBSCRIPTION=false bash
```

生成更偏国内解析的 Mihomo 配置：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo env DNS_PROFILE=domestic bash
```

## DNS 配置

DNS profile 只影响生成的 Mihomo/Clash YAML。

| Profile | 适用场景 |
|---|---|
| `mixed` | 默认通用配置 |
| `foreign` | 主要访问海外网站 |
| `domestic` | 回国/主要访问中国网站 |
| `minimal` | 兼容优先的 redir-host 配置 |
| `auto` | 根据服务器国家列表选择 domestic 或 foreign |

如果 Clash/Mihomo 能导入节点，但 Global 后网页打不开，可以试：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo env DNS_PROFILE=domestic bash
```

然后删除客户端旧 profile，重新导入新订阅。

## 常用服务器命令

检查服务：

```bash
sudo systemctl status xray --no-pager
sudo systemctl status nginx --no-pager
```

检查端口：

```bash
sudo ss -ltnp | grep -E ':(443|8080)'
```

测试 Xray 配置：

```bash
sudo /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
```

查看日志：

```bash
sudo journalctl -u xray -n 100 --no-pager
sudo journalctl -u nginx -n 100 --no-pager
```

实时查看 Xray 日志：

```bash
sudo journalctl -u xray -f
```

## 排错

### 客户端显示 timeout

先在服务器检查：

```bash
sudo systemctl is-active xray
sudo ss -ltnp | grep ':443'
sudo /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
```

Windows PowerShell 测试：

```powershell
Test-NetConnection SERVER_IP -Port 443
```

如果 TCP `443` 不通，检查云防火墙/安全组和服务器公网 IP。

### 订阅 URL 打不开

检查 nginx 和 `8080`：

```bash
sudo systemctl is-active nginx
sudo ss -ltnp | grep ':8080'
sudo cat /opt/cloud-xray-terminal/subscription.env
```

如果要从外部访问订阅，确认云防火墙允许 TCP `8080`。

### 之前能用，突然失效

Reality target 可能随时间变得不适合。重跑脚本，它会自测已保存 target，并在失败时尝试 fallback：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo bash
```

必要时手动指定已知可用 target：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo env \
REALITY_DEST=www.cloudflare.com:443 \
REALITY_SERVER_NAME=www.cloudflare.com \
CLIENT_FINGERPRINT=chrome \
bash
```

### 一个客户端能用，另一个不能用

检查客户端是否支持：

```text
VLESS
Reality
XTLS Vision / flow=xtls-rprx-vision
uTLS / client fingerprint
```

Mihomo/Clash 类客户端请用 `/clash.yaml` 订阅。

支持 URI-list 的客户端使用 `/sub/TOKEN`。

### 服务器公网 IP 变了

如果 VPS 公网 IP 改变，重跑脚本生成新的订阅：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal_realityv.sh | sudo bash
```

然后更新或重新导入客户端订阅。

## 卸载

停止并删除 Xray 服务和生成文件：

```bash
sudo systemctl disable --now xray 2>/dev/null || true
sudo rm -f /etc/systemd/system/xray.service
sudo rm -rf /opt/cloud-xray-terminal
sudo rm -f /usr/local/etc/xray/config.json
sudo systemctl daemon-reload
```

删除脚本管理的 nginx 订阅站点：

```bash
sudo rm -f /etc/nginx/sites-enabled/cloud-xray-terminal-subscription
sudo rm -f /etc/nginx/sites-available/cloud-xray-terminal-subscription
sudo nginx -t && sudo systemctl reload nginx
```

上面的命令不会卸载 nginx，也不会删除 `/usr/local/bin/xray`。

## 安全注意

- SSH `22` 端口尽量只允许自己的 IP。
- 不要公开 `server-info.txt`、`reality.env`、`subscription.env` 或订阅 URL。
- HTTP 订阅里包含完整客户端配置。
- 尽量限制 TCP `8080` 的来源 IP。
- 不要把服务器生成的密钥、订阅、配置文件提交到 GitHub。

## License

MIT License.
