# Final end-to-end check, run outside the app container so every path is real.
$docs = [Environment]::GetFolderPath('MyDocuments')
$out  = Join-Path $docs 'eDEX-Tron\verify-apps.txt'
$lines = @("checked $(Get-Date -Format o)", '')

function Add-Check($label, [bool]$ok, $detail = '') {
    $script:lines += ("{0,-4} {1,-34} {2}" -f $(if ($ok) { 'OK' } else { 'FAIL' }), $label, $detail)
}

# --- Windows Terminal
$wt = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (Test-Path $wt) {
    $raw = Get-Content $wt -Raw
    Add-Check 'Terminal: scheme present' ($raw -match '"eDEX Tron"')
    Add-Check 'Terminal: scheme selected' ($raw -match '"colorScheme"\s*:\s*"eDEX Tron"')
    Add-Check 'Terminal: Fira Mono set' ($raw -match 'Fira Mono')
    Add-Check 'Terminal: backup kept' (Test-Path "$wt.edex-backup")
} else { Add-Check 'Terminal settings.json' $false 'not found' }

# --- VS Code
$vs = "$env:USERPROFILE\.vscode\extensions\edex-tron-theme-1.0.0"
Add-Check 'VS Code theme installed' (Test-Path "$vs\themes\edex-tron-color-theme.json") $vs

# --- launcher, dock and shell
$docs = [Environment]::GetFolderPath('MyDocuments')
Add-Check 'Launcher built' (Test-Path "$docs\eDEX-Tron\eDEX-Tron.exe")
$skins = "$docs\Rainmeter\Skins\eDEX-Tron"
Add-Check 'Dock skin deployed' (Test-Path "$skins\Dock\Dock.ini")
Add-Check 'Dock icons present' ((Get-ChildItem "$skins\@Resources\Dock" -Filter *.png -EA SilentlyContinue).Count -gt 0)
Add-Check 'Terminal skin deployed' (Test-Path "$skins\Terminal\Terminal.ini")
Add-Check 'Shell launcher present' (Test-Path "$skins\@Resources\launch_terminal.ps1")
Add-Check 'Terminal geometry written' (Test-Path "$skins\@Resources\terminal-pos.txt") `
    (Get-Content "$skins\@Resources\terminal-pos.txt" -EA SilentlyContinue)

# --- startup
$startup = [Environment]::GetFolderPath('Startup')
Add-Check 'Startup: launcher' (Test-Path "$startup\eDEX-Tron.lnk")

# --- running processes
Add-Check 'Rainmeter running' ([bool](Get-Process Rainmeter -ErrorAction SilentlyContinue))
Add-Check 'TranslucentTB running' ([bool](Get-Process -Name '*TranslucentTB*' -ErrorAction SilentlyContinue))

# --- theme state
$wp = (Get-ItemProperty 'HKCU:\Control Panel\Desktop').WallPaper
Add-Check 'Wallpaper points at theme' ($wp -like '*eDEX-Tron*') $wp
# Check the accent apps actually read. DWM\AccentColor is NOT the right probe:
# Windows re-derives it from the active theme file and it only drives title-bar
# tinting, which this theme leaves off.
try {
    [void][Windows.UI.ViewManagement.UISettings, Windows.UI.ViewManagement, ContentType = WindowsRuntime]
    $c = (New-Object Windows.UI.ViewManagement.UISettings).GetColorValue(5)
    $hex = '#{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B
    Add-Check 'Effective accent #AACFD1' ($hex -eq '#AACFD1') $hex
} catch {
    Add-Check 'Effective accent' $false 'UISettings unavailable'
}
$menu = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent').AccentColorMenu
Add-Check 'AccentColorMenu' ($menu -eq 4291940266) ("0x{0:X8}" -f $menu)
# sounds are opt-in, so the stock scheme staying selected is the pass condition
Add-Check 'Sound scheme left alone' ((Get-ItemProperty 'HKCU:\AppEvents\Schemes').'(default)' -eq '.Default')
Add-Check 'Backup exists' (Test-Path (Join-Path $docs 'eDEX-Tron\runtime\backup.json'))

$lines | Set-Content $out -Encoding utf8
$lines
