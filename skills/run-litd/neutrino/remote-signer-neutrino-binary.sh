#!/bin/bash

# LND Remote Signer Setup Script with Neutrino Backend (Binary Install)
# Tested on Ubuntu 24.04
#
# Sets up an LND remote signer node using Neutrino as the Bitcoin backend.
# No bitcoind required — Neutrino connects directly to peers that support
# BIP 157/158 compact block filters.
#
# Use this on the SIGNER machine. The signer holds private keys, should not
# be internet-exposed, and only needs to be reachable by the routing node.
#
# After this script completes, copy three files to the routing node:
#   ~/.lnd/tls.cert       → rename to signer-tls.cert on routing node
#   ~/.lnd/signer.macaroon
#   ~/.lnd/accounts.json

set -e

# Variables
USER_HOME=$(eval echo ~${SUDO_USER:-$USER})
LND_DIR="$USER_HOME/.lnd"
LND_CONF_FILE="$LND_DIR/lnd.conf"
WALLET_PASSWORD_FILE="$LND_DIR/wallet_password"
SERVICE_FILE="/etc/systemd/system/lnd.service"
LND_VERSION="v0.20.1-beta"
BINARY_URL="https://github.com/lightningnetwork/lnd/releases/download/$LND_VERSION/lnd-linux-amd64-$LND_VERSION.tar.gz"
MANIFEST_URL="https://github.com/lightningnetwork/lnd/releases/download/$LND_VERSION/manifest-$LND_VERSION.txt"
SIGNATURE_URL="https://github.com/lightningnetwork/lnd/releases/download/$LND_VERSION/manifest-roasbeef-$LND_VERSION.sig"
KEY_ID="296212681AADF05656A2CDEE90525F7DEEE0AD86"
KEY_SERVER="hkps://keyserver.ubuntu.com"
DOWNLOAD_DIR="/tmp/lnd_release_verification"

# Default Neutrino peers (must support BIP 157/158 compact block filters)
# No hardcoded mainnet peers — LND discovers peers via Bitcoin DNS seeds automatically.
# Add peers manually when prompted, or leave blank to rely on DNS seeding.
MAINNET_PEERS=()
SIGNET_PEERS=(
    "172.233.20.188:38333"
)

# Check root
if [[ $EUID -ne 0 ]]; then
    echo "[-] This script must be run as root. Use sudo."
    exit 1
fi

# Install dependencies
echo "[+] Installing dependencies..."
apt-get update
apt-get install -y curl jq wget

# Install LND from binary
echo "[+] Checking if LND is already installed..."
if [[ -f "/usr/local/bin/lnd" && -f "/usr/local/bin/lncli" ]]; then
    echo "[+] LND is already installed. Skipping."
else
    mkdir -p "$DOWNLOAD_DIR"
    cd "$DOWNLOAD_DIR" || { echo "[-] Failed to navigate to download directory."; exit 1; }

    echo "[+] Importing LND signing key..."
    if ! curl -sf "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x$KEY_ID" | gpg --import 2>/dev/null; then
        echo "[!] HTTPS key fetch failed, trying HKP..."
        gpg --keyserver "$KEY_SERVER" --recv-keys "$KEY_ID" || { echo "[-] Failed to import PGP key."; exit 1; }
    fi

    echo "[+] Downloading LND binary, manifest, and signature..."
    wget "$BINARY_URL"    || { echo "[-] Failed to download binary."; exit 1; }
    wget "$MANIFEST_URL"  || { echo "[-] Failed to download manifest."; exit 1; }
    wget "$SIGNATURE_URL" || { echo "[-] Failed to download signature."; exit 1; }

    echo "[+] Verifying PGP signature..."
    GPG_OUTPUT=$(gpg --verify "$(basename "$SIGNATURE_URL")" "$(basename "$MANIFEST_URL")" 2>&1 || true)
    if echo "$GPG_OUTPUT" | grep -q "$KEY_ID"; then
        echo "[+] Signature verified."
    else
        echo "[-] Signature verification failed. Exiting."
        echo "$GPG_OUTPUT"
        exit 1
    fi

    echo "[+] Verifying SHA256 checksum..."
    BINARY_HASH=$(sha256sum "$(basename "$BINARY_URL")" | awk '{print $1}')
    if grep -q "$BINARY_HASH" "$(basename "$MANIFEST_URL")"; then
        echo "[+] SHA256 verified."
    else
        echo "[-] SHA256 verification failed. Exiting."
        exit 1
    fi

    echo "[+] Extracting and installing LND..."
    tar -xzf "$DOWNLOAD_DIR/lnd-linux-amd64-$LND_VERSION.tar.gz" -C "$DOWNLOAD_DIR" --strip-components=1
    sudo install -m 0755 -o root -g root "$DOWNLOAD_DIR/lnd" /usr/local/bin/lnd
    sudo install -m 0755 -o root -g root "$DOWNLOAD_DIR/lncli" /usr/local/bin/lncli
    rm -rf "$DOWNLOAD_DIR"

    cd "$USER_HOME"
    echo "[+] LND installed successfully."
