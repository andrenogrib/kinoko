$ErrorActionPreference = "Stop"

$dockerExe = if (Get-Command docker -ErrorAction SilentlyContinue) {
    (Get-Command docker).Source
} elseif (Test-Path "C:\Program Files\Docker\Docker\resources\bin\docker.exe") {
    "C:\Program Files\Docker\Docker\resources\bin\docker.exe"
} else {
    $null
}

Write-Host "=== DATABASE ==="
if ($dockerExe) {
    & $dockerExe ps --filter "name=kinoko-db" --format "table {{.Names}}`t{{.Status}}`t{{.Ports}}"
} else {
    Write-Host "docker nao encontrado no PATH."
}

Write-Host ""
Write-Host "=== SERVER PROCESS ==="
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

if ($serverPids) {
    Get-CimInstance Win32_Process | Where-Object { $serverPids -contains $_.ProcessId } | Select-Object ProcessId, CommandLine | Format-Table -AutoSize
} else {
    Write-Host "Servidor nao esta rodando."
}

Write-Host ""
Write-Host "=== PORTS ==="
netstat -ano | findstr ":8484 :8585 :8282 :9042"
