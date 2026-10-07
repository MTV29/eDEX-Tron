# Build a picture of the HUD out of its own windows, never off the screen.
#
# A screenshot of a themed desktop is a screenshot of somebody's desktop: their
# files, their open windows, whatever is behind. This takes each Rainmeter skin
# with PrintWindow -- which asks that window alone to draw itself -- and lays
# the results out on a plain background at the coordinates the planner chose.
# Nothing that is not ours ends up in the frame.
#
# The panels that show your own things (the dock, the desktop mirror, the
# folder panel) are left out by default for the same reason. -Personal puts
# them in, for a picture you are keeping rather than publishing.
param(
    [string]$Out = 'runtime\hud.png',
    [int]$Frames = 1,
    [int]$DelayMs = 400,
    [switch]$Personal,
    # Paint over the two fields that identify the machine, for a picture
    # that is going somewhere public.
    [switch]$Redact,
    [string[]]$Exclude = @()
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Add-Type -AssemblyName System.Drawing

Add-Type -Namespace Cap -Name Hud -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
public delegate bool EnumProc(IntPtr h, IntPtr l);
public struct RECT { public int Left, Top, Right, Bottom; }
'@

[void][Cap.Hud]::SetProcessDPIAware()

$plan = Get-Content (Join-Path $Root 'runtime\layout.json') -Raw | ConvertFrom-Json
$theme = @{}
$themePath = Join-Path $Root 'theme.json'
if (Test-Path $themePath) { $theme = Get-Content $themePath -Raw -Encoding UTF8 | ConvertFrom-Json }
$bgHex = if ($theme.background) { $theme.background } else { '#05080d' }
$bg = [System.Drawing.ColorTranslator]::FromHtml($bgHex)

# Which skins to draw. Everything the planner placed, less the personal ones.
$skip = @($Exclude | ForEach-Object { $_.ToLower() })
if (-not $Personal) { $skip += @('dock', 'desktop', 'folder') }

# Find every Rainmeter window once; titles are the skin's .ini path.
$windows = @{}
$cb = [Cap.Hud+EnumProc] {
    param($h, $l)
    if ([Cap.Hud]::IsWindowVisible($h)) {
        $sb = New-Object System.Text.StringBuilder 512
        [void][Cap.Hud]::GetWindowTextW($h, $sb, $sb.Capacity)
        $title = $sb.ToString()
        if ($title -match 'eDEX-Tron\\([A-Za-z]+)\\') {
            $name = $Matches[1]
            if (-not $windows.ContainsKey($name)) { $windows[$name] = $h }
        }
    }
    $true
}
[void][Cap.Hud]::EnumWindows($cb, [IntPtr]::Zero)

if ($windows.Count -eq 0) { throw 'no eDEX-Tron skin windows found -- is the theme on?' }
"found $($windows.Count) skin window(s): $(($windows.Keys | Sort-Object) -join ', ')"

# The scaling the planner worked in is logical pixels; the windows are physical.
$scale = 1.0
try {
    $g0 = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    $scale = $g0.DpiX / 96.0
    $g0.Dispose()
} catch { }

$canvasW = [int]($plan.screen_w * $scale)
$canvasH = [int]($plan.work_h * $scale)

function Capture-One($h) {
    $r = New-Object Cap.Hud+RECT
    if (-not [Cap.Hud]::GetWindowRect($h, [ref]$r)) { return $null }
    $w = $r.Right - $r.Left; $hh = $r.Bottom - $r.Top
    if ($w -le 0 -or $hh -le 0) { return $null }
    $bmp = New-Object System.Drawing.Bitmap $w, $hh
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $dc = $g.GetHdc()
    # 2 = PW_RENDERFULLCONTENT, needed for the layered windows Rainmeter uses.
    $ok = [Cap.Hud]::PrintWindow($h, $dc, 2)
    $g.ReleaseHdc($dc); $g.Dispose()
    if (-not $ok) { $bmp.Dispose(); return $null }
    $bmp
}

$outFull = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $Root $Out }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outFull) | Out-Null
$made = @()

for ($frame = 0; $frame -lt $Frames; $frame++) {
    $canvas = New-Object System.Drawing.Bitmap $canvasW, $canvasH
    $cg = [System.Drawing.Graphics]::FromImage($canvas)
    $cg.Clear($bg)

    foreach ($name in ($windows.Keys | Sort-Object)) {
        if ($skip -contains $name.ToLower()) { continue }
        $pos = $plan.positions.$name
        if (-not $pos) { continue }
        $shot = Capture-One $windows[$name]
        if (-not $shot) { continue }
        $cg.DrawImage($shot, [int]($pos[0] * $scale), [int]($pos[1] * $scale),
                      $shot.Width, $shot.Height)
        $shot.Dispose()
    }
    # --- redaction -----------------------------------------------------
    # The HUD reports two things that are nobody else's business: the machine's
    # name and its address on the network. Everything else on screen is
    # hardware and load, which is the point of the picture.
    #
    # The rectangles are panel-relative logical pixels, keyed to the layout
    # gen_skins.py produces. A wrong box shows up immediately as a smear in the
    # wrong place, rather than as something leaking quietly.
    if ($Redact) {
        $redactions = @(
            @{ Panel = 'Clock';   X = 6; Y = 128; W = 88;  H = 22; Text = 'EDEX-PC' },
            @{ Panel = 'NetStat'; X = 6; Y = 84;  W = 186; H = 24; Text = '192.168.1.42' }
        )
        $rg = [System.Drawing.Graphics]::FromImage($canvas)
        $accentCol = [System.Drawing.ColorTranslator]::FromHtml(
            $(if ($theme.accent) { $theme.accent } else { '#aacfd1' }))
        foreach ($r in $redactions) {
            $pos = $plan.positions.($r.Panel)
            if (-not $pos -or ($skip -contains $r.Panel.ToLower())) { continue }
            $x = [int](($pos[0] + $r.X) * $scale)
            $y = [int](($pos[1] + $r.Y) * $scale)
            $bgBrush = New-Object System.Drawing.SolidBrush $bg
            $rg.FillRectangle($bgBrush, $x, $y, [int]($r.W * $scale), [int]($r.H * $scale))
            $bgBrush.Dispose()
            $font = New-Object System.Drawing.Font 'Consolas', ([float](11 * $scale))
            $fg = New-Object System.Drawing.SolidBrush $accentCol
            $rg.DrawString($r.Text, $font, $fg, [float]$x, [float]$y)
            $font.Dispose(); $fg.Dispose()
        }
        $rg.Dispose()
    }

    $cg.Dispose()

    $path = if ($Frames -eq 1) { $outFull }
            else { [System.IO.Path]::ChangeExtension($outFull, $null).TrimEnd('.') +
                   ('-{0:d3}.png' -f $frame) }
    $canvas.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $canvas.Dispose()
    $made += $path
    "frame $($frame + 1)/$Frames -> $path"
    if ($frame -lt $Frames - 1) { Start-Sleep -Milliseconds $DelayMs }
}

"wrote $($made.Count) file(s)"
