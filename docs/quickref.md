# Quick Reference

> Every important command in one place.

## Installation

```bash
# Docker image pull is the default; add --source to build from source instead.
skills/lnd/scripts/install.sh                              # litd container image
skills/lnget/scripts/install.sh                            # lnget CLI (always built from source)
skills/aperture/scripts/install.sh                         # aperture (always built from source)
skills/lightning-mcp-server/scripts/install.sh                          # MCP server (always built from source)
skills/lightning-security-module/scripts/install.sh         # lnd signer container image
```

## Node Operations

```bash
# Start/stop (Docker container by default; --native for local binary)
skills/lnd/scripts/start-lnd.sh                            # start litd container (standalone)
skills/lnd/scripts/start-lnd.sh --watchonly                # watch-only + signer containers
skills/lnd/scripts/start-lnd.sh --regtest                  # regtest + bitcoind containers
skills/lnd/scripts/start-lnd.sh --profile debug            # start with debug logging profile
skills/lnd/scripts/docker-start.sh --list-profiles         # list available profiles
skills/lnd/scripts/stop-lnd.sh                             # stop containers
skills/lnd/scripts/stop-lnd.sh --clean                     # stop + remove Docker volumes

# Node queries (auto-detects containers)
skills/lnd/scripts/lncli.sh getinfo                        # node status
skills/lnd/scripts/lncli.sh walletbalance                  # on-chain balance
skills/lnd/scripts/lncli.sh channelbalance                 # channel balance
skills/lnd/scripts/unlock-wallet.sh                        # unlock after restart
```

## Wallet

```bash
# Watch-only with Docker (signer on Docker network, no --signer-host needed)
skills/lnd/scripts/import-credentials.sh --bundle <path>
skills/lnd/scripts/create-wallet.sh                        # auto-detects container

# Watch-only with native (signer on separate machine)
skills/lnd/scripts/import-credentials.sh --bundle <path>
skills/lnd/scripts/create-wallet.sh --native --signer-host <ip>:10012

# Standalone (testing, generates local seed)
skills/lnd/scripts/create-wallet.sh --mode standalone

# Funding
skills/lnd/scripts/lncli.sh newaddress p2tr               # generate address
skills/lnd/scripts/lncli.sh walletbalance                  # check balance
```

## Channels

```bash
skills/lnd/scripts/lncli.sh connect <pubkey>@<host>:9735                      # connect to peer
skills/lnd/scripts/lncli.sh openchannel --node_key=<pubkey> --local_amt=N      # open channel
skills/lnd/scripts/lncli.sh listchannels                                       # list channels
skills/lnd/scripts/lncli.sh pendingchannels                                    # pending opens/closes
skills/lnd/scripts/lncli.sh closechannel --funding_txid=<txid> --output_index=N  # close channel
skills/lnd/scripts/lncli.sh listpeers                                          # connected peers
skills/lnd/scripts/lncli.sh disconnect <pubkey>                                # disconnect peer
```

## Payments

```bash
skills/lnd/scripts/lncli.sh addinvoice --amt=1000 --memo="description"    # create invoice
skills/lnd/scripts/lncli.sh decodepayreq <bolt11>                          # decode invoice
skills/lnd/scripts/lncli.sh sendpayment --pay_req=<bolt11>                 # pay invoice
skills/lnd/scripts/lncli.sh listpayments                                   # payment history
skills/lnd/scripts/lncli.sh listinvoices                                   # invoice history
```

## Macaroon Bakery

```bash
# Preset roles
skills/macaroon-bakery/scripts/bake.sh --role pay-only
skills/macaroon-bakery/scripts/bake.sh --role invoice-only
skills/macaroon-bakery/scripts/bake.sh --role read-only
skills/macaroon-bakery/scripts/bake.sh --role channel-admin
skills/macaroon-bakery/scripts/bake.sh --role signer-only

# Custom
skills/macaroon-bakery/scripts/bake.sh --custom \
    uri:/lnrpc.Lightning/SendPaymentSync \
    uri:/lnrpc.Lightning/DecodePayReq \
    uri:/lnrpc.Lightning/GetInfo

# Inspect
skills/macaroon-bakery/scripts/bake.sh --inspect <path-to-macaroon>

# List all available permissions
skills/macaroon-bakery/scripts/bake.sh --list-permissions

# Save to specific path
skills/macaroon-bakery/scripts/bake.sh --role pay-only --save-to ~/agent.macaroon
```

