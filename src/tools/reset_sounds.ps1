# Put the Windows sound events back the way they were and re-select the stock
# scheme. Run outside the app container so it touches the real HKCU.
$ErrorActionPreference = 'Continue'
$docs = [Environment]::GetFolderPath('MyDocuments')
$backupFile = Join-Path $docs 'eDEX-Tron\runtime\backup.json'

$restored = 0
if (Test-Path $backupFile) {
    $backup = Get-Content $backupFile -Raw | ConvertFrom-Json
    foreach ($prop in $backup.Sounds.PSObject.Properties) {
        $k = "HKCU:\AppEvents\Schemes\Apps\.Default\$($prop.Name)\.Current"
        if (Test-Path $k) {
            # a null in the backup means the event had no sound before
            Set-ItemProperty $k '(default)' ([string]$prop.Value)
            $restored++
        }
    }
    "restored $restored event(s) from backup"
} else {
    "no backup found; clearing the events this theme set"
    foreach ($e in '.Default','SystemAsterisk','SystemExclamation','SystemHand',
                   'SystemQuestion','Notification.Default','DeviceConnect',
                   'DeviceDisconnect','DeviceFail','EmptyRecycleBin','Open','Close') {
        $k = "HKCU:\AppEvents\Schemes\Apps\.Default\$e\.Current"
        if (Test-Path $k) { Set-ItemProperty $k '(default)' '' }
    }
}

Set-ItemProperty 'HKCU:\AppEvents\Schemes' '(default)' '.Default'
Remove-Item 'HKCU:\AppEvents\Schemes\Names\eDEX-Tron' -Recurse -Force -ErrorAction SilentlyContinue
'sound scheme reset to Windows Default'
