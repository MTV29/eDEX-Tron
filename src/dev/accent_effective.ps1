# What accent do apps actually see? UISettings.GetColorValue is the API WinUI /
# UWP surfaces read, so this is the colour that really shows on buttons,
# toggles, selection and focus rings -- regardless of what the raw registry
# values say.
$out = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'eDEX-Tron\accent-effective.txt'
$l = @()
try {
    [void][Windows.UI.ViewManagement.UISettings, Windows.UI.ViewManagement, ContentType = WindowsRuntime]
    $ui = New-Object Windows.UI.ViewManagement.UISettings
    # UIColorType: 5 = Accent, 4/3/2 = darker, 6/7/8 = lighter
    foreach ($pair in @(@(2, 'AccentDark3'), @(3, 'AccentDark2'), @(4, 'AccentDark1'),
                        @(5, 'Accent'), @(6, 'AccentLight1'), @(7, 'AccentLight2'), @(8, 'AccentLight3'))) {
        $c = $ui.GetColorValue($pair[0])
        $l += ("{0,-13} #{1:X2}{2:X2}{3:X2}" -f $pair[1], $c.R, $c.G, $c.B)
    }
} catch {
    $l += "UISettings unavailable: $($_.Exception.Message)"
}
$l += ''
$l += 'expected accent #AACFD1'
$l | Set-Content $out -Encoding utf8
$l
