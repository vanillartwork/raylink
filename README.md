# RayLink

Deploy and maintain personal Xray REALITY proxy nodes with a single command — featuring client-ready subscriptions and automated self-healing.

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
  end-to-end Reality self-test, and automatically attempts recovery (e.g., service restart, config regeneration, upstream refresh, or target fallback) to maintain connectivity.
- **Relay mode** — chain `Client → Relay → Terminal` to hide the exit node or
  stabilize a flaky client→exit path.
- **Resilient downloads** — optimized for unstable networks with built-in retries, timeouts, and support for custom mirrors/proxies.
- **IPv4 & IPv6** — auto-detects the address family and fully supports IPv6-only servers.
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

(For detailed instructions, see docs/getting-started.md)

On a Linux server, allow inbound TCP traffic on ports `443` and `8080`, then run:

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

RayLink 是一个用于在 Linux 服务器上部署和维护个人 Xray 代理节点（VLESS Reality）的模块化安装器和 CLI。一键部署并维护个人 Xray REALITY 代理节点 —— 附带开箱即用的客户端订阅与自动化自愈机制。

> 请仅用于合法、合规的网络访问。云服务器和流量可能产生费用。

### 核心特性

- **一条命令极速部署** — 自动完成 Xray-core 安装、systemd 服务加固、BBR 网络调优及持久化 VLESS Reality 凭据配置，一行代码即可就绪。
- **开箱即用的客户端订阅** — 通过 HTTP 提供 Clash/Mihomo YAML 配置文件及通用 URI-list，客户端只需导入一个 URL 即可完成节点配置。
- **自动化自愈机制** — 守护节点长期稳定运行。定时自检会监测服务状态并执行端到端 Reality 测试；在网络环境变化或检测到异常时，可自动重启服务、应对公网 IP 变更更新订阅文件、刷新中转上游参数或执行 fallback 切换。
- **灵活的中转模式** — 支持`客户端 → 中转节点 → 终端节点`架构，有效隐藏真实出口节点，改善并稳定较差的直连链路。。
- **网络容错与下载优化** — 专为复杂网络环境设计。内置完善的重试与超时管控机制，并支持灵活配置自定义镜像源，确保在不稳定网络下依然能顺利完成安装与更新。
- **完善的 IPv6 支持** — 自动识别当前公网地址族，全面兼容双栈网络，并完美支持 IPv6-only VPS。
- **幂等设计与高可配置性** — 脚本可安全地重复执行；节点的所有默认行为与参数均可通过环境变量进行自定义覆盖。

### 工作原理

```text
客户端 → 服务器:443 → Xray VLESS Reality 入站 → direct 出站 → 互联网
```

中转节点会在终端节点前面多加一跳：

```text
客户端 → Relay:443 → Terminal:443 → 互联网
```

### 快速开始
(详情参见 docs/getting-started.md)

在一台 Linux 服务器上，放行入站端口`443`和`8080` TCP 流量，然后执行下面指令：

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

### 项目结构

```text
raylink/
├── install.sh        # 引导安装器：下载并安装 raylink CLI
├── src/              # raylink 调度器、commands/、lib/、defaults/、templates/
├── scripts/          # build-release.sh、check.sh
└── docs/
```

服务器端 CLI 安装在 `/usr/local/lib/raylink/`，软链到 `/usr/local/bin/raylink`。

### 安全

SSH（`22`）只放行你自己的 IP；导入配置后，限制或关闭订阅端口（`8080`）。不要分享
订阅链接、VLESS 链接、UUID、Reality key 或 shortId——它们合起来就是你完整的客户端
配置。注意云服务器账单和流量。

### 开源协议

本项目基于 MIT License 发布。
