#!/bin/bash

# litd Setup Script with Neutrino Backend (Binary Install)
# Tested on Ubuntu 24.04
#
# Neutrino is a lightweight SPV Bitcoin client built into LND — no bitcoind required.
# Use this script instead of bitcoind_setup_binary.sh + litd_setup_binary.sh.
#
# NOTE: Neutrino is suitable for signet and development. It is NOT recommended for
# mainnet production routing nodes — it depends on external peers for block data,
# so if those peers go down or are overloaded, your node suffers.
# For a mainnet routing node, use bitcoind_setup_binary.sh + litd_setup_binary.sh.

set -e

# Variables
USER_HOME=$(eval echo ~${SUDO_USER:-$USER})
LIT_CONF_DIR="$USER_HOME/.lit"
LIT_CONF_FILE="$LIT_CONF_DIR/lit.conf"
LND_DIR="$USER_HOME/.lnd"
WALLET_PASSWORD_FILE="$LND_DIR/wallet_password"

LITD_VERSION="v0.16.1-alpha"
BINARY_URL="https://github.com/lightninglabs/lightning-terminal/releases/download/$LITD_VERSION/lightning-terminal-linux-amd64-$LITD_VERSION.tar.gz"
SIGNATURE_URL="https://github.com/lightninglabs/lightning-terminal/releases/download/$LITD_VERSION/manifest-ellemouton-$LITD_VERSION.sig"
MANIFEST_URL="https://github.com/lightninglabs/lightning-terminal/releases/download/$LITD_VERSION/manifest-$LITD_VERSION.txt"
KEY_ID="26984CB69EB8C4A26196F7A4D7D916376026F177"
KEY_SERVER="hkps://keyserver.ubuntu.com"
DOWNLOAD_DIR="/tmp/litd_release_verification"

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

# Install litd from binary
echo "[+] Checking if Lightning Terminal is already installed..."
if [[ -f "/usr/local/bin/litd" ]]; then
    echo "[+] litd is already installed. Skipping installation."
else
    echo "[+] litd not found. Proceeding with installation."

    mkdir -p "$DOWNLOAD_DIR"
    cd "$DOWNLOAD_DIR" || { echo "[-] Failed to navigate to download directory."; exit 1; }

    echo "[+] Importing signing key..."
    if ! curl -sf "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x$KEY_ID" | gpg --import 2>/dev/null; then
        echo "[!] HTTPS key fetch failed, trying HKP..."
        gpg --keyserver "$KEY_SERVER" --recv-keys "$KEY_ID" || { echo "[-] Failed to import PGP key."; exit 1; }
    fi

    echo "[+] Downloading litd binary, signature, and manifest..."
    wget "$BINARY_URL"   || { echo "[-] Failed to download binary."; exit 1; }
    wget "$SIGNATURE_URL" || { echo "[-] Failed to download signature."; exit 1; }
    wget "$MANIFEST_URL"  || { echo "[-] Failed to download manifest."; exit 1; }

    echo "[+] Verifying signature..."
    gpg --verify "$(basename "$SIGNATURE_URL")" "$(basename "$MANIFEST_URL")" 2>&1 | grep "$KEY_ID" > /dev/null
    if [[ $? -eq 0 ]]; then
        echo "[+] Signature verified."
    else
        echo "[-] Signature verification failed. Exiting."
        exit 1
    fi

    echo "[+] Verifying SHA256 checksum..."
    grep "$(sha256sum "$(basename "$BINARY_URL")" | awk '{print $1}')" "$(basename "$MANIFEST_URL")" > /dev/null
    if [[ $? -eq 0 ]]; then
        echo "[+] SHA256 verified."
    else
        echo "[-] SHA256 verification failed. Exiting."
        exit 1
    fi

    echo "[+] Extracting and installing litd..."
    tar -xvzf "$DOWNLOAD_DIR/lightning-terminal-linux-amd64-$LITD_VERSION.tar.gz" -C "$DOWNLOAD_DIR" --strip-components=1
    find "$DOWNLOAD_DIR" -maxdepth 1 -type f -executable -exec sudo install -m 0755 -o root -g root {} /usr/local/bin/ \;
    rm -rf "$DOWNLOAD_DIR"
    echo "[+] litd installed successfully."

    cd "$USER_HOME" || { echo "[-] Failed to return to home directory."; exit 1; }
fi

# Set up ~/.lnd directory
echo "[+] Ensuring ~/.lnd directory exists..."
if [[ ! -d $LND_DIR ]]; then
    mkdir -p $LND_DIR
    sudo chown -R ${SUDO_USER:-$USER}:${SUDO_USER:-$USER} $LND_DIR
    echo "[+] Created $LND_DIR."
else
    echo "[!] $LND_DIR already exists."
fi

# Generate wallet password
echo "[+] Checking for wallet password file..."
if [[ -f $WALLET_PASSWORD_FILE && -s $WALLET_PASSWORD_FILE ]]; then
    echo "[+] Wallet password already exists. Skipping."
else
    echo "[+] Generating wallet password..."
    openssl rand -hex 21 > $WALLET_PASSWORD_FILE
    sudo chown ${SUDO_USER:-$USER}:${SUDO_USER:-$USER} $WALLET_PASSWORD_FILE
    echo "[+] Wallet password saved to $WALLET_PASSWORD_FILE."
fi

# Configure lit.conf
if [[ -f $LIT_CONF_FILE && -s $LIT_CONF_FILE ]]; then
    echo "[+] Configuration file already exists. Skipping."
