<#
.SYNOPSIS
    Build the eDEX-Tron shortcut dock from an editable list.

.DESCRIPTION
    Reads dock.txt (one "Label | target" per line, # for comments), extracts
    each target's icon to a PNG, and writes the Dock Rainmeter skin.

    Targets may be executables, .lnk shortcuts, folders, documents or URI
    schemes such as ms-settings:. Entries whose target cannot be found are
    skipped, so the same list works across machines.

    Re-run this after editing dock.txt, then refresh Rainmeter.

.PARAMETER Config
    Path to dock.txt. Defaults to <project>\dock.txt.

.PARAMETER SkinRoot
    The eDEX-Tron skin folder to write into.
#>
param(
    [string]$Config,
    [string]$SkinRoot,
    [int]$IconSize = 40,      # logical px
    [int]$Gap = 26,
    # Build the entries by scanning a folder instead of reading dock.txt.
    # Used for the Desktop panel, which mirrors the Desktop folder.
    [string]$FromFolder,
    [string]$SkinName = 'Dock',
    [string]$Title = 'Shortcuts',
    [string]$Subtitle = 'dock',
    [int]$Cols = 0,           # 0 = one row; otherwise wrap into a grid
    [int]$Rows = 4,
    [switch]$NoEdit
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $Config)   { $Config   = Join-Path $root 'dock.txt' }
if (-not $SkinRoot) { $SkinRoot = Join-Path $root 'skins\eDEX-Tron' }

$iconDir = Join-Path $SkinRoot "@Resources\$SkinName"
New-Item -ItemType Directory -Force -Path $iconDir, (Join-Path $SkinRoot $SkinName) | Out-Null

Add-Type -AssemblyName System.Drawing
Add-Type -Namespace Dock -Name Ico -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern int PrivateExtractIconsW(string lpszFile, int nIconIndex, int cxIcon, int cyIcon,
    IntPtr[] phicon, int[] piconid, int nIcons, int flags);
[DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr hIcon);
'@

function Get-AppxLogo([string]$familyName) {
    # Store apps have no icon-bearing .exe to extract from -- their artwork is
    # a set of PNGs whose names encode the size and the background they are
    # drawn for. Pick the biggest full-colour one, and never a "lightunplated"
    # or "theme-light" variant: those are dark glyphs meant for light
    # backgrounds and vanish against this HUD.
    $pkg = Get-AppxPackage | Where-Object { $_.PackageFamilyName -eq $familyName } | Select-Object -First 1
    if (-not $pkg) { return $null }

    $ve = $null
    try { $ve = (Get-AppxPackageManifest $pkg).Package.Applications.Application.VisualElements } catch { }
    $bases = @()
    foreach ($p in @($ve.Square150x150Logo, $ve.Square44x44Logo)) {
        if ($p) { $bases += [IO.Path]::GetFileNameWithoutExtension($p) }
    }
    if (-not $bases) { $bases = @('Square150x150Logo', 'Square44x44Logo', 'StoreLogo') }

    $assetDir = Join-Path $pkg.InstallLocation 'Assets'
    if (-not (Test-Path $assetDir)) { return $null }

    # Score on the real pixel dimensions, not the filename. Names like
    # "targetsize-24_altform-unplated" are transparent and full-colour but tiny;
    # preferring the unplated form on name alone picks a 24px icon over an 88px
    # one and it renders blurry at dock size.
    $best = $null; $bestScore = [int]::MinValue
    foreach ($base in ($bases | Select-Object -Unique)) {
        foreach ($f in Get-ChildItem $assetDir -Filter "$base*.png" -ErrorAction SilentlyContinue) {
            if ($f.Name -match 'lightunplated|theme-light|contrast') { continue }
            $side = 0
            try {
                $img = [System.Drawing.Image]::FromFile($f.FullName)
                $side = [Math]::Min($img.Width, $img.Height)
                $img.Dispose()
            } catch { continue }
            # size dominates; transparency only breaks ties between equal sizes
            $score = $side * 10
            if ($f.Name -match 'altform-unplated') { $score += 5 }
            if ($score -gt $bestScore) { $bestScore = $score; $best = $f.FullName }
        }
    }
    return $best
}

function Resolve-Target([string]$raw) {
    $t = $raw.Trim()
    # shell:AppsFolder\<PackageFamilyName>!<AppId> -- a Store app. Resolve the
    # icon from the package rather than the moniker, and re-resolve on every
    # rebuild so it survives the app updating (the install path is versioned).
    if ($t -match '^shell:AppsFolder\\([^!]+)!') {
        return @{ Kind = 'uri'; Path = $t; Icon = (Get-AppxLogo $Matches[1]) }
    }
    if ($t -match '^[a-z][a-z0-9+.-]*:' -and $t -notmatch '^[a-z]:\\') {
        return @{ Kind = 'uri'; Path = $t; Icon = $null }   # ms-settings:, http:, ...
    }
    $expanded = [Environment]::ExpandEnvironmentVariables($t)
    if (Test-Path $expanded) {
        $item = Get-Item $expanded
        if ($item.Extension -eq '.lnk') {
            $sh = New-Object -ComObject WScript.Shell
            $lnk = $sh.CreateShortcut($item.FullName)
            return @{ Kind = 'file'; Path = $item.FullName; Icon = $(if ($lnk.TargetPath) { $lnk.TargetPath } else { $item.FullName }) }
        }
        return @{ Kind = 'file'; Path = $item.FullName; Icon = $item.FullName }
    }
    $cmd = Get-Command $expanded -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return @{ Kind = 'file'; Path = $cmd.Source; Icon = $cmd.Source } }
    return $null
}

