# Report what the real user profile actually contains, from outside any app
# container. Writes to Documents (never redirected) so the caller can read it.
$out = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'eDEX-Tron\verify-outside.txt'
New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null

$lines = @()
$lines += "generated      : $(Get-Date -Format o)"
$lines += "APPDATA        : $env:APPDATA"
$lines += "LOCALAPPDATA   : $env:LOCALAPPDATA"
$lines += ''
$lines += '--- files ---'
foreach ($p in @(
    "$env:APPDATA\Rainmeter\Rainmeter.ini",
    "$env:LOCALAPPDATA\Microsoft\Windows\Fonts\united_sans_medium.ttf",
    "$env:LOCALAPPDATA\Microsoft\Windows\Fonts\fira_mono.ttf",
    (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'eDEX-Tron\wallpaper\edex-tron-1920x1080.jpg'),
    (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Rainmeter\Skins\eDEX-Tron\Clock\Clock.ini')
)) {
    $exists = Test-Path $p
    $size = if ($exists) { (Get-Item $p).Length } else { 0 }
    $lines += ("{0,-6} {1,9}  {2}" -f $exists, $size, $p)
}

if (Test-Path "$env:APPDATA\Rainmeter\Rainmeter.ini") {
    $ini = Get-Content "$env:APPDATA\Rainmeter\Rainmeter.ini" -Raw
    $lines += "Rainmeter.ini mentions eDEX-Tron: $($ini -match 'eDEX-Tron')"
}

$lines += ''
$lines += '--- registry (real HKCU) ---'
function Show($path, $name) {
    $v = try { (Get-ItemProperty -Path $path -Name $name -ErrorAction Stop).$name } catch { '<missing>' }
    if ($v -is [byte[]]) { $v = ($v | ForEach-Object { '{0:X2}' -f $_ }) -join ' ' }
    elseif ($v -is [int] -or $v -is [long]) { $v = "$v (0x{0:X8})" -f $v }
    $script:lines += ("{0,-22} = {1}" -f $name, $v)
}
Show 'HKCU:\Software\Microsoft\Windows\DWM' 'AccentColor'
Show 'HKCU:\Software\Microsoft\Windows\DWM' 'ColorPrevalence'
Show 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' 'AccentColorMenu'
Show 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' 'AccentPalette'
Show 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme'
Show 'HKCU:\Control Panel\Desktop' 'WallPaper'
Show 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers' 'BackgroundType'
Show 'HKCU:\AppEvents\Schemes' '(default)'
Show 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts' 'United Sans Reg Medium (TrueType)'

$lines | Set-Content $out -Encoding utf8
