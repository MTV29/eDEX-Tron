<#
Rescan the Desktop folder and rebuild the Desktop panel.

The panel is generated rather than live: icons have to be extracted from real
executables through the Windows shell, which Rainmeter cannot do on its own
(FileView has no icon type). eDEX-Tron.exe's watcher runs this whenever the
Desktop folder changes; right-clicking the panel runs it by hand.

The grid keeps the size the layout planner gave it (runtime\layout.json), so a
rescan never pushes the panel into its neighbours.
#>
$ErrorActionPreference = 'Continue'

$docs      = [Environment]::GetFolderPath('MyDocuments')
$desktop   = [Environment]::GetFolderPath('Desktop')
$project   = Join-Path $docs 'eDEX-Tron'
$gen       = Join-Path $project 'src\tools\gen_dock.ps1'
$srcSkin   = Join-Path $project 'skins\eDEX-Tron'
$liveSkin  = Join-Path $docs 'Rainmeter\Skins\eDEX-Tron'
$planFile  = Join-Path $project 'runtime\layout.json'
$rainmeter = Join-Path ${env:ProgramFiles} 'Rainmeter\Rainmeter.exe'

if (-not (Test-Path $gen)) { return }

$cols, $rows = 8, 4
if (Test-Path $planFile) {
    $plan = Get-Content $planFile -Raw | ConvertFrom-Json
    if ($plan.desk_cols) { $cols = [int]$plan.desk_cols }
    if ($plan.desk_rows) { $rows = [int]$plan.desk_rows }
}

& $gen -FromFolder $desktop -SkinRoot $srcSkin -SkinName 'Desktop' `
       -Title 'Desktop' -Cols $cols -Rows $rows -NoEdit | Out-Null

New-Item -ItemType Directory -Force -Path (Join-Path $liveSkin 'Desktop'), (Join-Path $liveSkin '@Resources\Desktop') | Out-Null
# clear old icons first: a removed item would otherwise leave its PNG behind
Remove-Item (Join-Path $liveSkin '@Resources\Desktop\*') -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $srcSkin 'Desktop\Desktop.ini') (Join-Path $liveSkin 'Desktop\') -Force
Copy-Item (Join-Path $srcSkin '@Resources\Desktop\*') (Join-Path $liveSkin '@Resources\Desktop\') -Force

if (Test-Path $rainmeter) { & $rainmeter '!Refresh' 'eDEX-Tron\Desktop' }