function Save-Icon([string]$source, [string]$dest) {
    # Already an image (a Store app's logo asset): copy it straight through.
    if ($source -match '\.(png|ico|jpg|jpeg)$' -and (Test-Path $source)) {
        try {
            $img = [System.Drawing.Image]::FromFile($source)
            $img.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
            $img.Dispose()
            return $true
        } catch { return $false }
    }

    # Folders have no icon of their own; borrow the shell's from imageres.dll.
    if ((Test-Path $source) -and (Get-Item $source).PSIsContainer) {
        $source = Join-Path $env:SystemRoot 'System32\imageres.dll'
        foreach ($size in 256, 128, 64) {
            $h = New-Object IntPtr[] 1
            $id = New-Object int[] 1
            # index 3 is the standard closed-folder icon
            $n = [Dock.Ico]::PrivateExtractIconsW($source, 3, $size, $size, $h, $id, 1, 0)
            if ($n -gt 0 -and $h[0] -ne [IntPtr]::Zero) {
                try {
                    $ico = [System.Drawing.Icon]::FromHandle($h[0])
                    $bmp = $ico.ToBitmap()
                    $bmp.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
                    $bmp.Dispose()
                    return $true
                } finally { [void][Dock.Ico]::DestroyIcon($h[0]) }
            }
        }
        return $false
    }

    # PrivateExtractIcons can hand back a large icon; ExtractAssociatedIcon is
    # capped at 32px and only used when that fails.
    foreach ($size in 256, 128, 64, 48) {
        $h = New-Object IntPtr[] 1
        $id = New-Object int[] 1
        $n = [Dock.Ico]::PrivateExtractIconsW($source, 0, $size, $size, $h, $id, 1, 0)
        if ($n -gt 0 -and $h[0] -ne [IntPtr]::Zero) {
            try {
                $ico = [System.Drawing.Icon]::FromHandle($h[0])
                $bmp = $ico.ToBitmap()
                $bmp.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
                $bmp.Dispose()
                return $true
            } finally { [void][Dock.Ico]::DestroyIcon($h[0]) }
        }
    }
    try {
        $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($source)
        if ($ico) { $ico.ToBitmap().Save($dest, [System.Drawing.Imaging.ImageFormat]::Png); return $true }
    } catch { }
    return $false
}

