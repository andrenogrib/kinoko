param(
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$logsDir = Join-Path $repoRoot "logs"
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

function Resolve-CommandPath([string]$commandName, [string[]]$fallbacks) {
    $cmd = Get-Command $commandName -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    foreach ($path in $fallbacks) {
        if (Test-Path $path) {
            return $path
        }
    }
    return $null
}

function Resolve-Java21Path {
    if ($env:JAVA_HOME) {
        $javaFromEnv = Join-Path $env:JAVA_HOME "bin\\java.exe"
        if (Test-Path $javaFromEnv) {
            return $javaFromEnv
        }
    }

    $candidates = @(
        "C:\\Program Files\\Eclipse Adoptium\\jdk-21.0.10.7-hotspot\\bin\\java.exe",
        "C:\\Program Files\\Amazon Corretto\\jdk21.0.10_7\\bin\\java.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $detected = Get-ChildItem "C:\\Program Files\\Eclipse Adoptium" -Directory -ErrorAction SilentlyContinue `
        | Where-Object { $_.Name -like "jdk-21*" } `
        | Sort-Object Name -Descending `
        | Select-Object -First 1
    if ($detected) {
        $javaDetected = Join-Path $detected.FullName "bin\\java.exe"
        if (Test-Path $javaDetected) {
            return $javaDetected
        }
    }

    return $null
}

function Get-ServerProcessIds {
    $pids = @()

    try {
        $listeners = Get-NetTCPConnection -LocalPort 8484 -State Listen -ErrorAction Stop
        $pids += $listeners | Select-Object -ExpandProperty OwningProcess
    } catch {
        # Ignore and fallback below.
    }

    if (-not $pids) {
        $fallback = Get-CimInstance Win32_Process | Where-Object {
            $_.Name -eq "java.exe" -and $_.CommandLine -match "target[/\\\\]server\\.jar"
        } | Select-Object -ExpandProperty ProcessId
        $pids += $fallback
    }

    return $pids | Sort-Object -Unique
}

function Wait-LoginPort([int]$Seconds = 20) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $listeners = Get-NetTCPConnection -LocalPort 8484 -State Listen -ErrorAction Stop
            if ($listeners) {
                return $true
            }
        } catch {
            # keep waiting
        }
        Start-Sleep -Seconds 1
    }
    return $false
}

$dockerExe = Resolve-CommandPath "docker" @("C:\\Program Files\\Docker\\Docker\\resources\\bin\\docker.exe")
if (-not $dockerExe) {
    throw "Docker nao encontrado. Abra o Docker Desktop e tente novamente."
}

$mvnCmd = Resolve-CommandPath "mvn" @("C:\\Program Files\\JetBrains\\IntelliJ IDEA 2024.3\\plugins\\maven\\lib\\maven3\\bin\\mvn.cmd")
if (-not $mvnCmd) {
    throw "Maven nao encontrado. Instale o Maven ou rode pelo IntelliJ."
}

$javaExe = Resolve-Java21Path
if (-not $javaExe) {
    throw "Java 21 nao encontrado."
}

# Build jar (skip tests for local startup speed)
if (-not $SkipBuild) {
    Push-Location $repoRoot
    try {
        & $mvnCmd --% clean package -Dmaven.test.skip=true
    } finally {
        Pop-Location
    }
}

# Start Cassandra container
$dbContainer = "kinoko-db"
$exists = (& $dockerExe ps -a --format "{{.Names}}") | Where-Object { $_ -eq $dbContainer }
if ($exists) {
    & $dockerExe start $dbContainer | Out-Null
} else {
    & $dockerExe run -d --name $dbContainer -p 9042:9042 cassandra:5.0.0-jammy | Out-Null
}

# Wait for database readiness
$deadline = (Get-Date).AddMinutes(3)
$ready = $false
while ((Get-Date) -lt $deadline) {
    # Reliable readiness probe: run cqlsh in the container.
    cmd /c "`"$dockerExe`" exec $dbContainer cqlsh -e `"describe keyspaces`" >nul 2>nul"
    if ($LASTEXITCODE -eq 0) {
        $ready = $true
        break
    }
    Start-Sleep -Seconds 5
}
if (-not $ready) {
    throw "Cassandra nao ficou pronta dentro do tempo esperado."
}

# Start server process if needed
$serverPids = Get-ServerProcessIds
if (-not $serverPids) {
    $env:DATABASE_HOST = "127.0.0.1"
    $env:SERVER_HOST = "127.0.0.1"
    $env:CENTRAL_HOST = "127.0.0.1"
    $env:WORLD_NAME = "Kinoko"
    $env:JAVA_HOME = Split-Path -Parent (Split-Path -Parent $javaExe)

    $serverProc = Start-Process `
        -FilePath $javaExe `
        -ArgumentList "-jar target/server.jar" `
        -WorkingDirectory $repoRoot `
        -RedirectStandardOutput (Join-Path $logsDir "server.out.log") `
        -RedirectStandardError (Join-Path $logsDir "server.err.log") `
        -PassThru

    Start-Sleep -Seconds 4
    if ($serverProc.HasExited) {
        $errLog = Join-Path $logsDir "server.err.log"
        $tail = if (Test-Path $errLog) { (Get-Content $errLog -Tail 30) -join [Environment]::NewLine } else { "Sem server.err.log" }
        throw "Servidor encerrou durante inicializacao.`n$tail"
    }
}

if (-not (Wait-LoginPort 20)) {
    throw "Servidor nao abriu a porta 8484 dentro do tempo esperado."
}

Write-Host "OK: Cassandra e servidor iniciados."
Write-Host "Login online em 127.0.0.1:8484"
Write-Host "Log do servidor: $logsDir\\server.out.log"