fi

# Set up ~/.lnd directory
echo "[+] Ensuring ~/.lnd directory exists..."
if [[ ! -d $LND_DIR ]]; then
    mkdir -p $LND_DIR
    sudo chown -R ${SUDO_USER:-$USER}:${SUDO_USER:-$USER} $LND_DIR
else
    echo "[!] $LND_DIR already exists."
fi

# Generate wallet password
echo "[+] Checking for wallet password file..."
if [[ -f $WALLET_PASSWORD_FILE && -s $WALLET_PASSWORD_FILE ]]; then
    echo "[+] Wallet password already exists. Skipping."
else
    openssl rand -hex 21 > $WALLET_PASSWORD_FILE
    sudo chown ${SUDO_USER:-$USER}:${SUDO_USER:-$USER} $WALLET_PASSWORD_FILE
    chmod 600 $WALLET_PASSWORD_FILE
    echo "[+] Wallet password saved to $WALLET_PASSWORD_FILE."
fi

# Configure LND
if [[ -f $LND_CONF_FILE && -s $LND_CONF_FILE ]]; then
    echo "[+] lnd.conf already exists. Skipping."
else
    echo "[+] Configuring LND remote signer with Neutrino backend..."

    # Network
    while true; do
        read -p "Which network? [mainnet/signet]: " NETWORK
        NETWORK=$(echo "$NETWORK" | tr '[:upper:]' '[:lower:]')
        if [[ "$NETWORK" == "mainnet" || "$NETWORK" == "signet" ]]; then
            break
        fi
        echo "[-] Please enter 'mainnet' or 'signet'."
    done

    # Mainnet warning
    if [[ "$NETWORK" == "mainnet" ]]; then
        echo ""
        echo "[!] WARNING: Neutrino is not recommended for mainnet production use."
        echo "    The signer node depends on external peers for block data."
        echo "    For a production signer, use remote-signer-binary.sh (bitcoind) instead."
        echo ""
        read -p "Continue with Neutrino on mainnet anyway? (yes/no): " CONFIRM
        if [[ "$CONFIRM" != "yes" ]]; then
            echo "[-] Exiting. Run remote-signer-binary.sh for a production mainnet signer."
            exit 0
        fi
    fi

    read -p "Enter the IP address of this signer node (used by the routing node to connect): " SIGNER_IP
    if [[ -z $SIGNER_IP ]]; then
        echo "[-] Signer IP cannot be empty. Exiting."
        exit 1
    fi

    read -p "Enter a node alias: " NODE_ALIAS

    # Neutrino peers
    if [[ "$NETWORK" == "mainnet" ]]; then
        DEFAULT_PEERS=("${MAINNET_PEERS[@]}")
        NETWORK_FLAG="bitcoin.mainnet=1"
        FEE_LINE=$'\n[fee]\nfee.url=https://nodes.lightning.computer/fees/v1/btc-fee-estimates.json'
    else
        DEFAULT_PEERS=("${SIGNET_PEERS[@]}")
        NETWORK_FLAG="bitcoin.signet=1"
        FEE_LINE=""
    fi

    PEER_CONFIG=""
    echo ""
    echo "[+] Default Neutrino peers for $NETWORK:"
    for PEER in "${DEFAULT_PEERS[@]}"; do
        echo "    $PEER"
        PEER_CONFIG+="neutrino.connect=$PEER"$'\n'
    done

    read -p "Add additional Neutrino peers? (comma-separated, or press Enter to skip): " EXTRA_PEERS
    if [[ -n "$EXTRA_PEERS" ]]; then
        IFS=',' read -ra EXTRA_PEER_ARRAY <<< "$EXTRA_PEERS"
        for PEER in "${EXTRA_PEER_ARRAY[@]}"; do
            PEER=$(echo "$PEER" | tr -d '[:space:]')
            PEER_CONFIG+="neutrino.connect=$PEER"$'\n'
        done
    fi

    sudo chown -R ${SUDO_USER:-$USER}:${SUDO_USER:-$USER} $LND_DIR

    cat <<EOF > $LND_CONF_FILE
