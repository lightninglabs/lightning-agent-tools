---
name: run-litd
description: "Setting up a Bitcoin Lightning node on Ubuntu using litd (Lightning Terminal). Default path: Neutrino-backed single node (fast, no bitcoind needed). Also covers bitcoind-backed routing nodes and the remote signer architecture for production."
---

# Run litd — Node Setup & Remote Signer

Reference for setting up litd (Lightning Terminal) and LND on Ubuntu, including the recommended remote signer architecture that separates key-holding from routing.

Tested on Ubuntu 24.04 LTS. Current target versions: **bitcoind v31.0**, **litd v0.16.1-alpha**, **LND v0.20.1-beta**.

Source scripts: https://github.com/HannahMR/run-litd

---

## Architecture Overview

| Role | Software | Holds keys? | Internet-exposed? |
|------|----------|-------------|-------------------|
| **Single node** | litd (integrated) | Yes | Yes |
| **Signer node** | LND (standalone) | Yes — wallet + private keys | No — ideally on private network |
| **Routing node** | litd (watch-only) | No | Yes — public Lightning node |

The remote signer architecture is recommended for production: the signer holds keys and is never internet-exposed; the routing node handles payments. Three files transfer from signer to routing node: `tls.cert` (rename to `signer-tls.cert`), `signer.macaroon`, `accounts.json`.

---

## Node Setup Options

| | Neutrino (default) | bitcoind |
|---|---|---|
| **Bitcoin backend** | Lightweight SPV, built into LND | Full node |
| **Disk required** | ~1 GB | 80 GB+ pruned / 800 GB+ full |
| **Sync time** | Minutes | Hours–days |
| **Mainnet routing** | Not recommended | ✓ |
| **Signet / dev** | ✓ Ideal | ✓ |

**Default behaviour:** unless the user explicitly asks for bitcoind or a source build, always use the Neutrino binary path.

---

## Server Requirements

- Ubuntu 24.04 LTS (also tested on 22.04)
- 2+ CPU cores, 4 GB+ RAM
- Storage: ~10 GB for Neutrino; 80 GB+ for pruned bitcoind node; 800 GB+ for full mainnet node
- For attached-disk full nodes, set `datadir=/path/to/disk` in `bitcoin.conf`

---

## Before You Begin

### Step 1 — Check sudo access

The setup scripts require root to install binaries to `/usr/local/bin/`, install packages via `apt-get`, write systemd service files to `/etc/systemd/system/`, and run `systemctl` commands. Check that passwordless sudo is working before doing anything else:

```bash
sudo -n true 2>/dev/null && echo "OK" || echo "NEEDS_SETUP"
```

If the output is `NEEDS_SETUP`, explain to the user why these permissions are needed — the setup scripts must install binaries to `/usr/local/bin/`, install packages via `apt-get`, write systemd service files to `/etc/systemd/system/`, and run `systemctl` commands, all of which require root. Claude cannot enter a password interactively, so passwordless sudo must be configured first. Then ask them to run the fix:

> "I need you to open a new SSH terminal tab and paste these two commands, then let me know when done. This is a one-time setup for this server. Note that each command pipes through `sudo tee` — the `sudo` is required to write to `/etc/sudoers.d/`, so you will be prompted for your password. Do not remove `sudo` from the commands."
>
> ```bash
> echo 'Defaults:ubuntu !use_pty' | sudo tee /etc/sudoers.d/ubuntu-nopty > /dev/null
> sudo chmod 0440 /etc/sudoers.d/ubuntu-nopty
> ```
> ```bash
> echo 'ubuntu ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/ubuntu-nopasswd > /dev/null
> sudo chmod 0440 /etc/sudoers.d/ubuntu-nopasswd
> ```

Wait for the user to confirm, then re-run `sudo -n true` to verify before continuing.

### Step 2 — Gather setup details

Ask the user:
1. Which network — **signet** (testing) or **mainnet** (production)?
2. Which role is this machine — **single node**, **signer node**, or **routing node**?

**Default behaviour:** use the Neutrino binary path unless the user explicitly asks for bitcoind or a source build. Neutrino is built into LND — no separate Bitcoin node or service needed. It is ideal for signet and development but not recommended for mainnet production routing nodes due to peer dependency.

Once you have the answers, run `sudo -v` to cache credentials, then jump to the relevant section below.

---

## Neutrino Setup (Default)

Neutrino is a lightweight SPV Bitcoin client built into LND — no bitcoind installation required. litd still needs its own `lit.conf` and systemd service; `neutrino_setup3.sh` handles both.

**Important:** the setup scripts use interactive `read` prompts that Claude CLI cannot respond to. Generate the config files directly before running the scripts — each script checks for existing files and skips the interactive config section automatically.

### Single node (litd + Neutrino)

This path installs litd with a Neutrino backend. litd provides the web UI and integrated LND node.

