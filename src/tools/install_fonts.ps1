# Per-user font install - no admin required.
param([string]$SourceDir = "build\ttf", [switch]$Uninstall)

$fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
$regKey  = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
if (-not (Test-Path $regKey)) { New-Item -Path $regKey -Force | Out-Null }

Add-Type -Namespace Win32 -Name Fonts -MemberDefinition @'
[DllImport("gdi32.dll")] public static extern int AddFontResourceW(string lpFilename);
[DllImport("gdi32.dll")] public static extern bool RemoveFontResourceW(string lpFilename);
'@

# Map file -> the family name Windows should register it under
$families = @{
  'united_sans_medium.ttf' = 'United Sans Reg Medium (TrueType)'
  'united_sans_light.ttf'  = 'UnitedSansReg-Light (TrueType)'
  'fira_mono.ttf'          = 'Fira Mono (TrueType)'
  'fira_code.ttf'          = 'Fira Code Regular (TrueType)'
}

# Which fonts to work on. Installing needs the source files, so a missing
# source directory means there is nothing to do -- it is empty whenever the
# person has no eDEX-UI to copy the typefaces out of.
#
# Removing them must NOT depend on that directory: it is build output, and it
# is gone on any machine where setup never finished, or where build\ was
# cleaned. Uninstall therefore works from the map above, which is the record of
# what this script ever installs, and treats the source directory as a bonus.
$sourceFiles = @()
if (Test-Path $SourceDir) { $sourceFiles = @(Get-ChildItem $SourceDir -Filter *.ttf) }

if ($Uninstall) {
    $wanted = [ordered]@{}
    foreach ($entry in $families.GetEnumerator()) { $wanted[$entry.Key] = $entry.Value }
    foreach ($f in $sourceFiles) {
        if (-not $wanted.Contains($f.Name)) { $wanted[$f.Name] = "$($f.BaseName) (TrueType)" }
    }
    foreach ($entry in $wanted.GetEnumerator()) {
        $target = Join-Path $fontDir $entry.Key
        $name = $entry.Value
        $had = (Test-Path $target) -or
               ($null -ne (Get-ItemProperty -Path $regKey -Name $name -ErrorAction SilentlyContinue))
        if (-not $had) { continue }
        [Win32.Fonts]::RemoveFontResourceW($target) | Out-Null
        Remove-ItemProperty -Path $regKey -Name $name -ErrorAction SilentlyContinue
        Remove-Item $target -ErrorAction SilentlyContinue
        "removed  $name"
    }
    return
}

if (-not $sourceFiles) {
    "no fonts to install ($SourceDir is empty or missing)"
    return
}

foreach ($file in $sourceFiles) {
    $target = Join-Path $fontDir $file.Name
    $name   = $families[$file.Name]
    if (-not $name) { $name = "$($file.BaseName) (TrueType)" }

    # A font already registered is loaded by GDI and cannot be overwritten, so
    # only copy when the bytes actually differ. Re-registering an identical
    # file is harmless and keeps re-runs idempotent.
    $needsCopy = -not (Test-Path $target) -or
                 (Get-Item $target).Length -ne $file.Length
    if ($needsCopy) {
        try {
            Copy-Item $file.FullName $target -Force -ErrorAction Stop
        } catch {
            "skipped $($file.Name) (in use, existing copy kept)"
        }
    }
    if (Test-Path $target) {
        [Win32.Fonts]::AddFontResourceW($target) | Out-Null
        New-ItemProperty -Path $regKey -Name $name -Value $target -PropertyType String -Force | Out-Null
        "installed $name"
    } else {
        "FAILED   $name (could not place $target)"
    }
}
