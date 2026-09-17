# Dump everything that participates in the accent colour, from the real HKCU.
$out = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'eDEX-Tron\accent-probe.txt'
$l = @("probed $(Get-Date -Format o)")

function Show($path, $name) {
    $v = try { (Get-ItemProperty -Path $path -Name $name -ErrorAction Stop).$name } catch { '<missing>' }
    if ($v -is [byte[]]) {
        $hex = ($v | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
        $script:l += ("{0,-22} = {1}" -f $name, $hex)
        # decode as 8 x R,G,B,00
        for ($i = 0; $i -lt $v.Length; $i += 4) {
            $script:l += ("    [{0}] R={1,3} G={2,3} B={3,3}" -f ($i/4), $v[$i], $v[$i+1], $v[$i+2])
        }
    } elseif ($v -is [int] -or $v -is [long] -or $v -is [uint32]) {
        $u = [uint32]$v
        $script:l += ("{0,-22} = 0x{1:X8}  (A={2} B={3} G={4} R={5})" -f $name, $u,
            (($u -shr 24) -band 0xFF), (($u -shr 16) -band 0xFF), (($u -shr 8) -band 0xFF), ($u -band 0xFF))
    } else {
        $script:l += ("{0,-22} = {1}" -f $name, $v)
    }
}

$l += '--- DWM ---'
Show 'HKCU:\Software\Microsoft\Windows\DWM' 'AccentColor'
Show 'HKCU:\Software\Microsoft\Windows\DWM' 'ColorizationColor'
Show 'HKCU:\Software\Microsoft\Windows\DWM' 'ColorPrevalence'
$l += '--- Explorer\Accent ---'
Show 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' 'AccentColorMenu'
Show 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' 'AccentPalette'
$l += '--- personalization ---'
Show 'HKCU:\Control Panel\Desktop' 'AutoColorization'
Show 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes' 'CurrentTheme'
Show 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme'

$l | Set-Content $out -Encoding utf8
$l
