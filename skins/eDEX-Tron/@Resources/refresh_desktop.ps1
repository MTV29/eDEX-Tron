<#
Rescan a folder and rebuild its icon panel: the Desktop panel, or the Folder
panel (your games folder by default).

The panels are generated rather than live: icons have to be extracted from real
executables through the Windows shell, which Rainmeter cannot do on its own
(FileView has no icon type). eDEX-Tron.exe's watcher runs this whenever one of
the folders changes; right-clicking a panel runs it by hand.

Each grid keeps the size the layout planner gave it (runtime\layout.json), so a
rescan never pushes the panel into its neighbours.
#>
param([ValidateSet('Desktop', 'Folder', 'Both')][string]$Panel = 'Desktop')

$ErrorActionPreference = 'Continue'

$docs      = [Environment]::GetFolderPath('MyDocuments')
$desktop   = [Environment]::GetFolderPath('Desktop')
$project   = Join-Path $docs 'eDEX-Tron'
$gen       = Join-Path $project 'src\tools\gen_dock.ps1'
$srcSkin   = Join-Path $project 'skins\eDEX-Tron'
$liveSkin  = Join-Path $docs 'Rainmeter\Skins\eDEX-Tron'
$planFile  = Join-Path $project 'runtime\layout.json'
$pathFile  = Join-Path $project 'runtime\folder-path.txt'
$rainmeter = Join-Path ${env:ProgramFiles} 'Rainmeter\Rainmeter.exe'

if (-not (Test-Path $gen)) { return }

$plan = $null
if (Test-Path $planFile) { $plan = Get-Content $planFile -Raw | ConvertFrom-Json }

# The Folder panel's folder: written by relayout.ps1 from theme.json.
$folder = Join-Path $desktop 'Games'
if (Test-Path $pathFile) {
    $saved = (Get-Content $pathFile -Raw).Trim()
    if ($saved) { $folder = [Environment]::ExpandEnvironmentVariables($saved) }
}

function Update-Panel([string]$name, [string]$source, [string]$title, [int]$cols, [int]$rows) {
    if (-not (Test-Path $source)) { return }
    & $gen -FromFolder $source -SkinRoot $srcSkin -SkinName $name `
           -Title $title -Cols $cols -Rows $rows -NoEdit | Out-Null

    New-Item -ItemType Directory -Force -Path (Join-Path $liveSkin $name), (Join-Path $liveSkin "@Resources\$name") | Out-Null
    # clear old icons first: a removed item would otherwise leave its PNG behind
    Remove-Item (Join-Path $liveSkin "@Resources\$name\*") -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $srcSkin "$name\$name.ini") (Join-Path $liveSkin "$name\") -Force
    Copy-Item (Join-Path $srcSkin "@Resources\$name\*") (Join-Path $liveSkin "@Resources\$name\") -Force

    if (Test-Path $rainmeter) { & $rainmeter '!Refresh' "eDEX-Tron\$name" }
}

if ($Panel -in 'Desktop', 'Both') {
    $cols = if ($plan.desk_cols) { [int]$plan.desk_cols } else { 8 }
    $rows = if ($plan.desk_rows) { [int]$plan.desk_rows } else { 4 }
    Update-Panel 'Desktop' $desktop 'Desktop' $cols $rows
}
if ($Panel -in 'Folder', 'Both') {
    $cols = if ($plan.folder_cols) { [int]$plan.folder_cols } else { 8 }
    $rows = if ($plan.folder_rows) { [int]$plan.folder_rows } else { 2 }
    Update-Panel 'Folder' $folder (Split-Path $folder -Leaf) $cols $rows
}
