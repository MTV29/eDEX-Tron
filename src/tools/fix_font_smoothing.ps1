# Turn ClearType font smoothing back on, and make it stick.
#
# These values live in HKCU\Control Panel\Desktop and can end up *absent*
# rather than wrong -- Windows re-applies the active .theme, and a theme whose
# [Control Panel\Desktop] section does not mention them clears them. Text then
# renders unsmoothed and looks pixelated, which is easy to notice and hard to
# attribute.
#
# SystemParametersInfo with SPIF_UPDATEINIFILE is used rather than writing the
# registry directly: Windows then writes the values itself, in the form it
# expects, and broadcasts the change so running apps re-render without a
# sign-out.
#
# Must run OUTSIDE any app container -- see run_outside.ps1 -- or the writes
# land in the container's private registry and nothing on the real desktop
# changes.
param([switch]$Report)

$ErrorActionPreference = 'Stop'

Add-Type -Namespace Fs -Name Api -MemberDefinition @'
[DllImport("user32.dll", SetLastError=true)]
public static extern bool SystemParametersInfoW(uint action, uint param, IntPtr pv, uint winIni);
// Same export, a second signature: the "get" calls need pvParam as a ref int
// rather than an IntPtr. EntryPoint is required -- there is no function
// actually named SystemParametersInfoGet.
[DllImport("user32.dll", EntryPoint="SystemParametersInfoW", SetLastError=true)]
public static extern bool SystemParametersInfoGet(uint action, uint param, ref int pv, uint winIni);
'@

$SPI_SETFONTSMOOTHING      = 0x004B
$SPI_GETFONTSMOOTHING      = 0x004A
$SPI_SETFONTSMOOTHINGTYPE  = 0x200B
$SPI_GETFONTSMOOTHINGTYPE  = 0x200A
$SPIF_UPDATEINIFILE        = 0x01
$SPIF_SENDCHANGE           = 0x02
$FE_FONTSMOOTHINGCLEARTYPE = 0x0002

function Get-State {
    $on = 0; $type = 0
    [void][Fs.Api]::SystemParametersInfoGet($SPI_GETFONTSMOOTHING, 0, [ref]$on, 0)
    [void][Fs.Api]::SystemParametersInfoGet($SPI_GETFONTSMOOTHINGTYPE, 0, [ref]$type, 0)
    [pscustomobject]@{ On = [bool]$on; Type = $type }
}

$before = Get-State
"before: smoothing=$($before.On)  type=$($before.Type)"
if ($Report) { return }

# Smoothing on.
if (-not [Fs.Api]::SystemParametersInfoW($SPI_SETFONTSMOOTHING, 1, [IntPtr]::Zero,
        $SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE)) {
    throw "SPI_SETFONTSMOOTHING failed ($([Runtime.InteropServices.Marshal]::GetLastWin32Error()))"
}

# ClearType rather than plain antialiasing. The type is passed in pvParam for
# this one, not in uiParam, which is why it goes through the IntPtr overload.
if (-not [Fs.Api]::SystemParametersInfoW($SPI_SETFONTSMOOTHINGTYPE, 0,
        [IntPtr]$FE_FONTSMOOTHINGCLEARTYPE, $SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE)) {
    throw "SPI_SETFONTSMOOTHINGTYPE failed ($([Runtime.InteropServices.Marshal]::GetLastWin32Error()))"
}

# Subpixel order and gamma: absent means Windows picks, but writing them keeps
# a theme re-application from having nothing to put back.
$desk = 'HKCU:\Control Panel\Desktop'
New-ItemProperty -Path $desk -Name 'FontSmoothingOrientation' -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $desk -Name 'FontSmoothingGamma' -Value 1000 -PropertyType DWord -Force | Out-Null

$after = Get-State
"after : smoothing=$($after.On)  type=$($after.Type)"

'registry now:'
foreach ($n in 'FontSmoothing', 'FontSmoothingType', 'FontSmoothingOrientation', 'FontSmoothingGamma') {
    $v = (Get-ItemProperty $desk -Name $n -ErrorAction SilentlyContinue).$n
    '  {0,-26} {1}' -f $n, $(if ($null -ne $v) { $v } else { '(absent)' })
}
