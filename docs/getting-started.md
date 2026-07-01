# Getting Started

[English](#Guide) · [中文](#指南)

This guide takes you from a bare Linux server to a working node and imported
client. Every step here is shared by both node types — for node-specific options
see [exit](exit.md) and [relay](relay.md).

Examples use the documentation IP `203.0.113.10`; substitute your own server's
address throughout.

---

## Guide

### 1. Prerequisites

#### 1.1 Launch a server instance

You need a Linux server with a public IP address (IPv4 or IPv6) and SSH access.
Any provider works — AWS, Google Cloud, Oracle Cloud, Azure or other cloud
service provider. Ubuntu system is recommended, and a small instance is plenty
for personal use.

**Example: AWS EC2**

Recommended operating system:

```text
Ubuntu Server 26.04 LTS
```

Recommended instance type for personal use:

```text
t3.micro
```

When creating the instance:

- Create a new SSH key pair, or select an existing one (see [1.2](#12-create-an-ssh-key-pair)).
- Allow inbound TCP ports `22`, `443`, and `8080` in the security group (see [1.3](#13-configure-the-firewall)).
- Assign a public IPv4 (or IPv6) address.

Cloud platforms usually provide the private key as a `.pem` file to download once — keep it safe, as
it cannot be downloaded again.

#### 1.2 Create an SSH Key Pair

SSH uses a key pair to authenticate you to the server: a **private key** that
stays on your computer, and a **public key** that is placed on the server.

Some providers generate a key pair for you during instance creation (for example AWS gives
you a `.pem` private key to download). Others ask you to upload an existing
public key. If you do not have a key pair yet, generate one locally — the full
walkthrough is in [Appendix B](#b-ssh-key-generation).

By default, keys live in the `~/.ssh` directory with standard filenames that most
SSH clients pick up automatically:

| Algorithm | Private key | Public key |
|---|---|---|
| ED25519 | `id_ed25519` | `id_ed25519.pub` |
| RSA | `id_rsa` | `id_rsa.pub` |
| ECDSA | `id_ecdsa` | `id_ecdsa.pub` |

Only the `.pub` public key is uploaded to your provider. **Never share the
private key.**

#### 1.3 Configure the Firewall

Open these inbound TCP ports in your cloud provider's firewall (security group):

| Port | Source | Purpose |
|---|---|---|
| `22` | your IP | SSH login |
| `443` | `0.0.0.0/0` (and `::/0` on IPv6) | the node itself |
| `8080` | your IP if possible | HTTP subscription (optional) |

Notes:

- Reality over TCP does not need UDP — only open TCP.
- The subscription URL contains your full client configuration; keep `8080`
  restricted to your own IP, or disable it after importing.
- For a **relay**, you instead open the exit's port to the relay's IP — see
  [relay](relay.md).

> Opening ports in the cloud console is not always enough.
> Many Linux images also run a local firewall (`ufw` or `firewalld`) that can
> silently block traffic even when the cloud rule is correct. If a port looks
> open in the console but the client still cannot connect, see
> [Appendix A](#a-firewall-ufw--firewalld).

#### 1.4 Connect via SSH

Open a terminal on your computer and use the following command:

```bash
ssh -i [KEY_FILE] [USERNAME]@[SERVER_PUBLIC_IP]
```

- `[KEY_FILE]` — path to your private key (for example `key.pem`, or `~/.ssh/id_ed25519`).
- `[USERNAME]` — the default login user. Ubuntu images use `ubuntu`; others may use `root`, `debian`, or `admin`.
- `[SERVER_PUBLIC_IP]` — your server's public IP address.

Example:

```bash
ssh -i key.pem ubuntu@203.0.113.10
```

On the first connection you will be asked to confirm the server's fingerprint;
type `yes` to continue.

### 2. Install RayLink

#### Exit Node

An **exit node** is the entry-and-exit node: clients connect to it and it reaches
the internet directly. Run this on the server:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/install.sh | sudo bash -s -- exit
```

When it finishes, the installer prints your subscription URLs (also saved to
`/opt/cloud-xray-exit/server-info.txt`). Continue to [Chapter 3](#3-import-into-clients).

To customize the install (ports, DNS profile, IPv6, etc.), pass environment
variables — see [configuration](configuration.md). Example, using port `8443`:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/install.sh | sudo env PORT=8443 bash -s -- exit
```

#### Relay Node

A **relay node** forwards all client traffic to an existing exit node
(`Client → Relay → Exit → Internet`). Deploy an exit node first, then take its
**Universal Subscription URL** and run this on a second server:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/install.sh | sudo env UPSTREAM_SUBSCRIPTION_URL='http://203.0.113.10:8080/sub/TOKEN' bash -s -- relay
```

Replace `203.0.113.10:8080/sub/TOKEN` with your exit's actual Universal
Subscription URL. See [relay](relay.md) for other ways to supply the upstream.

### 3. Import into Clients

The installer serves three link types. Use the one your client supports:

| Link | Endpoint | Use it for |
|---|---|---|
| **Universal Subscription URL** | `http://SERVER:8080/sub/TOKEN` | Auto-negotiating subscription for clients with subscription import — v2rayN, v2rayNG, Hiddify, Shadowrocket, NekoBox, etc. |
| **Clash Subscription URL** | `http://SERVER:8080/sub/TOKEN/clash.yaml` | Clash-family clients only — Mihomo, Clash Meta, FlClash, Clash Verge Rev |
| **Direct VLESS Link** | `vless://…` | Importing a single node by hand, with no subscription |

When HTTP subscription is enabled, the installer prints the two subscription
URLs; when it is disabled, it prints the Direct VLESS Link instead.

For Clash/Mihomo clients: import the Clash Subscription URL, select your node
under the `GLOBAL` proxy group, then enable system proxy or TUN mode.

To view the Direct VLESS Link on the server (an exit node shown; a relay uses
`/opt/cloud-xray-relay`):

```bash
sudo cat /opt/cloud-xray-exit/vless-uri.txt
```

> The Clash YAML and the VLESS URI intentionally keep their own field names
> (`network: tcp`, `reality-opts.public-key`, `type=tcp`, `pbk=…`). This is
> expected — do not rename them to the Xray JSON field names.

### 4. Download Configuration

To copy a generated file to your computer, use `scp` from your **local**
terminal:

```bash
scp -i [KEY_FILE] [USERNAME]@[SERVER_PUBLIC_IP]:[REMOTE_PATH] [LOCAL_PATH]
```

Example — download the Clash config:

```bash
scp -i key.pem ubuntu@203.0.113.10:/opt/cloud-xray-exit/clash.yaml ./raylink-clash.yaml
```

Example — download the Direct VLESS Link file:

```bash
scp -i key.pem ubuntu@203.0.113.10:/opt/cloud-xray-exit/vless-uri.txt ./vless-uri.txt
```

### 5. Next Steps

Manage the node any time from the server:

```bash
sudo raylink exit                 # re-run / update (safe, idempotent)
sudo raylink exit --health-check  # run a health check now
sudo raylink version
```

A systemd timer already re-checks the node periodically and self-heals. To learn
more:

- [exit](exit.md) — exit-node install, options, and health check.
- [relay](relay.md) — relay model, upstream parameters, and firewall.
- [configuration](configuration.md) — every environment variable.
- [troubleshooting](troubleshooting.md) — common issues, IPv6, uninstall.

---

## Appendix

### A. Firewall (ufw / firewalld)

Opening ports in the cloud console is not always sufficient — the operating
system may also run a local firewall. It is recommended that only to configure
the firewall that is **already active**.

**ufw** Check whether it is active:

```bash
sudo ufw status
```

If the output starts with `Status: active`, allow the ports:

```bash
sudo ufw allow 443/tcp
sudo ufw allow 8080/tcp
sudo ufw reload
```

**firewalld** Check whether it is running:

```bash
sudo systemctl is-active firewalld
```

If the output is `active`, allow the ports and reload:

```bash
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload
```

### B. SSH Key Generation

If you do not already have a key pair, generate one locally. ED25519 is
preferred (short and modern); RSA with a 4096-bit key is a widely compatible
alternative.

Generate an ED25519 key (saved to the default `~/.ssh/id_ed25519`):

```bash
ssh-keygen -t ed25519 -C "you@example.com"
```

Or an RSA key at an explicit path:

```bash
ssh-keygen -t rsa -b 4096 -C "you@example.com" -f ~/.ssh/id_rsa
```

You will be prompted for a passphrase:

- **Leave it empty** (press Enter twice) for convenience.
- **Set a passphrase** for better security — you will enter it whenever the key
  is used.

Press Enter to accept the default save location. Afterwards you have two files:

- `id_ed25519` (or `id_rsa`) — the **private key**. Never share it.
- `id_ed25519.pub` (or `id_rsa.pub`) — the **public key**. Safe to upload to your
  VPS provider.

Copy the public key to your clipboard, then paste it into your provider's
**SSH Keys** page (the "Key Name" is just a label and does not affect
authentication):

**# macOS**
```
pbcopy < ~/.ssh/id_ed25519.pub
```

**# Linux**
```
xclip -sel clip < ~/.ssh/id_ed25519.pub
```

**# Windows (PowerShell)**
```
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub" | Set-Clipboard
```

---

## 指南

本指南带你从一台全新的 Linux 服务器，一路完成节点部署和客户端导入。这里的每一步对两种节点都适用——节点专属选项见 [exit](exit.md) 和 [relay](relay.md)。

示例统一使用文档保留 IP `203.0.113.10`，请替换为你自己服务器的地址。

### 1. 准备工作

#### 1.1 启动一台服务器实例

你需要一台有公网 IP（IPv4 或 IPv6）且可 SSH 登录的 Linux 服务器。AWS、Google
Cloud、Oracle Cloud、Azure 或者其他云服务提供商。推荐 Ubuntu 系统，个人使用选小规格实例即可。

**示例:AWS EC2**

推荐操作系统:

```text
Ubuntu Server 26.04 LTS
```

个人使用推荐实例类型:

```text
t3.micro
```

创建实例时:

- 新建或选择一个 SSH Key Pair(见 [1.2](#12-创建-ssh-密钥对))。
- 在安全组放行入站 TCP 端口 `22`、`443`、`8080`(见 [1.3](#13-配置防火墙))。
- 分配一个公网 IPv4(或 IPv6)地址。

云平台通常会提供一个 `.pem` 私钥文件，只能下载一次，请妥善保存。

#### 1.2 创建 SSH 密钥对

SSH 通常通过一对密钥验证你的身份：**私钥**留在你自己电脑上，**公钥**放到服务器上。

有些服务商在创建实例时会帮你生成密钥对 (例如 AWS 会给你一个 `.pem` 私钥下载)；有些则要求你上传已有的公钥。如果你还没有密钥对，可以在本地生成，完整步骤见
[附录 B](#b-ssh-密钥生成)。

密钥默认存放在 `~/.ssh` 目录，使用标准文件名，大多数 SSH 客户端会自动识别：

| 算法 | 私钥 | 公钥 |
|---|---|---|
| ED25519 | `id_ed25519` | `id_ed25519.pub` |
| RSA | `id_rsa` | `id_rsa.pub` |
| ECDSA | `id_ecdsa` | `id_ecdsa.pub` |

只需要把 `.pub` 公钥上传给服务商。**切勿泄露私钥。**

#### 1.3 配置防火墙

在云服务商的防火墙（安全组）放行以下入站 TCP 端口：

| 端口 | 来源 | 用途 |
|---|---|---|
| `22` | 你的 IP | SSH 登录 |
| `443` | `0.0.0.0/0`(IPv6 用 `::/0`) | 节点本身 |
| `8080` | 尽量限制为你的 IP | HTTP 订阅(可选) |

说明:

- Reality over TCP 不需要 UDP，只开 TCP 即可。
- 订阅链接包含完整客户端配置；`8080` 尽量只对你自己的 IP 开放，或导入后关闭。
- 对于 **relay**，则是把出口节点的端口对 relay 的 IP 开放——见 [relay](relay.md)。

> 只在云控制台开端口，有时并不够。很多 Linux 镜像还运行着本地防火墙
> (`ufw` 或 `firewalld`)，即使云端规则正确，也可能悄悄拦截流量。如果控制台里对应端口
> 已经放行但是客户端仍连不上，请看 [附录 A](#a-防火墙-ufw--firewalld)。

#### 1.4 通过 SSH 登录

在你电脑上打开终端,使用如下命令：

```bash
ssh -i [KEY_FILE] [USERNAME]@[SERVER_PUBLIC_IP]
```

- `[KEY_FILE]` —— 私钥路径(例如 `key.pem`,或 `~/.ssh/id_ed25519`)。
- `[USERNAME]` —— 默认登录用户。Ubuntu 镜像是 `ubuntu`;其他可能是 `root`、`debian`、`admin`。
- `[SERVER_PUBLIC_IP]` —— 服务器公网 IP。

示例:

```bash
ssh -i key.pem ubuntu@203.0.113.10
```

首次连接会要求确认服务器指纹，输入 `yes` 继续。

### 2. 安装 RayLink

#### 出口节点(Exit)

**出口节点**既是入口也是出口：客户端连接它，它直接出站访问互联网。在服务器上运行：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/install.sh | sudo bash -s -- exit
```

结束时安装器会打印订阅链接（也保存在 `/opt/cloud-xray-exit/server-info.txt`）。
接着看 [章节3](#3-导入客户端)。

要自定义安装（端口、DNS profile、IPv6 等）可传环境变量——见
[configuration](configuration.md)。示例，使用 `8443` 端口：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/install.sh | sudo env PORT=8443 bash -s -- exit
```

#### 中转节点(Relay)

**中转节点**把所有客户端流量转发到一个已有的出口节点
(`客户端 → Relay → Exit → 互联网`)。先部署好出口节点，拿到它的
**Universal Subscription URL**，再在第二台服务器上运行：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/install.sh | sudo env UPSTREAM_SUBSCRIPTION_URL='http://203.0.113.10:8080/sub/TOKEN' bash -s -- relay
```

把 `203.0.113.10:8080/sub/TOKEN` 换成你出口节点真实的 Universal Subscription URL。其他提供 upstream 的方式见 [relay](relay.md)。

### 3. 导入客户端

安装器提供三种链接，按你的客户端支持情况选用：

| 链接 | 地址 | 适用于 |
|---|---|---|
| **Universal Subscription URL** | `http://SERVER:8080/sub/TOKEN` | 自动协商格式,支持订阅导入的客户端 —— v2rayN、v2rayNG、Hiddify、Shadowrocket、NekoBox 等 |
| **Clash Subscription URL** | `http://SERVER:8080/sub/TOKEN/clash.yaml` | 仅 Clash 系客户端 —— Mihomo、Clash Meta、FlClash、Clash Verge Rev |
| **Direct VLESS Link** | `vless://…` | 手动导入单个节点,不经过订阅 |

开启 HTTP 订阅时，安装器打印两个订阅链接；关闭时，则打印 Direct VLESS Link。

Clash/Mihomo 客户端：导入 Clash Subscription URL，在 `GLOBAL` 代理组里选择你的
节点,然后开启系统代理或 TUN 模式。

在服务器上查看 Direct VLESS Link（以出口节点为例；relay 使用
`/opt/cloud-xray-relay`）：

```bash
sudo cat /opt/cloud-xray-exit/vless-uri.txt
```

> Clash YAML 和 VLESS URI 会保留各自的字段名(`network: tcp`、
> `reality-opts.public-key`、`type=tcp`、`pbk=…`)。这是正常的，不要把它们改成
> Xray JSON 的字段名。

### 4. 下载配置

在你的**本地**终端用 `scp` 把生成的文件拷回电脑：

```bash
scp -i [KEY_FILE] [USERNAME]@[SERVER_PUBLIC_IP]:[REMOTE_PATH] [LOCAL_PATH]
```

示例 —— 下载 Clash 配置：

```bash
scp -i key.pem ubuntu@203.0.113.10:/opt/cloud-xray-exit/clash.yaml ./raylink-clash.yaml
```

示例 —— 下载 Direct VLESS Link 文件：

```bash
scp -i key.pem ubuntu@203.0.113.10:/opt/cloud-xray-exit/vless-uri.txt ./vless-uri.txt
```

### 5. 后续

随时在服务器上管理节点：

```bash
sudo raylink exit                 # 重新运行 / 更新(安全、幂等)
sudo raylink exit --health-check  # 立即运行一次自检
sudo raylink version
```

systemd timer 已经在定期自检并自修复。想深入了解：

- [exit](exit.md) —— 出口节点安装、选项、自检。
- [relay](relay.md) —— 中转模型、upstream 参数、防火墙。
- [configuration](configuration.md) —— 所有环境变量。
- [troubleshooting](troubleshooting.md) —— 常见问题、IPv6、卸载。

---

## 附录

### A. 防火墙 (ufw / firewalld)

只在云控制台开端口有时不够——操作系统本身可能也在跑本地防火墙。建议只配置**已经启用**
的防火墙。

**ufw** 先检查是否启用：

```bash
sudo ufw status
```

如果输出以 `Status: active` 开头,放行端口：

```bash
sudo ufw allow 443/tcp
sudo ufw allow 8080/tcp
sudo ufw reload
```

**firewalld** 先检查是否在运行：

```bash
sudo systemctl is-active firewalld
```

如果输出是 `active`，放行端口并重载：

```bash
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload
```

### B. SSH 密钥生成

如果还没有密钥对，在本地生成一个。推荐 ED25519(短小、现代)；RSA 4096 位是兼容性
更广的备选。

生成 ED25519 密钥(保存到默认的 `~/.ssh/id_ed25519`)：

```bash
ssh-keygen -t ed25519 -C "you@example.com"
```

或在指定路径生成 RSA 密钥：

```bash
ssh-keygen -t rsa -b 4096 -C "you@example.com" -f ~/.ssh/id_rsa
```

过程中会提示设置密码：

- **留空**（连按两次 Enter）更方便。
- **设置密码** 更安全——每次使用密钥都要输入它。

按 Enter 使用默认保存位置。之后你会得到两个文件：

- `id_ed25519`(或 `id_rsa`)—— **私钥**,切勿泄露。
- `id_ed25519.pub`(或 `id_rsa.pub`)—— **公钥**,可以安全上传给 VPS 服务商。

把公钥复制到剪贴板，再粘贴到服务商的 **SSH Keys** 页面("Key Name" 只是标签,不影响认证)：

**# macOS**
```
pbcopy < ~/.ssh/id_ed25519.pub
```

**# Linux**
```
xclip -sel clip < ~/.ssh/id_ed25519.pub
```

**# Windows (PowerShell)**
```
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub" | Set-Clipboard
```
