#!/bin/bash
# CYBER C2 - Ubuntu Setup Script
# Run this ONCE on a fresh Ubuntu system to install all dependencies

set -e

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
NC="\033[0m"

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           CYBER C2 - UBUNTU SETUP                             ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${YELLOW}[1/7] Updating system...${NC}"
sudo apt update && sudo apt upgrade -y

echo -e "${YELLOW}[2/7] Installing core dependencies...${NC}"
sudo apt install -y \
    python3 python3-pip python3-venv \
    redis-server \
    tor torsocks \
    curl wget git unzip \
    build-essential pkg-config libssl-dev \
    netcat-openbsd

echo -e "${YELLOW}[3/7] Installing Cloudflared...${NC}"
if ! command -v cloudflared &> /dev/null; then
    # Download cloudflared for Ubuntu/Debian
    ARCH=$(dpkg --print-architecture)
    wget -q "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb"
    sudo dpkg -i "cloudflared-linux-${ARCH}.deb"
    rm "cloudflared-linux-${ARCH}.deb"
    echo -e "${GREEN}  ✓ Cloudflared installed${NC}"
else
    echo -e "${GREEN}  ✓ Cloudflared already installed${NC}"
fi

echo -e "${YELLOW}[4/9] Installing Metasploit Framework...${NC}"
if ! command -v msfconsole &> /dev/null; then
    echo -e "${CYAN}  → Installing MSF (this takes a few minutes)...${NC}"
    curl https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > /tmp/msfinstall
    chmod +x /tmp/msfinstall
    sudo /tmp/msfinstall
    rm /tmp/msfinstall
    echo -e "${GREEN}  ✓ Metasploit Framework installed${NC}"
else
    echo -e "${GREEN}  ✓ Metasploit already installed ($(msfconsole --version 2>/dev/null | head -1))${NC}"
fi

echo -e "${YELLOW}[5/9] Installing Rust (for agent compilation)...${NC}"
if ! command -v cargo &> /dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    rustup target add x86_64-pc-windows-gnu
    sudo apt install -y mingw-w64
    echo -e "${GREEN}  ✓ Rust installed with Windows cross-compile${NC}"
else
    echo -e "${GREEN}  ✓ Rust already installed${NC}"
fi

echo -e "${YELLOW}[6/9] Installing Nim (for lightweight agents)...${NC}"
if ! command -v nim &> /dev/null; then
    echo -e "${CYAN}  → Installing Nim via choosenim...${NC}"
    curl https://nim-lang.org/choosenim/init.sh -sSf | sh -s -- -y
    export PATH="$HOME/.nimble/bin:$PATH"
    echo 'export PATH="$HOME/.nimble/bin:$PATH"' >> "$HOME/.bashrc"
    echo -e "${GREEN}  ✓ Nim installed${NC}"
else
    echo -e "${GREEN}  ✓ Nim already installed ($(nim --version 2>/dev/null | head -1))${NC}"
fi

echo -e "${YELLOW}[7/9] Setting up Python environment...${NC}"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
echo -e "${GREEN}  ✓ Python venv ready${NC}"

echo -e "${YELLOW}[8/9] Configuring Tor...${NC}"
# Enable Tor control port for circuit switching
sudo tee /etc/tor/torrc > /dev/null << 'EOF'
SocksPort 9050
ControlPort 9051
CookieAuthentication 0
EOF
sudo systemctl enable tor
sudo systemctl restart tor
echo -e "${GREEN}  ✓ Tor configured with control port 9051${NC}"

echo -e "${YELLOW}[9/9] Setting up directories...${NC}"
mkdir -p data payloads logs certs memory tasks
chmod +x start_c5.sh
echo -e "${GREEN}  ✓ Directories created${NC}"

# Generate self-signed cert if needed
if [ ! -f "certs/server.crt" ]; then
    mkdir -p certs
    openssl req -x509 -newkey rsa:4096 -keyout certs/server.key -out certs/server.crt -days 365 -nodes -subj "/CN=localhost"
    echo -e "${GREEN}  ✓ Self-signed certificate generated${NC}"
fi

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                    SETUP COMPLETE!                            ║${NC}"
echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║${NC}  ${GREEN}To start C2:${NC}                                               ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}    ${YELLOW}./start_c5.sh${NC}          # Without Tor                    ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}    ${YELLOW}./start_c5.sh --tor${NC}    # With Tor (recommended)         ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  ${GREEN}For VPN:${NC} Connect NordVPN/ProtonVPN BEFORE running         ${CYAN}║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