**Before running the script**, ask the user for:
- A UI password (for the litd web interface)
- A node alias

Then generate the config files using the Bash tool. Read `${CLAUDE_SKILL_DIR}/neutrino/neutrino_setup_binary.sh` to see the exact config structure the script would produce, then reproduce it with the user's values substituted in:

```bash
mkdir -p ~/.lnd ~/.lit
openssl rand -hex 21 > ~/.lnd/wallet_password
chmod 600 ~/.lnd/wallet_password
# Write ~/.lit/lit.conf via heredoc — structure is in neutrino_setup_binary.sh
```

Once the config files exist, run the install script — it installs litd and skips the interactive config section:

```bash
chmod +x ${CLAUDE_SKILL_DIR}/neutrino/neutrino_setup_binary.sh ${CLAUDE_SKILL_DIR}/neutrino/neutrino_setup3.sh
sudo ${CLAUDE_SKILL_DIR}/neutrino/neutrino_setup_binary.sh
```

After the install script completes, create the wallet automatically:

```bash
chmod +x ${CLAUDE_SKILL_DIR}/litd_wallet_create.sh
sudo ${CLAUDE_SKILL_DIR}/litd_wallet_create.sh
```

This starts litd in the background, creates the wallet via the LND REST API, saves the seed to `~/.lnd/seed_phrase.txt`, and stops litd. Prompt the user to back up and delete the seed:

> "Your seed phrase has been saved to `~/.lnd/seed_phrase.txt`. Back it up to offline storage now — it is your only recovery option. Then delete it: `shred -u ~/.lnd/seed_phrase.txt`"

Wait for confirmation, then enable auto-unlock and the systemd service:

```bash
sudo ${CLAUDE_SKILL_DIR}/neutrino/neutrino_setup3.sh
```

---

### Neutrino remote signer (signer node only)

This path installs LND only (no litd, no web UI) and uses Neutrino as the Bitcoin backend. The routing node runs litd with bitcoind separately.

**Before running the script**, ask the user for:
- The IP address of this signer machine (the routing node connects to it over gRPC)
- A node alias

Then generate the config files using the Bash tool. Read `${CLAUDE_SKILL_DIR}/neutrino/remote-signer-neutrino-binary.sh` to see the exact config structure the script would produce, then reproduce it with the user's values substituted in:

```bash
mkdir -p ~/.lnd
openssl rand -hex 21 > ~/.lnd/wallet_password
chmod 600 ~/.lnd/wallet_password
# Write ~/.lnd/lnd.conf via heredoc — structure is in remote-signer-neutrino-binary.sh
```

Once the config files exist, run the script:

```bash
chmod +x ${CLAUDE_SKILL_DIR}/neutrino/remote-signer-neutrino-binary.sh
sudo ${CLAUDE_SKILL_DIR}/neutrino/remote-signer-neutrino-binary.sh
```

The script installs LND, skips config generation (files already exist), creates the `lnd` systemd service, and **automatically creates and initialises the wallet via REST** — no manual `lncli create` step needed.

When the script completes, prompt the user to back up the seed:

> "Your seed phrase has been saved to `~/.lnd/seed_phrase.txt`. Back it up to offline storage now — it is your only recovery option. Then delete it: `shred -u ~/.lnd/seed_phrase.txt`"

Then follow Step 2 — Transfer Files and Step 3 — Routing Node from the Remote Signer Setup section below.

---

## Bitcoind + litd Setup (explicit request only)

Use this path when the user has specifically asked for a bitcoind-backed node. Run bitcoind first, then litd.

### Step 1 — bitcoind

The bitcoind script generates its own RPC password via `rpcauth.py` — Claude cannot pre-generate it. Before running, tell the user:

> "The bitcoind setup script will display an RPC password. Please copy it and paste it back to me when prompted — I'll use it to configure litd. The script will also ask which network you want (signet or mainnet)."

```bash
sudo ${CLAUDE_SKILL_DIR}/bitcoind_setup_binary.sh
# Source build alternative: sudo ${CLAUDE_SKILL_DIR}/bitcoind_setup.sh
```

After the script completes, ask the user: "What RPC password did the script display?" Then store it — you will use it in the next step. Verify bitcoind is running before continuing:

```bash
bitcoin-cli -signet getblockchaininfo   # signet
bitcoin-cli getblockchaininfo           # mainnet
```

### Step 2 — litd

**Before running the script**, ask the user for:
- UI password (for the litd web interface)
- Node alias

Then pre-generate the config files. Read `${CLAUDE_SKILL_DIR}/litd_setup_binary.sh` to see the exact config structure, then reproduce it using the network from Before You Begin Step 2, the RPC password from Step 1 above, and the UI password and alias just collected:

