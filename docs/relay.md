# Relay node

A relay sits in front of an exit node and forwards all client traffic to it:

```text
Client
→ Relay server:443      (Xray VLESS Reality inbound)
→ Relay outbound        (Xray VLESS Reality to exit)
→ Exit server:443       (Xray VLESS Reality inbound)
→ Exit direct out
→ Internet
```

Clients connect only to the relay and never see the exit. Use a relay when
the client→exit path is unstable but client→relay and relay→exit are
stable, when you want to hide the exit's real entry, or when you want the
exit firewall to only accept the relay's IP.

Trade-offs: one extra hop of latency, traffic billed on both servers, and a
failure on either node breaks the chain.

> Server preparation, SSH, and importing the relay's subscription into clients
> are the same as any node — see [getting-started.md](getting-started.md). This
> page covers what is relay-specific.

## Prerequisite: a working exit

The relay needs upstream exit parameters. Deploy an exit first (see
[exit.md](exit.md)) and grab its VLESS link or subscription URL.

## Two Reality parameter sets

A relay has two sets, kept strictly separate:

- **Inbound (client-facing)** — reused under the standard variable names
  (`UUID`, `PRIVATE_KEY`, `PUBLIC_KEY`, `SHORT_ID`, `REALITY_DEST`,
  `REALITY_SERVER_NAME`, `CLIENT_FINGERPRINT`, `FLOW`, `PORT`). These are
  generated on the relay and are what the client subscription exposes. You can
  pin them with the `RELAY_*` aliases (`RELAY_UUID`, `RELAY_PRIVATE_KEY`, …).
- **Upstream (relay → exit)** — the `UPSTREAM_*` variables, taken from the
  exit. Stored only in `/opt/cloud-xray-relay/upstream.env`, never published.

## Install

The relay needs upstream parameters. Pick one of three ways, easiest last.

Subscription URL (recommended — health check can auto-refresh it). Use the
exit's **Universal URI-list** endpoint (`/sub/TOKEN`), which returns the
base64 VLESS URI list. Do **not** use the `/clash.yaml` endpoint here — the
relay parses a `vless://` URI, not a Clash YAML.

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/install.sh \
  | sudo env UPSTREAM_SUBSCRIPTION_URL='http://EXIT_IP:8080/sub/TOKEN' bash -s -- relay
```

Exit VLESS link:

```bash
curl -fsSL .../install.sh \
  | sudo env UPSTREAM_VLESS_URI='vless://UUID@EXIT_IP:443?...' bash -s -- relay
```

Individual fields:

```bash
curl -fsSL .../install.sh | sudo env \
  UPSTREAM_ADDRESS=1.2.3.4 UPSTREAM_PORT=443 UPSTREAM_UUID='...' \
  UPSTREAM_SERVER_NAME=www.cloudflare.com UPSTREAM_FINGERPRINT=chrome \
  UPSTREAM_PUBLIC_KEY='...' UPSTREAM_SHORT_ID='...' \
  bash -s -- relay
```

Manage later with the CLI:

```bash
sudo raylink relay                 # re-run / update (safe)
sudo raylink relay --health-check  # run a health check
```

## Self-test covers the whole chain

Because the relay routes every inbound connection to the upstream, the
end-to-end self-test (a temporary local SOCKS client → relay inbound →
exit → internet) validates the complete path in one shot. If it fails,
the relay's inbound Reality target falls back through candidates exactly like
the exit; if the *exit* itself is down, the relay cannot repair it and
can only refresh upstream parameters from the exit subscription.

## Firewall

Relay server:

| Port | Source | Purpose |
|---|---|---|
| TCP 22 | your IP | SSH |
| TCP 443 | `0.0.0.0/0` | clients connect to relay |
| TCP 8080 | your IP | relay subscription (optional) |

Exit server (tighten once the relay is up):

| Port | Source | Purpose |
|---|---|---|
| TCP 443 | relay IP (+ your IP if needed) | relay connects to exit |
| TCP 8080 | relay IP (+ your IP if needed) | relay refreshes upstream subscription |

## Health check

The timer runs `raylink relay --health-check`, which:

1. Detects the relay's current public IPv4.
2. Loads relay inbound credentials.
3. Refreshes upstream parameters from `UPSTREAM_SUBSCRIPTION_URL` if set.
4. Checks the relay Xray service.
5. Runs the end-to-end self-test.
6. Falls back through relay inbound Reality candidates if that target fails.
7. On success, rewrites config, restarts, and regenerates client/subscription files.
8. On total failure, keeps the previous config and exits non-zero.

Note: if the exit's public IP changes and your `UPSTREAM_SUBSCRIPTION_URL`
points at the old raw IP, the relay can no longer reach it. Use a static IP or
domain for the exit.

## Same-host coexistence

Relay paths, service names, nginx site/zone, and health check units are all
distinct from the exit (`/opt/cloud-xray-relay`, `raylink-relay.service`,
`raylink-relay-healthcheck.*`), so both roles can be installed on one host for
testing. You must still give them different `PORT` and `SUB_PORT` values, since
two services cannot share a port.