[Application Options]
# No p2p — signer should not be internet-exposed
nolisten=true

# gRPC for routing node to connect
rpclisten=0.0.0.0:10009
restlisten=0.0.0.0:8080

# Include signer IP in TLS cert so routing node can verify it
tlsextraip=$SIGNER_IP

# Auto-unlock wallet on startup
wallet-unlock-password-file=$WALLET_PASSWORD_FILE
wallet-unlock-allow-create=true

debuglevel=info
alias=$NODE_ALIAS

[Bitcoin]
bitcoin.active=1
$NETWORK_FLAG
bitcoin.node=neutrino

[Neutrino]
${PEER_CONFIG}${FEE_LINE}
EOF

    sudo chown ${SUDO_USER:-$USER}:${SUDO_USER:-$USER} $LND_CONF_FILE
    echo "[+] lnd.conf created at $LND_CONF_FILE."
fi

# Create systemd service (no bitcoind dependency)
if [[ ! -f "$SERVICE_FILE" ]]; then
    echo "[+] Creating systemd service for lnd..."
    LND_PATH=$(which lnd)
    cat <<EOF > $SERVICE_FILE
[Unit]
Description=LND Remote Signer (Neutrino)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$LND_PATH

User=${SUDO_USER:-$USER}
Group=${SUDO_USER:-$USER}

Type=simple
Restart=always
RestartSec=120

[Install]
WantedBy=multi-user.target
EOF
    echo "[+] Systemd service created."
else
    echo "[!] Systemd service already exists. Skipping."
fi

# Enable and start service
systemctl enable lnd
systemctl daemon-reload
if ! systemctl is-active --quiet lnd; then
    systemctl start lnd
    echo "[+] lnd service started."
else
    echo "[!] lnd service is already running."
fi

# Detect network from config
if grep -q "bitcoin.signet=1" "$LND_CONF_FILE" 2>/dev/null; then
    NETWORK="signet"
else
    NETWORK="mainnet"
fi

MACAROON_PATH="$LND_DIR/data/chain/bitcoin/$NETWORK/admin.macaroon"
SEED_FILE="$LND_DIR/seed_phrase.txt"
XPUB_FILE="$LND_DIR/accounts.json"
SIGNER_MACAROON="$LND_DIR/signer.macaroon"
# mainnet Neutrino takes significantly longer to start than signet
if [[ "$NETWORK" == "mainnet" ]]; then
    TIMEOUT=600
else
    TIMEOUT=180
fi

if [[ -f "$MACAROON_PATH" ]]; then
    echo "[!] Wallet already initialized. Skipping wallet setup."