```bash
mkdir -p ~/.lnd ~/.lit
openssl rand -hex 21 > ~/.lnd/wallet_password
chmod 600 ~/.lnd/wallet_password
# Write ~/.lit/lit.conf via heredoc — structure is in litd_setup_binary.sh
```

Once config files exist, run the install script — it installs litd and skips the interactive config section:

```bash
sudo ${CLAUDE_SKILL_DIR}/litd_setup_binary.sh
```

After the install script completes, create the wallet automatically:

```bash
chmod +x ${CLAUDE_SKILL_DIR}/litd_wallet_create.sh
sudo ${CLAUDE_SKILL_DIR}/litd_wallet_create.sh
```

This starts litd in the background, creates the wallet via the LND REST API, saves the seed to `~/.lnd/seed_phrase.txt`, and stops litd. Prompt the user to back up and delete the seed:

> "Your seed phrase has been saved to `~/.lnd/seed_phrase.txt`. Back it up to offline storage now — it is your only recovery option. Then delete it: `shred -u ~/.lnd/seed_phrase.txt`"

Wait for confirmation, then enable auto-unlock and the systemd service:

```bash
sudo ${CLAUDE_SKILL_DIR}/litd_setup3.sh
```

**Source build:** `litd_setup.sh` (installs Go/Node/Yarn) → new shell → `litd_setup2.sh` (builds litd) → `source ~/.profile` if `litd`/`lncli` are not found → create wallet as above → `litd_setup3.sh`.

---

## Remote Signer Setup

### Step 1 — Signer Node

Two options depending on whether bitcoind is available on the signer machine:

**Neutrino signer (default — no bitcoind needed):**

Follow the pre-generation steps in the **Neutrino remote signer** section above — collect signer IP and node alias, generate `wallet_password` and `lnd.conf`, then run:

```bash
chmod +x ${CLAUDE_SKILL_DIR}/neutrino/remote-signer-neutrino-binary.sh
sudo ${CLAUDE_SKILL_DIR}/neutrino/remote-signer-neutrino-binary.sh
```

**bitcoind signer (explicit request only — bitcoind must already be installed and running):**
```bash
chmod +x ${CLAUDE_SKILL_DIR}/remote-signer/remote-signer-binary.sh
sudo ${CLAUDE_SKILL_DIR}/remote-signer/remote-signer-binary.sh
```

The script:
1. Installs LND v0.20.1-beta (GPG + SHA256 verified)
2. Creates `~/.lnd/` and generates `wallet_password`
3. Configures `lnd.conf` for signing role (no p2p, `nolisten=true`, gRPC on `0.0.0.0:10009`, `tlsextraip=<signer-ip>`)
4. Creates and starts `lnd.service` via systemd
5. Generates the wallet seed via REST (`/v1/genseed`), initialises the wallet, saves seed to `~/.lnd/seed_phrase.txt`
6. Exports xpubs: `lncli wallet accounts list > ~/.lnd/accounts.json`
7. Bakes a minimum-permission signing macaroon: `~/.lnd/signer.macaroon`

**Immediately after the script completes**, back up the seed:

```bash
cat ~/.lnd/seed_phrase.txt
shred -u ~/.lnd/seed_phrase.txt
```

---

### Step 2 — Transfer Files to Routing Node

Copy three files from the signer to the routing node. The signer's TLS cert **must** be renamed to avoid collision with litd's own cert.

```bash
# Run from routing node (or adjust source/destination)
scp ubuntu@<signer-ip>:~/.lnd/tls.cert        ~/.lnd/signer-tls.cert
scp ubuntu@<signer-ip>:~/.lnd/signer.macaroon ~/.lnd/signer.macaroon
scp ubuntu@<signer-ip>:~/.lnd/accounts.json   ~/.lnd/accounts.json
```

Verify all three files are present before running the routing node script:
```bash
ls -la ~/.lnd/signer-tls.cert ~/.lnd/signer.macaroon ~/.lnd/accounts.json
```

---

### Step 3 — Routing Node

Run on the routing node machine. Bitcoind must already be installed and running. All three signer files must be in `~/.lnd/` before running.

**Before running the script**, the routing node script also has interactive prompts. Pre-generate the config using the same pattern as the bitcoind + litd section:

1. If bitcoind was just set up on this machine, ask the user for the RPC password it generated. If bitcoind was already running, ask the user for the existing RPC password.
2. Ask the user for: UI password, node alias. (Network is from Before You Begin Step 2; signer IP is from Step 1.)
3. Generate config files. Read `${CLAUDE_SKILL_DIR}/remote-signer/routing-node-binary.sh` for the exact `lit.conf` structure — it includes `lnd.remotesigner.*` settings pointing at the signer IP from Step 1:

```bash
mkdir -p ~/.lnd ~/.lit
openssl rand -hex 21 > ~/.lnd/wallet_password
chmod 600 ~/.lnd/wallet_password
# Write ~/.lit/lit.conf via heredoc — structure is in routing-node-binary.sh
```