# ------------------------------------------------------------------- entries
$entries = @()
$slot = 0

if ($FromFolder) {
    # Mirror a folder: directories first, then files, skipping the hidden
    # bookkeeping entries Explorer never shows either.
    if (-not (Test-Path $FromFolder)) { throw "Folder not found: $FromFolder" }
    $limit = if ($Cols -gt 0) { $Cols * $Rows } else { 12 }
    $items = Get-ChildItem $FromFolder -Force |
        Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::Hidden) -and $_.Name -ne 'desktop.ini' } |
        Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name |
        Select-Object -First $limit

    foreach ($item in $items) {
        $png = Join-Path $iconDir ("slot{0}.png" -f $slot)
        $iconSrc = $item.FullName
        if ($item.Extension -eq '.lnk') {
            $sh = New-Object -ComObject WScript.Shell
            $t = $sh.CreateShortcut($item.FullName).TargetPath
            if ($t -and (Test-Path $t)) { $iconSrc = $t }
        }
        $entries += [pscustomobject]@{
            Label   = $item.BaseName
            Path    = $item.FullName
            Slot    = $slot
            HasIcon = (Save-Icon $iconSrc $png)
        }
        $slot++
    }
    if (-not $entries) { throw "No visible items in $FromFolder" }
}

# ---------------------------------------------------------------- read config
if (-not $FromFolder) {
if (-not (Test-Path $Config)) { throw "Dock config not found: $Config" }
foreach ($line in Get-Content $Config) {
    $line = $line.Trim()
    if (-not $line -or $line.StartsWith('#')) { continue }
    # Label | target [| icon source]  -- the third field is for targets that
    # carry no icon of their own, such as URI schemes like ms-settings:
    $parts = $line -split '\|', 3
    if ($parts.Count -lt 2) { Write-Warning "skipping malformed line: $line"; continue }
    $label = $parts[0].Trim()
    $resolved = Resolve-Target $parts[1]
    if (-not $resolved) { Write-Warning "skipping '$label' - target not found: $($parts[1].Trim())"; continue }

    $png = Join-Path $iconDir ("slot{0}.png" -f $slot)
    $iconSrc = $resolved.Icon
    if ($parts.Count -ge 3 -and $parts[2].Trim()) {
        $override = [Environment]::ExpandEnvironmentVariables($parts[2].Trim())
        if (Test-Path $override) { $iconSrc = $override }
        else { Write-Warning "icon override for '$label' not found: $override" }
    }
    $haveIcon = $false
    if ($iconSrc) { $haveIcon = Save-Icon $iconSrc $png }
    if (-not $haveIcon) { Write-Warning "no icon for '$label'; it will show as a label only" }

    $entries += [pscustomobject]@{
        Label = $label; Path = $resolved.Path; Slot = $slot; HasIcon = $haveIcon
    }
    $slot++
}
if (-not $entries) { throw "No usable entries in $Config" }
}

# ------------------------------------------------------------------ emit skin
# Absolute coordinates throughout. A relative chain across a wrapping grid has
# to step back up at every row break, which is easy to get subtly wrong.
$count   = $entries.Count
$cell    = $IconSize + $Gap
$pad     = 14
$cols    = if ($Cols -gt 0) { [Math]::Min($Cols, $count) } else { $count }
$rows    = [int][Math]::Ceiling($count / $cols)
$width   = $cols * $cell - $Gap + $pad * 2
$gridTop = 52
$rowH    = $IconSize + 28

$sb = New-Object System.Text.StringBuilder
function W($s) { [void]$sb.AppendLine($s) }

