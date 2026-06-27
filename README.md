# RayLink

[English](#english) | [中文说明](#中文说明)

---

# English

RayLink is a script for one-click deployment of a personal Xray VPN node on a Linux server.

This README covers the terminal node installer:

```text
terminal.sh
```

The script installs Xray, creates a systemd service, generates persistent VLESS Reality credentials, optionally publishes subscription files through nginx, and runs a local Reality self-test before printing the client import information.

Use this project only for legal and compliant network access. Cloud servers and data transfer may incur charges.

## Default settings

| Item | Default |
|---|---|
| Xray protocol | VLESS Reality |
| Transport | TCP |
| Node port | `443` |
| HTTP subscription | Yes, enabled by default |
| Subscription port | `8080` |
| Install directory | `/opt/cloud-xray-terminal` |
| Xray config | `/usr/local/etc/xray/config.json` |
| Xray service | `xray.service` |
| Service user | `xray:xray` |
| TCP Fast Open | No, disabled by default |
| Reality self-test | Yes, enabled by default |

Traffic path:

```text
Client
→ server public IPv4:443
→ Xray VLESS Reality inbound
→ server direct outbound
→ Internet
```

## Server preparation

You can use AWS EC2, Google Cloud, Oracle Cloud, Azure, or a normal VPS provider. The server should have a public IPv4 address and allow SSH access.

### Example: AWS EC2

Recommended AMI:

```text
Ubuntu Server 24.04 LTS or Ubuntu Server 26.04 LTS
```

Recommended instance type for light personal use:

```text
t3.micro
```

When creating the instance, create or select an SSH key pair. For Windows CMD examples in this README, a `.pem` key is assumed.

### Security group / firewall

Open these inbound TCP ports:

| Type | Protocol | Port | Source | Purpose |
|---|---|---:|---|---|
| SSH | TCP | `22` | Your own IP | SSH login |
| Custom TCP | TCP | `443` | `0.0.0.0/0` | Xray VLESS Reality node |
| Custom TCP | TCP | `8080` | Your own IP if possible | HTTP subscription |

Notes:

- Reality over TCP does not need UDP `443`.
- The subscription URL contains your client configuration. Do not publish it.
- If your client device is on a mobile network and the IP changes often, you may temporarily allow TCP `8080` from `0.0.0.0/0`, import the subscription, then restrict it again or disable subscription hosting.
- If you change `PORT` or `SUB_PORT`, update the firewall/security group accordingly.

## SSH into the server

This README uses Windows CMD examples.

Open CMD and go to the folder where your `.pem` key is saved. For example:

```cmd
cd %USERPROFILE%\Downloads
```

Use this format:

```cmd
ssh -i [KEY_FILE] [USERNAME]@[SERVER_PUBLIC_IP]
```

Example:

```cmd
ssh -i key.pem ubuntu@192.168.1.1
```

For Ubuntu cloud images, the default username is usually:

```text
ubuntu
```

Other providers may use `root`, `debian`, `admin`, or another username shown in their control panel.

## One-line installation

Run this command on the Linux server:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo bash
```

After installation, the script prints the server information and subscription URLs.

## Import into clients

If HTTP subscription is enabled, the script prints URLs like these:

```text
Universal URI-list:
http://SERVER_IP:8080/sub/TOKEN

Mihomo / Clash Meta:
http://SERVER_IP:8080/sub/TOKEN/clash.yaml

VLESS URI-list:
http://SERVER_IP:8080/sub/TOKEN/vless
```

Use:

| Client type | Recommended import |
|---|---|
| Mihomo / Clash Meta / FlClash / Clash Verge Rev | `.../clash.yaml` |
| Shadowrocket / v2rayN / v2rayNG / Hiddify | Universal URI-list or direct VLESS link |

For Clash/Mihomo clients, import the `clash.yaml` URL, then select:

```text
GLOBAL → Terminal-Reality
```

Then enable system proxy or TUN mode in the client.

To view the direct VLESS link on the server:

```bash
sudo cat /opt/cloud-xray-terminal/vless-uri.txt
```

## Generated files

The script writes generated files under:

```text
/opt/cloud-xray-terminal
```

Common files:

```text
/opt/cloud-xray-terminal/server-info.txt
/opt/cloud-xray-terminal/clash.yaml
/opt/cloud-xray-terminal/vless-uri.txt
/opt/cloud-xray-terminal/vless-uri-list
/opt/cloud-xray-terminal/reality.env
/opt/cloud-xray-terminal/subscription.env
/opt/cloud-xray-terminal/public/
/usr/local/etc/xray/config.json
```

Useful commands:

```bash
sudo cat /opt/cloud-xray-terminal/server-info.txt
sudo cat /opt/cloud-xray-terminal/subscription.env
sudo cat /opt/cloud-xray-terminal/vless-uri.txt
sudo cat /opt/cloud-xray-terminal/clash.yaml
```

## Download generated config to your computer

From Windows CMD, download the generated Clash YAML to your Downloads folder:

```cmd
scp -i %USERPROFILE%\Downloads\[KEY_FILE].pem ubuntu@[SERVER_PUBLIC_IP]:/opt/cloud-xray-terminal/clash.yaml %USERPROFILE%\Downloads\raylink-clash.yaml
```

Example:

```cmd
scp -i %USERPROFILE%\Downloads\raylink-key.pem ubuntu@18.175.219.66:/opt/cloud-xray-terminal/clash.yaml %USERPROFILE%\Downloads\raylink-clash.yaml
```

You can also download the direct VLESS link file:

```cmd
scp -i %USERPROFILE%\Downloads\[KEY_FILE].pem ubuntu@[SERVER_PUBLIC_IP]:/opt/cloud-xray-terminal/vless-uri.txt %USERPROFILE%\Downloads\vless-uri.txt
```

## Common customization

Pass environment variables before `bash`:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo env KEY=value bash
```

### Custom node port

Example: use port `8443` instead of `443`:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo env PORT=8443 bash
```

Remember to open TCP `8443` in the firewall/security group.

### Disable HTTP subscription hosting

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo env ENABLE_SUBSCRIPTION=false bash
```

When subscription hosting is disabled, use the local files under `/opt/cloud-xray-terminal/` instead.

### Change subscription port

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo env SUB_PORT=18080 bash
```

Open TCP `18080` in the firewall/security group if you need remote subscription access.

### Choose a Reality target manually

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo env \
REALITY_DEST=www.cloudflare.com:443 \
REALITY_SERVER_NAME=www.cloudflare.com \
CLIENT_FINGERPRINT=chrome \
bash
```

## Reality self-test and fallback

Reality depends on a suitable TLS target. A target may pass a simple TLS check but still fail a real Reality handshake.

The script performs:

1. A basic TLS 1.3 probe against the selected target.
2. A local end-to-end Reality self-test by starting a temporary local Xray SOCKS client and connecting back to the local Reality inbound.

If the self-test fails and fallback is enabled, the script tries the configured target candidates and saves the first working one.

Default candidate format:

```text
dest|serverName|clientFingerprint
```

Default candidates:

```text
www.cloudflare.com:443|www.cloudflare.com|chrome
www.apple.com:443|www.apple.com|safari
addons.mozilla.org:443|addons.mozilla.org|firefox
www.speedtest.net:443|www.speedtest.net|chrome
www.microsoft.com:443|www.microsoft.com|chrome
```

Custom candidate list:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo env \
REALITY_TARGET_CANDIDATES='www.cloudflare.com:443|www.cloudflare.com|chrome www.apple.com:443|www.apple.com|safari' \
bash
```

Disable self-test only when you know what you are doing:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo env REALITY_SELF_TEST=false bash
```

## DNS profiles for generated Clash YAML

`DNS_PROFILE` controls the DNS section written into `clash.yaml`.

| Value | Use case |
|---|---|
| `mixed` | Default, general use |
| `foreign` | Mostly global/foreign websites |
| `domestic` | Mostly China-oriented access |
| `minimal` | Compatibility-first DNS config |
| `auto` | Legacy auto selection based on server country |

Example:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo env DNS_PROFILE=domestic bash
```

## Re-running the script

Re-running the script is safe. By default, it reuses existing values from `/opt/cloud-xray-terminal/reality.env` and `/opt/cloud-xray-terminal/subscription.env`.

It normally keeps:

- UUID
- Reality private/public key pair
- shortId
- Reality target
- client fingerprint
- subscription token

Regenerate Reality credentials:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo env RESET_REALITY_CREDENTIALS=true bash
```

Regenerate only the subscription token:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo env RESET_SUB_TOKEN=true bash
```

## Useful service commands

Check service status:

```bash
sudo systemctl status xray --no-pager
```

View recent logs:

```bash
sudo journalctl -u xray -n 80 --no-pager
```

Restart Xray:

```bash
sudo systemctl restart xray
```

Check listening ports:

```bash
sudo ss -ltnp | grep -E ':(443|8080)'
```

Test the Xray config:

```bash
sudo /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
```

## Test port connectivity from Windows

From Windows CMD:

```cmd
powershell -Command "Test-NetConnection [SERVER_PUBLIC_IP] -Port 443"
powershell -Command "Test-NetConnection [SERVER_PUBLIC_IP] -Port 8080"
```

Example:

```cmd
powershell -Command "Test-NetConnection 18.175.219.66 -Port 443"
```

If `TcpTestSucceeded` is `False`, check:

- The server public IPv4 is correct.
- The firewall/security group allows the port.
- Xray is running.
- The script was run on the same server IP used by the client.

## Troubleshooting

### Client shows timeout

Check server status:

```bash
sudo systemctl is-active xray
sudo ss -ltnp | grep -E ':(443|8080)'
sudo /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
```

If TCP `443` is not reachable from your computer, fix the cloud firewall/security group first.

### Subscription URL cannot open

Check whether subscription hosting is enabled:

```bash
sudo cat /opt/cloud-xray-terminal/subscription.env
sudo systemctl status nginx --no-pager
sudo ss -ltnp | grep ':8080'
```

Also check that TCP `8080` is allowed by the cloud firewall/security group.

### Node worked before but suddenly fails

Reality targets can become unsuitable. Re-run the script and let the self-test/fallback select a working target:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo bash
```

Then update or re-import the subscription in your client.

### Public IP changed

If the server uses an auto-assigned public IP, the IP may change after stopping and starting the instance.

Check the cloud console for the current public IPv4 address. Re-run the script to regenerate subscriptions with the new IP:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo bash
```

To avoid this issue, use a static IP such as AWS Elastic IP or your provider's equivalent.

## Uninstall

Stop and disable Xray:

```bash
sudo systemctl disable --now xray
sudo rm -f /etc/systemd/system/xray.service
sudo systemctl daemon-reload
```

Remove generated files:

```bash
sudo rm -rf /opt/cloud-xray-terminal
sudo rm -rf /usr/local/etc/xray
```

Remove the script-managed nginx site if subscription hosting was enabled:

```bash
sudo rm -f /etc/nginx/sites-enabled/cloud-xray-terminal-subscription
sudo rm -f /etc/nginx/sites-available/cloud-xray-terminal-subscription
sudo systemctl reload nginx || true
```

The Xray binary is installed at `/usr/local/bin/xray`. Remove it only if you do not use it for anything else:

```bash
sudo rm -f /usr/local/bin/xray
```

## Security notes

Do not upload these files to a public repository:

```text
/opt/cloud-xray-terminal/reality.env
/opt/cloud-xray-terminal/subscription.env
/opt/cloud-xray-terminal/server-info.txt
/opt/cloud-xray-terminal/vless-uri.txt
/opt/cloud-xray-terminal/clash.yaml
*.pem
```

Recommended practices:

- Keep SSH port `22` limited to your own IP.
- Restrict or disable subscription port `8080` after importing the configuration.
- Do not share the subscription URL, VLESS link, UUID, Reality keys, or shortId.
- Watch your cloud billing and bandwidth usage.

## License

This project is released under the MIT License.

---

# 中文说明

RayLink 是一个用于在 Linux 服务器上一键部署 Xray 个人 VPN 节点的脚本。

本文档目前说明的是 terminal 节点部署脚本：

```text
terminal.sh
```

脚本会安装 Xray，创建 systemd 服务，生成并保存 VLESS Reality 连接参数，根据需要通过 nginx 提供订阅链接，并在输出客户端配置前执行本机 Reality 自测。

请仅用于合法、合规的网络访问。云服务器和流量可能产生费用，请注意账单。

## 默认配置

| 项目 | 默认值 |
|---|---|
| Xray 协议 | VLESS Reality |
| 传输方式 | TCP |
| 节点端口 | `443` |
| HTTP 订阅 | 是，默认开启 |
| 订阅端口 | `8080` |
| 安装目录 | `/opt/cloud-xray-terminal` |
| Xray 配置 | `/usr/local/etc/xray/config.json` |
| Xray 服务 | `xray.service` |
| 服务用户 | `xray:xray` |
| TCP Fast Open | 否，默认关闭 |
| Reality 本机自测 | 是，默认开启 |

流量路径：

```text
客户端
→ 服务器公网 IPv4:443
→ Xray VLESS Reality 入站
→ 服务器 direct 出站
→ 互联网
```

## 服务器准备

你可以使用 AWS EC2、Google Cloud、Oracle Cloud、Azure，或者普通 VPS 服务商。服务器需要有公网 IPv4，并且可以通过 SSH 登录。

### 示例：AWS EC2

推荐系统镜像：

```text
Ubuntu Server 24.04 LTS 或 Ubuntu Server 26.04 LTS
```

个人轻量使用可以选择：

```text
t3.micro
```

创建实例时需要创建或选择 SSH Key Pair。本文档的 Windows CMD 示例默认使用 `.pem` 私钥文件。

### 安全组 / 防火墙

需要开放以下入站 TCP 端口：

| 类型 | 协议 | 端口 | 来源 | 用途 |
|---|---|---:|---|---|
| SSH | TCP | `22` | 你的 IP | SSH 登录 |
| Custom TCP | TCP | `443` | `0.0.0.0/0` | Xray VLESS Reality 节点 |
| Custom TCP | TCP | `8080` | 尽量限制为你的 IP | HTTP 订阅 |

说明：

- Reality over TCP 不需要开放 UDP `443`。
- 订阅链接包含完整客户端配置，不要公开。
- 如果你的客户端在手机移动网络下使用，IP 经常变化，可以临时把 TCP `8080` 开给 `0.0.0.0/0`，导入完成后再限制来源，或者关闭订阅功能。
- 如果修改了 `PORT` 或 `SUB_PORT`，安全组/防火墙也要同步修改。

## SSH 登录服务器

本文档默认使用 Windows CMD。

打开 CMD，进入 `.pem` 私钥所在文件夹。例如私钥在 Downloads 文件夹：

```cmd
cd %USERPROFILE%\Downloads
```

使用下面的命令格式：

```cmd
ssh -i [KEY_FILE] [USERNAME]@[SERVER_PUBLIC_IP]
```

示例：

```cmd
ssh -i key.pem ubuntu@192.168.1.1
```

Ubuntu 云镜像默认用户名通常是：

```text
ubuntu
```

其他服务商可能是 `root`、`debian`、`admin`，或者控制台里显示的用户名。

## 一键安装

在 Linux 服务器上运行：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo bash
```

安装完成后，脚本会输出服务器信息和订阅链接。

## 导入客户端

如果 HTTP 订阅开启，脚本会输出类似下面的链接：

```text
Universal URI-list:
http://SERVER_IP:8080/sub/TOKEN

Mihomo / Clash Meta:
http://SERVER_IP:8080/sub/TOKEN/clash.yaml

VLESS URI-list:
http://SERVER_IP:8080/sub/TOKEN/vless
```

推荐这样导入：

| 客户端类型 | 推荐导入方式 |
|---|---|
| Mihomo / Clash Meta / FlClash / Clash Verge Rev | `.../clash.yaml` |
| Shadowrocket / v2rayN / v2rayNG / Hiddify | Universal URI-list 或直接 VLESS 链接 |

对于 Clash/Mihomo 类客户端，导入 `clash.yaml` 订阅后选择：

```text
GLOBAL → Terminal-Reality
```

然后在客户端里开启系统代理或 TUN 模式。

在服务器上查看直接 VLESS 链接：

```bash
sudo cat /opt/cloud-xray-terminal/vless-uri.txt
```

## 生成的文件

脚本生成的文件位于：

```text
/opt/cloud-xray-terminal
```

常见文件：

```text
/opt/cloud-xray-terminal/server-info.txt
/opt/cloud-xray-terminal/clash.yaml
/opt/cloud-xray-terminal/vless-uri.txt
/opt/cloud-xray-terminal/vless-uri-list
/opt/cloud-xray-terminal/reality.env
/opt/cloud-xray-terminal/subscription.env
/opt/cloud-xray-terminal/public/
/usr/local/etc/xray/config.json
```

常用查看命令：

```bash
sudo cat /opt/cloud-xray-terminal/server-info.txt
sudo cat /opt/cloud-xray-terminal/subscription.env
sudo cat /opt/cloud-xray-terminal/vless-uri.txt
sudo cat /opt/cloud-xray-terminal/clash.yaml
```

## 下载配置到本机

在 Windows CMD 中，可以把生成的 Clash YAML 下载到 Downloads 文件夹：

```cmd
scp -i %USERPROFILE%\Downloads\[KEY_FILE].pem ubuntu@[SERVER_PUBLIC_IP]:/opt/cloud-xray-terminal/clash.yaml %USERPROFILE%\Downloads\raylink-clash.yaml
```

示例：

```cmd
scp -i %USERPROFILE%\Downloads\raylink-key.pem ubuntu@18.175.219.66:/opt/cloud-xray-terminal/clash.yaml %USERPROFILE%\Downloads\raylink-clash.yaml
```

也可以下载直接 VLESS 链接文件：

```cmd
scp -i %USERPROFILE%\Downloads\[KEY_FILE].pem ubuntu@[SERVER_PUBLIC_IP]:/opt/cloud-xray-terminal/vless-uri.txt %USERPROFILE%\Downloads\vless-uri.txt
```

## 部署时的常用自定义参数

在 `bash` 前通过环境变量传参：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo env KEY=value bash
```

### 自定义节点端口

例如使用 `8443` 端口：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo env PORT=8443 bash
```

记得在安全组/防火墙里开放 TCP `8443`。

### 关闭 HTTP 订阅

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo env ENABLE_SUBSCRIPTION=false bash
```

关闭订阅后，可以使用 `/opt/cloud-xray-terminal/` 里的本地配置文件。

### 修改订阅端口

例如使用 `18080` 端口：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo env SUB_PORT=18080 bash
```

如果需要远程访问订阅链接，记得开放 TCP `18080`。

### 手动指定 Reality target

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo env \
REALITY_DEST=www.cloudflare.com:443 \
REALITY_SERVER_NAME=www.cloudflare.com \
CLIENT_FINGERPRINT=chrome \
bash
```

## Reality 自测和 fallback

Reality 依赖合适的 TLS target。有些 target 可以通过简单 TLS 检查，但真实 Reality 握手仍然失败。

脚本会执行：

1. 对当前 target 做基础 TLS 1.3 检查。
2. 启动一个临时本地 Xray SOCKS 客户端，连接回本机 Reality 入站，做端到端 Reality 自测。

如果自测失败并且 fallback 开启，脚本会尝试候选 target，并保存第一个可用的 target。

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

自定义候选列表：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo env \
REALITY_TARGET_CANDIDATES='www.cloudflare.com:443|www.cloudflare.com|chrome www.apple.com:443|www.apple.com|safari' \
bash
```

只有你明确知道自己在做什么时，才建议关闭自测：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo env REALITY_SELF_TEST=false bash
```

## Clash YAML 的 DNS profile

`DNS_PROFILE` 会影响生成的 `clash.yaml` 里的 DNS 配置。

| 值 | 适用场景 |
|---|---|
| `mixed` | 默认，通用配置 |
| `foreign` | 主要访问海外/全球网站 |
| `domestic` | 主要访问中国方向服务 |
| `minimal` | 优先兼容性的 DNS 配置 |
| `auto` | 根据服务器国家选择的旧兼容模式 |

示例：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo env DNS_PROFILE=domestic bash
```

## 重新运行脚本

重复运行脚本是安全的。默认会复用 `/opt/cloud-xray-terminal/reality.env` 和 `/opt/cloud-xray-terminal/subscription.env` 里的已有参数。

通常会保持不变：

- UUID
- Reality 私钥/公钥
- shortId
- Reality target
- client fingerprint
- 订阅 token

重新生成 Reality 凭据：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo env RESET_REALITY_CREDENTIALS=true bash
```

只重新生成订阅 token：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo env RESET_SUB_TOKEN=true bash
```

## 常用服务命令

查看服务状态：

```bash
sudo systemctl status xray --no-pager
```

查看最近日志：

```bash
sudo journalctl -u xray -n 80 --no-pager
```

重启 Xray：

```bash
sudo systemctl restart xray
```

检查监听端口：

```bash
sudo ss -ltnp | grep -E ':(443|8080)'
```

测试 Xray 配置：

```bash
sudo /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
```

## 在 Windows 上测试端口连通性

在 Windows CMD 中运行：

```cmd
powershell -Command "Test-NetConnection [SERVER_PUBLIC_IP] -Port 443"
powershell -Command "Test-NetConnection [SERVER_PUBLIC_IP] -Port 8080"
```

示例：

```cmd
powershell -Command "Test-NetConnection 18.175.219.66 -Port 443"
```

如果 `TcpTestSucceeded` 是 `False`，检查：

- 服务器公网 IP 是否正确。
- 安全组/防火墙是否开放端口。
- Xray 是否正在运行。
- 客户端使用的 IP 是否和脚本生成配置里的 IP 一致。

## 排错

### 客户端显示 timeout

先在服务器上检查：

```bash
sudo systemctl is-active xray
sudo ss -ltnp | grep -E ':(443|8080)'
sudo /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
```

如果你的电脑无法连接 TCP `443`，先检查云平台安全组/防火墙。

### 订阅链接打不开

检查订阅配置和 nginx：

```bash
sudo cat /opt/cloud-xray-terminal/subscription.env
sudo systemctl status nginx --no-pager
sudo ss -ltnp | grep ':8080'
```

同时检查云平台安全组/防火墙是否允许 TCP `8080`。

### 节点之前能用，突然失效

Reality target 可能变得不适合。重新运行脚本，让自测/fallback 自动选择可用 target：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo bash
```

然后在客户端里更新或重新导入订阅。

### 公网 IP 变化

如果服务器使用自动分配公网 IP，停止再启动实例后公网 IP 可能变化。

在云平台控制台确认当前 Public IPv4，然后重新运行脚本生成新订阅：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo bash
```

为了避免这个问题，可以使用 AWS Elastic IP 或对应云服务商的静态 IP。

## 卸载

停止并禁用 Xray：

```bash
sudo systemctl disable --now xray
sudo rm -f /etc/systemd/system/xray.service
sudo systemctl daemon-reload
```

删除生成文件：

```bash
sudo rm -rf /opt/cloud-xray-terminal
sudo rm -rf /usr/local/etc/xray
```

如果启用了订阅，删除脚本管理的 nginx 配置：

```bash
sudo rm -f /etc/nginx/sites-enabled/cloud-xray-terminal-subscription
sudo rm -f /etc/nginx/sites-available/cloud-xray-terminal-subscription
sudo systemctl reload nginx || true
```

Xray 二进制文件安装在 `/usr/local/bin/xray`。只有确认不再使用它时再删除：

```bash
sudo rm -f /usr/local/bin/xray
```

## 安全提醒

不要把以下文件上传到公开仓库：

```text
/opt/cloud-xray-terminal/reality.env
/opt/cloud-xray-terminal/subscription.env
/opt/cloud-xray-terminal/server-info.txt
/opt/cloud-xray-terminal/vless-uri.txt
/opt/cloud-xray-terminal/clash.yaml
*.pem
```

建议：

- SSH `22` 端口只允许你自己的 IP。
- 导入配置后，限制或关闭订阅端口 `8080`。
- 不要分享订阅链接、VLESS 链接、UUID、Reality key 或 shortId。
- 注意云服务器账单和流量使用。

## License

This project is released under the MIT License.