**Binary install:**
```bash
chmod +x ${CLAUDE_SKILL_DIR}/remote-signer/routing-node-binary.sh ${CLAUDE_SKILL_DIR}/remote-signer/routing-node3.sh
sudo ${CLAUDE_SKILL_DIR}/remote-signer/routing-node-binary.sh
```

The script:
1. Installs litd v0.16.1-alpha (GPG + SHA256 verified)
2. Checks for the three signer files — exits with `scp` instructions if any are missing
3. Generates `~/.lit/lit.conf` with `remotesigner.*` settings pointing at the signer
4. Pauses — you must create the watch-only wallet before continuing

**Create the watch-only wallet (manual step between scripts):**
```bash
# Start litd without systemd for first-time wallet setup
litd

# In a new terminal — initialise watch-only wallet from signer's xpubs
lncli --network=signet createwatchonly ~/.lnd/accounts.json
# Use the password from ~/.lnd/wallet_password

# Stop litd (Ctrl-C)
```

**Enable auto-unlock and systemd service:**
```bash
sudo ${CLAUDE_SKILL_DIR}/remote-signer/routing-node3.sh
```

`routing-node3.sh` uncomments the wallet unlock lines in `lit.conf` and creates `litd.service`.

**Source build:** `routing-node.sh` (installs Go/Node/Yarn) → new shell → `routing-node2.sh` (builds litd) → `source ~/.profile` if `litd`/`lncli` are not found → create watch-only wallet as above → `routing-node3.sh`.

---

## Verification Commands

```bash
# Node info (shows synced_to_chain, synced_to_graph, pubkey)
lncli --network=signet getinfo

# Check wallet balance
lncli --network=signet walletbalance

# List peers
lncli --network=signet listpeers

# Connect to a peer (required before synced_to_graph=true)
lncli --network=signet connect <pubkey>@<host>:<port>

# Check service status
systemctl status litd
systemctl status lnd        # signer node only
systemctl status bitcoind

# Tail logs
journalctl -fu litd
journalctl -fu lnd

# Verify signer connectivity from routing node
lncli --network=signet --macaroonpath=~/.lnd/signer.macaroon \
  --tlscertpath=~/.lnd/signer-tls.cert \
  --rpcserver=<signer-ip>:10009 \
  getinfo
```

---

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| `synced_to_graph: false` on routing node | Connect to at least one peer: `lncli connect <pubkey>@<host>:<port>` |
| Neutrino stuck at `num_peers: 0` on mainnet | No hardcoded mainnet peers — LND uses DNS seeding which can take a few minutes. If still 0, test a candidate peer with `nc -zv <host> 8333` and add working ones to `lnd.conf` as `neutrino.connect=<host>:8333`. |
| Script exits "Missing required signer file" | Run `scp` to copy all three files from signer — see Step 2 above. Don't forget to rename `tls.cert` → `signer-tls.cert`. |
| `tls.cert` and `signer-tls.cert` confusion | The routing node generates its own `~/.lit/tls.cert`. The signer's cert must live at `~/.lnd/signer-tls.cert`. `lit.conf` must point `remotesigner.tlscertpath` to the signer cert, not the local one. |
| Watch-only wallet creation fails | `createwatchonly` must be run while litd is running but *before* auto-unlock lines are uncommented in `lit.conf`. Run `routing-node3.sh` only after the wallet exists. |
| `wallet-unlock-allow-create=true` causes issues | This flag is intentionally commented out in the initial config. `routing-node3.sh` uncomments it. Do not uncomment manually before the watch-only wallet is created. |
| Signer not reachable from routing node | Check that port 10009 is open between the two machines. The signer's `lnd.conf` must have `tlsextraip=<signer-ip>` set before the wallet was initialised (TLS cert bakes the IP in). If the IP was wrong, delete `~/.lnd/tls.cert` and `~/.lnd/tls.key` and restart lnd to regenerate. |
| Scripts fail on re-run after interruption | All scripts check existing state and skip completed steps — safe to re-run. |
| Seed phrase not backed up | The remote signer scripts and `litd_wallet_create.sh` all save the seed to `~/.lnd/seed_phrase.txt`. Back it up to offline storage and then `shred -u ~/.lnd/seed_phrase.txt` immediately. |
| `lncli` uses wrong macaroon/network | Always pass `--network=<mainnet|signet>` and confirm `--macaroonpath` points to the correct node's macaroon. Omitting `--network` defaults to mainnet. |
| litd binary not found in PATH after install | Binary installs go to `/usr/local/bin` — check it is in `$PATH`. Source builds install to `~/go/bin` — run `source ~/.profile` or start a new shell after `litd_setup2.sh` or `routing-node2.sh` if `litd` or `lncli` are not found. |