$edit = '["powershell.exe" "-NoProfile" "-WindowStyle" "Hidden" "-ExecutionPolicy" "Bypass" "-File" "#@#customize_dock.ps1"]'
$rescan = '["powershell.exe" "-NoProfile" "-WindowStyle" "Hidden" "-ExecutionPolicy" "Bypass" "-File" "#@#refresh_desktop.ps1"]'
$action = if ($NoEdit) { $rescan } else { $edit }
$hint   = if ($NoEdit) { 'Right-click to rescan the folder' } else { 'Right-click to edit shortcuts' }
$corner = if ($NoEdit) { '. Rescan' } else { '+ Edit' }

W '[Rainmeter]'
W 'Update=1000'
W 'AccurateText=1'
W 'DynamicWindowSize=1'
W "RightMouseUpAction=$action"
W "ToolTipText=$hint"
W ''
W '[Variables]'
W '@Include=#@#Variables.inc'
W ''
W '[MeterTitle]'
W 'Meter=String'
W "X=$pad"
W 'Y=0'
W 'FontFace=#FontMain#'
W 'FontSize=9'
W 'FontColor=#Accent#,255'
W 'StringCase=Upper'
W 'AntiAlias=1'
W "Text=$Title"
W ''
W '[MeterTitleRight]'
W 'Meter=String'
W "X=$($width - $pad)"
W 'Y=0r'
W 'FontFace=#FontLight#'
W 'FontSize=9'
W 'FontColor=#Accent#,190'
W 'StringAlign=Right'
W 'StringCase=Upper'
W 'AntiAlias=1'
W "LeftMouseUpAction=$action"
W "ToolTipText=$hint"
W "Text=$corner"
W ''
W '[MeterTitleRule]'
W 'Meter=Shape'
W 'X=0'
W 'Y=15r'
W "Shape=Line 0,0,$width,0 | StrokeWidth 1 | Stroke Color #Accent#,90"
W "Shape2=Line 0.5,0,0.5,5 | StrokeWidth 1 | Stroke Color #Accent#,130"
W "Shape3=Line $($width - 0.5),0,$($width - 0.5),5 | StrokeWidth 1 | Stroke Color #Accent#,130"

foreach ($e in $entries) {
    $col = $e.Slot % $cols
    $row = [int][Math]::Floor($e.Slot / $cols)
    $x   = $pad + $col * $cell
    $y   = $gridTop + $row * $rowH
    W ''
    if ($e.HasIcon) {
        W "[MeterIcon$($e.Slot)]"
        W 'Meter=Image'
        W "ImageName=#@#$SkinName\slot$($e.Slot).png"
        W "X=$x"
        W "Y=$y"
        W "W=$IconSize"
        W "H=$IconSize"
        W 'PreserveAspectRatio=1'
        W 'AntiAlias=1'
        W "LeftMouseUpAction=[""$($e.Path)""]"
        W "ToolTipText=$($e.Label)"
        W ''
    }
    W "[MeterLabel$($e.Slot)]"
    W 'Meter=String'
    W "X=$($x + [int]($IconSize / 2))"
    W "Y=$($y + $IconSize + 3)"
    W "W=$($cell - 4)"
    W 'H=16'
    W 'ClipString=1'
    W 'FontFace=#FontLight#'
    W 'FontSize=8'
    W 'FontColor=#Accent#,190'
    W 'StringAlign=CenterTop'
    W 'StringCase=Upper'
    W 'AntiAlias=1'
    W "LeftMouseUpAction=[""$($e.Path)""]"
    W "ToolTipText=$($e.Label)"
    W "Text=$($e.Label)"
}

$out = Join-Path $SkinRoot "$SkinName\$SkinName.ini"
$sb.ToString() | Set-Content $out -Encoding utf8
# gen_rainmeter_ini.py reads this to place the panel
"$width" | Set-Content (Join-Path $SkinRoot "@Resources\$($SkinName.ToLower())-width.txt") -Encoding utf8
"{0}: {1} entr(y/ies), {2} col x {3} row, width {4}px -> {5}" -f $SkinName, $count, $cols, $rows, $width, $out
$entries | ForEach-Object { "  {0,-20} {1}" -f $_.Label, $_.Path }