## lnget

```bash
# Fetch
lnget https://api.example.com/data.json                   # fetch to stdout
lnget -o data.json https://api.example.com/data.json       # fetch to file
lnget -q https://api.example.com/data.json | jq .          # quiet mode, pipe
lnget -X POST -d '{"q":"test"}' https://api.example.com    # POST with body

# Cost control
lnget --max-cost 500 https://api.example.com/data          # max auto-pay amount
lnget --no-pay https://api.example.com/data                # preview without paying
lnget --no-pay --json https://... | jq '.invoice_amount_sat'  # check price

# Tokens
lnget tokens list                                          # list cached tokens
lnget tokens show api.example.com                          # show specific token
lnget tokens remove api.example.com                        # force re-payment
lnget tokens clear --force                                 # clear all tokens

# Configuration
lnget config init                                          # initialize config
lnget config show                                          # show current config

# Backend status
lnget ln status                                            # connection status
lnget ln info                                              # backend info

# LNC pairing
lnget ln lnc pair "ten word pairing phrase here"           # pair with LNC
lnget ln lnc sessions                                      # list LNC sessions
lnget ln lnc revoke <session-id>                           # revoke session

# Neutrino (embedded wallet)
lnget ln neutrino init                                     # initialize
lnget ln neutrino fund                                     # funding address
lnget ln neutrino balance                                  # check balance

# Dashboard & API server
lnget serve                                                # start API (localhost:2402)
lnget serve --addr localhost:2402                           # custom address
cd dashboard && yarn dev                                   # start dashboard (localhost:3001)
```

## Aperture

```bash
skills/aperture/scripts/setup.sh                           # generate config
skills/aperture/scripts/setup.sh --insecure --port 8081    # dev mode
skills/aperture/scripts/setup.sh --network testnet         # testnet
skills/aperture/scripts/start.sh                           # start proxy
skills/aperture/scripts/stop.sh                            # stop proxy
```

## MCP Server

```bash
skills/lightning-mcp-server/scripts/install.sh                         # build from source
skills/lightning-mcp-server/scripts/configure.sh                        # generate .env
skills/lightning-mcp-server/scripts/configure.sh --production           # mainnet config
skills/lightning-mcp-server/scripts/configure.sh --dev --insecure       # regtest config
skills/lightning-mcp-server/scripts/setup-claude-config.sh --scope project   # add to .mcp.json
skills/lightning-mcp-server/scripts/setup-claude-config.sh --scope global    # add to ~/.claude.json
```

## Remote Signer

```bash
# On signer machine (Docker container by default)
skills/lightning-security-module/scripts/install.sh        # pull lnd signer image
skills/lightning-security-module/scripts/setup-signer.sh   # create wallet + export creds (auto-detects container)
skills/lightning-security-module/scripts/start-signer.sh   # start signer container
skills/lightning-security-module/scripts/stop-signer.sh    # stop signer container
skills/lightning-security-module/scripts/stop-signer.sh --clean  # stop + remove volumes
skills/lightning-security-module/scripts/export-credentials.sh   # re-export bundle

# On agent machine (Docker)
skills/lnd/scripts/import-credentials.sh --bundle <path>
skills/lnd/scripts/create-wallet.sh                        # auto-detects container
skills/lnd/scripts/start-lnd.sh --watchonly                # watch-only + signer containers

# On agent machine (native, signer on separate host)
skills/lnd/scripts/import-credentials.sh --bundle <path>
skills/lnd/scripts/create-wallet.sh --native --signer-host <ip>:10012
skills/lnd/scripts/start-lnd.sh --native --signer-host <ip>:10012

# Scope signer macaroon (container or native)
skills/macaroon-bakery/scripts/bake.sh --role signer-only --container litd-signer
skills/macaroon-bakery/scripts/bake.sh --role signer-only --rpc-port 10012 --lnddir ~/.lnd-signer
```