else
    echo "[+] Configuring litd with Neutrino backend..."

    # Network selection
    while true; do
        read -p "Which network? [mainnet/signet]: " NETWORK
        NETWORK=$(echo "$NETWORK" | tr '[:upper:]' '[:lower:]')
        if [[ "$NETWORK" == "mainnet" || "$NETWORK" == "signet" ]]; then
            break
        fi
        echo "[-] Please enter 'mainnet' or 'signet'."
    done

    # Warn on mainnet
    if [[ "$NETWORK" == "mainnet" ]]; then
        echo ""
        echo "[!] WARNING: Neutrino is not recommended for mainnet production routing nodes."
        echo "    It depends on external peers for block data — if peers go down or are"
        echo "    overloaded, your node suffers. For a production routing node, use"
        echo "    bitcoind_setup_binary.sh + litd_setup_binary.sh instead."
        echo ""
        read -p "Continue with Neutrino on mainnet anyway? (yes/no): " CONFIRM
        if [[ "$CONFIRM" != "yes" ]]; then
            echo "[-] Exiting. Run bitcoind_setup_binary.sh + litd_setup_binary.sh for mainnet."
            exit 0
        fi
    fi

    read -s -p "Enter a UI password for litd: " UI_PASSWORD
    echo
    if [[ -z $UI_PASSWORD ]]; then
        echo "[-] UI password cannot be empty. Exiting."
        exit 1
    fi

    read -p "Enter a Lightning Node alias: " NODE_ALIAS

    # Set network-specific values
    if [[ "$NETWORK" == "mainnet" ]]; then
        DEFAULT_PEERS=("${MAINNET_PEERS[@]}")
        NETWORK_FLAG="lnd.bitcoin.mainnet=1"
        FEE_LINE="lnd.fee.url=https://nodes.lightning.computer/fees/v1/btc-fee-estimates.json"
        SIGNET_OPTS="#pool-mode=disable
#loop-mode=disable
#autopilot.disable=true"
    else
        DEFAULT_PEERS=("${SIGNET_PEERS[@]}")
        NETWORK_FLAG="lnd.bitcoin.signet=1"
        FEE_LINE=""
        SIGNET_OPTS="pool-mode=disable
loop-mode=disable
autopilot.disable=true"
    fi

    # Build peer config lines
    PEER_CONFIG=""
    echo ""
    echo "[+] Default Neutrino peers for $NETWORK:"
    for PEER in "${DEFAULT_PEERS[@]}"; do
        echo "    $PEER"
        PEER_CONFIG+="lnd.neutrino.connect=$PEER"$'\n'
    done

    read -p "Add additional Neutrino peers? (comma-separated, or press Enter to skip): " EXTRA_PEERS
    if [[ -n "$EXTRA_PEERS" ]]; then
        IFS=',' read -ra EXTRA_PEER_ARRAY <<< "$EXTRA_PEERS"
        for PEER in "${EXTRA_PEER_ARRAY[@]}"; do
            PEER=$(echo "$PEER" | tr -d '[:space:]')
            PEER_CONFIG+="lnd.neutrino.connect=$PEER"$'\n'
        done
    fi

    mkdir -p $LIT_CONF_DIR
    sudo chown -R ${SUDO_USER:-$USER}:${SUDO_USER:-$USER} $LIT_CONF_DIR

    cat > $LIT_CONF_FILE <<EOF
# litd Settings
enablerest=true
httpslisten=0.0.0.0:8443
uipassword=$UI_PASSWORD
network=$NETWORK
lnd-mode=integrated
$SIGNET_OPTS

# Bitcoin Configuration (Neutrino — no bitcoind required)
lnd.bitcoin.active=1
lnd.bitcoin.node=neutrino
$NETWORK_FLAG

# Neutrino Peers (must support BIP 157/158 compact block filters)
${PEER_CONFIG}${FEE_LINE}

# LND General Settings
#lnd.wallet-unlock-password-file=$USER_HOME/.lnd/wallet_password
#lnd.wallet-unlock-allow-create=true
lnd.debuglevel=debug
lnd.alias=$NODE_ALIAS
lnd.maxpendingchannels=3
lnd.accept-keysend=true
lnd.accept-amp=true
lnd.rpcmiddleware.enable=true
lnd.autopilot.active=0

# LND Protocol Settings
lnd.protocol.simple-taproot-chans=true
lnd.protocol.simple-taproot-overlay-chans=true
lnd.protocol.option-scid-alias=true
lnd.protocol.zero-conf=true
lnd.protocol.custom-message=17

# Taproot Assets Settings (uncomment to enable)
#taproot-assets.rpclisten=0.0.0.0:10029
#taproot-assets.allow-public-uni-proof-courier=true
#taproot-assets.allow-public-stats=true
#taproot-assets.universe.public-access=rw
EOF

    sudo chown ${SUDO_USER:-$USER}:${SUDO_USER:-$USER} $LIT_CONF_FILE
    echo "[+] Configuration file created at $LIT_CONF_FILE."
fi

echo ""
echo "[+] litd is configured with Neutrino — no bitcoind required!"
echo ""
echo "    Next steps:"
echo "    1. Start litd manually as the non-root user:"
echo "       $ litd"
echo ""
echo "    2. In a new terminal tab, create the LND wallet:"
echo "       $ lncli --network=$NETWORK create"
echo "       Use the password from: cat $WALLET_PASSWORD_FILE"
echo "       BACK UP YOUR SEED PHRASE."
echo ""
echo "    3. Stop litd (Ctrl-C), then run the final script:"
echo "       $ sudo ./neutrino_setup3.sh"