else
    # Wait for TLS cert
    echo "[+] Waiting for LND to generate TLS certificate..."
    ELAPSED=0
    while [[ ! -f "$LND_DIR/tls.cert" ]]; do
        sleep 2; ELAPSED=$((ELAPSED + 2))
        if ! systemctl is-active --quiet lnd; then echo "[-] lnd exited unexpectedly — check 'journalctl -u lnd' for errors."; exit 1; fi
        if [[ $ELAPSED -ge $TIMEOUT ]]; then echo "[-] Timed out waiting for TLS cert."; exit 1; fi
    done
    echo "[+] TLS certificate ready."

    # Wait for REST API
    echo "[+] Waiting for LND REST API..."
    ELAPSED=0
    while ! curl -sf --cacert "$LND_DIR/tls.cert" https://localhost:8080/v1/state > /dev/null 2>&1; do
        sleep 2; ELAPSED=$((ELAPSED + 2))
        if [[ $ELAPSED -ge $TIMEOUT ]]; then echo "[-] Timed out waiting for REST API."; exit 1; fi
    done
    echo "[+] LND REST API ready."

    # Generate seed
    echo "[+] Generating wallet seed..."
    SEED_JSON=$(curl -sf --cacert "$LND_DIR/tls.cert" https://localhost:8080/v1/genseed)
    if [[ -z "$SEED_JSON" ]]; then echo "[-] Failed to generate seed."; exit 1; fi

    MNEMONIC=$(echo "$SEED_JSON" | jq -r '.cipher_seed_mnemonic | join(" ")')
    MNEMONIC_ARRAY=$(echo "$SEED_JSON" | jq -c '.cipher_seed_mnemonic')

    echo "$MNEMONIC" > "$SEED_FILE"
    chown ${SUDO_USER:-$USER}:${SUDO_USER:-$USER} "$SEED_FILE"
    chmod 600 "$SEED_FILE"

    echo ""
    echo "============================================================"
    echo "  !! WALLET SEED PHRASE - BACK THIS UP IMMEDIATELY !!      "
    echo "  This is your ONLY recovery option if this node is lost.  "
    echo "============================================================"
    echo "$MNEMONIC"
    echo "============================================================"
    echo "  Saved to: $SEED_FILE  (chmod 600)"
    echo "  Once backed up, delete it:  shred -u $SEED_FILE"
    echo "============================================================"
    echo ""

    # Initialize wallet
    echo "[+] Initializing wallet..."
    WALLET_PASSWORD_B64=$(tr -d '\n' < "$WALLET_PASSWORD_FILE" | base64 -w 0)
    INIT_RESPONSE=$(curl -sf --cacert "$LND_DIR/tls.cert" \
        -X POST https://localhost:8080/v1/initwallet \
        -H 'Content-Type: application/json' \
        -d "{\"wallet_password\": \"$WALLET_PASSWORD_B64\", \"cipher_seed_mnemonic\": $MNEMONIC_ARRAY}")

    if [[ -z "$INIT_RESPONSE" ]]; then echo "[-] No response from initwallet."; exit 1; fi
    if echo "$INIT_RESPONSE" | jq -e '.code' > /dev/null 2>&1; then
        echo "[-] Wallet init failed: $(echo "$INIT_RESPONSE" | jq -r '.message')"
        exit 1
    fi
    echo "[+] Wallet initialized, waiting for unlock..."

    ELAPSED=0
    while [[ ! -f "$MACAROON_PATH" ]]; do
        sleep 2; ELAPSED=$((ELAPSED + 2))
        if [[ $ELAPSED -ge $TIMEOUT ]]; then echo "[-] Timed out waiting for wallet unlock."; exit 1; fi
    done
    echo "[+] Wallet unlocked."

    # Wait for gRPC
    echo "[+] Waiting for LND gRPC..."
    ELAPSED=0
    while ! sudo -u ${SUDO_USER:-$USER} /usr/local/bin/lncli \
            --network="$NETWORK" \
            --macaroonpath="$MACAROON_PATH" \
            --tlscertpath="$LND_DIR/tls.cert" \
            getinfo > /dev/null 2>&1; do
        sleep 2; ELAPSED=$((ELAPSED + 2))
        if [[ $ELAPSED -ge $TIMEOUT ]]; then echo "[-] Timed out waiting for gRPC."; exit 1; fi
    done
    echo "[+] LND gRPC ready."

    # Export xpubs
    echo "[+] Exporting account xpubs..."
    sudo -u ${SUDO_USER:-$USER} /usr/local/bin/lncli \
        --network="$NETWORK" \
        --macaroonpath="$MACAROON_PATH" \
        --tlscertpath="$LND_DIR/tls.cert" \
        wallet accounts list > "$XPUB_FILE"
    chown ${SUDO_USER:-$USER}:${SUDO_USER:-$USER} "$XPUB_FILE"
    echo "[+] Account xpubs saved to $XPUB_FILE."

    # Bake signing macaroon
    echo "[+] Baking signing macaroon..."
    sudo -u ${SUDO_USER:-$USER} /usr/local/bin/lncli \
        --network="$NETWORK" \
        --macaroonpath="$MACAROON_PATH" \
        --tlscertpath="$LND_DIR/tls.cert" \
        bakemacaroon \
        signer:generate signer:read signer:write \
        uri:/walletrpc.WalletKit/DeriveNextKey \
        uri:/walletrpc.WalletKit/DeriveKey \
        uri:/walletrpc.WalletKit/SignPsbt \
        uri:/walletrpc.WalletKit/FinalizePsbt \
        --save_to "$SIGNER_MACAROON"
    chown ${SUDO_USER:-$USER}:${SUDO_USER:-$USER} "$SIGNER_MACAROON"
    echo "[+] Signing macaroon saved to $SIGNER_MACAROON."
fi

cat <<"EOF"

[+] LND Remote Signer (Neutrino) setup complete!

Copy these three files to your routing node:
  ~/.lnd/tls.cert         → rename to signer-tls.cert on routing node
  ~/.lnd/signer.macaroon
  ~/.lnd/accounts.json

IMPORTANT: Back up your seed phrase then delete it from disk:
  shred -u ~/.lnd/seed_phrase.txt

EOF
