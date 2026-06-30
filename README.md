# RayLink

One-command Xray VLESS Reality VPN nodes on Linux — with a client-ready HTTP
subscription and a self-healing health check.

[English](#english) · [中文](#中文)

---

## English

RayLink is a modular installer and CLI for deploying and maintaining personal
Xray-based proxy nodes (VLESS Reality) on Linux servers. One command sets up the
node, publishes a subscription your clients import directly, and installs a timer
that keeps the node working as conditions change.

> Use this project only for legal, compliant network access. Cloud servers and
> bandwidth may incur charges.

### Features

- **One command, fully set up** — Xray-core, a hardened systemd service, BBR
  tuning, and persistent VLESS Reality credentials, in a single line.
- **Client-ready subscriptions** — serves a Clash/Mihomo YAML and a universal
  URI-list over HTTP; clients import one URL.
- **Self-healing** — a periodic health check re-detects the public IP, runs an
  end-to-end Reality self-test, and auto-fails-over the Reality target when one
  stops working.
- **Relay mode** — chain `Client → Relay → Terminal` to hide the exit node or
  stabilize a flaky client→exit path.
- **Resilient downloads** — retries, timeouts, and `GITHUB_URL_PREFIX` /
  `XRAY_DOWNLOAD_URL` escape hatches for slow or blocked GitHub.
- **IPv4 & IPv6** — auto-detects the address family and brackets IPv6 in links
  and URLs automatically.
- **Idempotent & configurable** — safe to re-run; every default is overridable
  through environment variables.

### How it works

```text
Client → server:443 → Xray VLESS Reality inbound → direct outbound → Internet
```

A **relay** adds one hop in front of a terminal:

```text
Client → Relay:443 → Terminal:443 → Internet
```

### Quick start

On a fresh Linux server (Ubuntu recommended), open inbound TCP `443` (and `8080`
for the subscription), then run:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/install.sh | sudo bash -s -- terminal
```

The installer prints your subscription URLs at the end. Import the
`…/clash.yaml` URL into Clash/Mihomo, or the universal URL into
v2rayN / v2rayNG / Hiddify / Shadowrocket.

Manage the node later:

```bash
sudo raylink terminal                 # re-run / update (safe, idempotent)
sudo raylink terminal --health-check  # run a health check now
```

Add a relay in front of an existing terminal:

```bash
curl -fsSL .../install.sh | sudo env UPSTREAM_SUBSCRIPTION_URL='http://TERMINAL_IP:8080/sub/TOKEN' bash -s -- relay
```

### Documentation

| Doc | Contents |
|---|---|
| [docs/getting-started.md](docs/getting-started.md) | Start here — server prep, SSH, importing into clients, downloading config |
| [docs/terminal.md](docs/terminal.md) | Terminal node — install, options, managing, health check |
| [docs/relay.md](docs/relay.md) | Relay node — model, upstream parameters, firewall |
| [docs/configuration.md](docs/configuration.md) | Every environment variable — ports, Reality, DNS profiles, IPv6, metrics, downloads |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Common issues, IPv6-only servers, uninstall |

### Project layout

```text
raylink/
├── install.sh        # bootstrap: downloads + installs the raylink CLI
├── src/              # raylink dispatcher, commands/, lib/, defaults/, templates/
├── scripts/          # build-release.sh, check.sh
└── docs/
```

On the server the CLI lives under `/usr/local/lib/raylink/` and is linked at
`/usr/local/bin/raylink`.

### Security

Keep SSH (`22`) limited to your own IP, and restrict or disable the subscription
port (`8080`) once you have imported the config. Never share your subscription
URL, VLESS link, UUID, Reality keys, or shortId — together they are your full
client configuration. Watch your cloud bill and bandwidth.

### License

Released under the [MIT License](#license).

---

## 中文

RayLink 是一个用于在 Linux 服务器上部署和维护个人 Xray 代理节点（VLESS Reality）
的模块化安装器和 CLI。一条命令即可搭好节点、生成客户端可直接导入的订阅，并安装一个
定时自检，让节点在环境变化时保持可用。

> 请仅用于合法、合规的网络访问。云服务器和流量可能产生费用。

### 特性

- **一条命令装好** — Xray-core、加固的 systemd 服务、BBR 调优、持久化的 VLESS
  Reality 凭据，一行搞定。
- **客户端可直接导入的订阅** — 通过 HTTP 提供 Clash/Mihomo YAML 和通用 URI-list，
  客户端导入一个 URL 即可。
- **自愈机制** — 定时自检会重新检测公网 IP、执行端到端 Reality 自测，并在某个 Reality
  target 失效时自动 fallback 切换。
- **中转模式** — `客户端 → 中转节点 → 终端节点`，用于隐藏出口节点或稳定不佳的链路。
- **下载更稳** — 带重试、超时，以及 `GITHUB_URL_PREFIX` / `XRAY_DOWNLOAD_URL`
  逃生口，应对 GitHub 慢或被墙。
- **IPv4 / IPv6 双栈支持** — 自动识别地址族，并自动给 IPv6 在链接/URL 中加方括号。
- **幂等性与可配置性** — 可安全重复运行；所有默认值都能通过环境变量覆盖。

### 工作原理

```text
客户端 → 服务器:443 → Xray VLESS Reality 入站 → direct 出站 → 互联网
```

中转节点会在终端节点前面多加一跳：

```text
客户端 → Relay:443 → Terminal:443 → 互联网
```

### 快速开始

在一台干净的 Linux 服务器（推荐 Ubuntu）上，放行入站 TCP `443`（订阅再放行
`8080`），然后执行下面指令：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/install.sh | sudo bash -s -- terminal
```

安装结束时会打印订阅链接：Clash/Mihomo 导入 `…/clash.yaml` URL，
v2rayN / v2rayNG / Hiddify / Shadowrocket 导入通用 URL。

之后管理节点：

```bash
sudo raylink terminal                 # 重新运行 / 更新（安全、幂等）
sudo raylink terminal --health-check  # 立即运行一次自检
```

在已有 terminal 前面加一个 relay：

```bash
curl -fsSL .../install.sh | sudo env UPSTREAM_SUBSCRIPTION_URL='http://TERMINAL_IP:8080/sub/TOKEN' bash -s -- relay
```

### 文档

| 文档 | 内容 |
|---|---|
| [docs/getting-started.md](docs/getting-started.md) | 从这里开始 — 服务器准备、SSH、客户端导入、下载配置 |
| [docs/terminal.md](docs/terminal.md) | 终端节点 — 安装、选项、管理、自检 |
| [docs/relay.md](docs/relay.md) | 中转节点 — 模型、upstream 参数、防火墙 |
| [docs/configuration.md](docs/configuration.md) | 所有环境变量 — 端口、Reality、DNS profile、IPv6、metrics、下载 |
| [docs/troubleshooting.md](docs/troubleshooting.md) | 常见问题、IPv6-only 服务器、卸载 |

> 文档为英文。

### 工程结构

```text
raylink/
├── install.sh        # 引导安装器：下载并安装 raylink CLI
├── src/              # raylink 调度器、commands/、lib/、defaults/、templates/
├── scripts/          # build-release.sh、check.sh
└── docs/
```

服务器上 CLI 位于 `/usr/local/lib/raylink/`，软链到 `/usr/local/bin/raylink`。

### 安全

SSH（`22`）只放行你自己的 IP；导入配置后，限制或关闭订阅端口（`8080`）。不要分享
订阅链接、VLESS 链接、UUID、Reality key 或 shortId——它们合起来就是你完整的客户端
配置。注意云服务器账单和流量。

### License

This project is released under the MIT License.
