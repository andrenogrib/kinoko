$ErrorActionPreference = "Stop"

$dockerExe = if (Get-Command docker -ErrorAction SilentlyContinue) {
    (Get-Command docker).Source
} elseif (Test-Path "C:\Program Files\Docker\Docker\resources\bin\docker.exe") {
    "C:\Program Files\Docker\Docker\resources\bin\docker.exe"
} else {
    $null
}

$serverPids = @()
try {
    $serverPids += Get-NetTCPConnection -LocalPort 8484 -State Listen -ErrorAction Stop | Select-Object -ExpandProperty OwningProcess
} catch {
    # Ignore and fallback below.
}
if (-not $serverPids) {
    $serverPids += Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "java.exe" -and $_.CommandLine -match "target[/\\\\]server\\.jar"
    } | Select-Object -ExpandProperty ProcessId
}
$serverPids = $serverPids | Sort-Object -Unique

foreach ($procId in $serverPids) {
    Stop-Process -Id $procId -Force
}

if ($dockerExe) {
    & $dockerExe stop kinoko-db | Out-Null
}

Write-Host "OK: servidor e banco parados."