## Docker Containers

Docker is the default deployment method. Container lifecycle:

```bash
# Lifecycle (these are the primary entry points)
skills/lnd/scripts/start-lnd.sh                            # standalone litd container
skills/lnd/scripts/start-lnd.sh --watchonly                # litd + signer containers
skills/lnd/scripts/start-lnd.sh --regtest                  # litd + bitcoind containers
skills/lnd/scripts/start-lnd.sh --regtest --profile debug  # regtest with debug logging
skills/lnd/scripts/stop-lnd.sh                             # stop all mode containers
skills/lnd/scripts/stop-lnd.sh --clean                     # stop + remove volumes
skills/lnd/scripts/docker-start.sh --list-profiles         # show available profiles
```

All `lncli` and bakery commands auto-detect running containers. Use `--container`
to target a specific container by name:

```bash
skills/lnd/scripts/lncli.sh getinfo                        # auto-detects litd container
skills/lnd/scripts/lncli.sh --container litd-bob getinfo   # target specific container
skills/macaroon-bakery/scripts/bake.sh --role pay-only --container litd
skills/lightning-security-module/scripts/export-credentials.sh --container litd-signer
```

## Remote Nodes

All scripts support direct connection to remote lnd nodes:

```bash
skills/lnd/scripts/lncli.sh \
    --rpcserver remote-host:10009 \
    --tlscertpath ~/remote-tls.cert \
    --macaroonpath ~/remote-admin.macaroon \
    getinfo

skills/macaroon-bakery/scripts/bake.sh --role pay-only \
    --rpcserver remote-host:10009 \
    --tlscertpath ~/remote-tls.cert \
    --macaroonpath ~/remote-admin.macaroon \
    --save-to ~/remote-pay-only.macaroon
```

## File Paths

| Path | Purpose |
|------|---------|
| `~/.lnget/lnd/lnd.conf` | lnd configuration |
| `~/.lnget/lnd/wallet-password.txt` | Wallet passphrase (0600) |
| `~/.lnget/lnd/seed.txt` | Wallet seed, standalone only (0600) |
| `~/.lnget/lnd/signer-credentials/` | Imported signer credentials |
| `~/.lnget/signer/signer-lnd.conf` | Signer configuration |
| `~/.lnget/signer/wallet-password.txt` | Signer passphrase (0600) |
| `~/.lnget/signer/seed.txt` | Signer seed (0600) |
| `~/.lnget/signer/credentials-bundle/` | Exported signer credentials |
| `~/.lnget/config.yaml` | lnget configuration |
| `~/.lnget/tokens/<domain>/` | L402 cached tokens |
| `~/.lnget/events.db` | Payment event log (SQLite) |
| `~/.lnd/` | lnd data (chain, macaroons, TLS) |
| `~/.lnd/data/chain/bitcoin/<network>/admin.macaroon` | Admin macaroon |
| `~/.lnd/tls.cert` | lnd TLS certificate |
| `~/.lnd-signer/` | Signer lnd data |
| `~/.aperture/aperture.yaml` | Aperture configuration |
| `~/.aperture/aperture.db` | Aperture token database |
| `lightning-mcp-server/.env` | MCP server config |

## Ports

| Port | Service | Daemon |
|------|---------|--------|
| 8443 | HTTPS (UI + gRPC + REST) | litd (container) |
| 9735 | Lightning P2P | lnd |
| 10009 | gRPC | lnd |
| 8080 | REST | lnd |
| 10012 | gRPC | signer lnd |
| 10013 | REST | signer lnd |
| 8081 | HTTP/L402 | aperture (configurable) |
