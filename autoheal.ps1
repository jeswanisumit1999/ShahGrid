# ============================================================
#  ShahGrid Auto-Heal Script
#  Monitors Docker containers and restarts unhealthy services.
#  Run once via Task Scheduler; set to repeat every 5 minutes.
# ============================================================

param(
    [string]$ProjectDir = "C:\ShahGrid",
    [string]$HealthUrl  = "http://localhost",
    [string]$DockerDesktopPath = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
)

$LogDir  = Join-Path $ProjectDir "logs"
$LogFile = Join-Path $LogDir "autoheal.log"
$MaxLogBytes = 5MB

# ── Logging ──────────────────────────────────────────────────────────────────

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Write-Host $line

    # Rotate log when it exceeds MaxLogBytes
    if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt $MaxLogBytes) {
        $archive = $LogFile -replace '\.log$', ("_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
        Rename-Item $LogFile $archive -Force
    }

    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

# ── Docker helpers ────────────────────────────────────────────────────────────

function Test-DockerRunning {
    docker info 2>&1 | Out-Null
    return $LASTEXITCODE -eq 0
}

function Start-DockerDesktop {
    if (-not (Test-Path $DockerDesktopPath)) {
        Write-Log "Docker Desktop not found at: $DockerDesktopPath" "ERROR"
        return $false
    }

    Write-Log "Docker Desktop not running — starting it now..."
    Start-Process $DockerDesktopPath

    # Wait up to 2 minutes for Docker to become ready
    for ($i = 0; $i -lt 24; $i++) {
        Start-Sleep 5
        if (Test-DockerRunning) {
            Write-Log "Docker Desktop is ready."
            return $true
        }
    }

    Write-Log "Docker Desktop did not become ready within 2 minutes." "ERROR"
    return $false
}

function Get-ServiceStatuses {
    # Returns: hashtable { serviceName -> @{ State; Health } }
    $statuses = @{}
    $lines = docker compose --project-directory $ProjectDir ps `
                 --format "{{.Service}}|{{.State}}|{{.Health}}" 2>&1

    foreach ($line in $lines) {
        $line = $line.Trim()
        if (-not $line -or $line -notmatch '\|') { continue }
        $parts = $line -split '\|'
        $statuses[$parts[0]] = @{
            State  = $parts[1]
            Health = if ($parts.Count -ge 3) { $parts[2] } else { "" }
        }
    }
    return $statuses
}

function Invoke-ComposeCommand {
    param([string[]]$Args)
    $output = docker compose --project-directory $ProjectDir @Args 2>&1
    $output | ForEach-Object { Write-Log "  docker: $_" }
    return $LASTEXITCODE
}

# ── Health check ──────────────────────────────────────────────────────────────

function Test-BackendHttp {
    try {
        $resp = Invoke-WebRequest -Uri "$HealthUrl/health" `
                    -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        return $resp.StatusCode -lt 400
    }
    catch { return $false }
}

# ── Core heal logic ───────────────────────────────────────────────────────────

function Invoke-Heal {
    Write-Log "===== Health check started ====="

    # 1. Ensure Docker is running
    if (-not (Test-DockerRunning)) {
        $ok = Start-DockerDesktop
        if (-not $ok) {
            Write-Log "Aborting — Docker is unavailable." "ERROR"
            return
        }
        Start-Sleep 10  # let Docker settle before issuing compose commands
    }

    # 2. Fetch container statuses
    $statuses = Get-ServiceStatuses

    # 3. No containers found → bring the whole stack up
    if ($statuses.Count -eq 0) {
        Write-Log "No containers running — bringing stack up..." "WARN"
        Invoke-ComposeCommand "up", "-d" | Out-Null
        Start-Sleep 15
        $statuses = Get-ServiceStatuses   # re-read after start
    }

    # 4. Restart any stopped or unhealthy container
    $restarted = @()
    foreach ($svc in $statuses.Keys) {
        $s = $statuses[$svc]
        $isDown      = $s.State -ne "running"
        $isUnhealthy = $s.Health -eq "unhealthy"

        if ($isDown -or $isUnhealthy) {
            Write-Log "[$svc] unhealthy  state=$($s.State)  health=$($s.Health)" "WARN"
            Write-Log "[$svc] Restarting..."
            Invoke-ComposeCommand "restart", $svc | Out-Null
            $restarted += $svc
        }
        else {
            Write-Log "[$svc] OK  state=$($s.State)"
        }
    }

    # Wait for restarted containers to stabilise
    if ($restarted.Count -gt 0) {
        Write-Log "Waiting 15 s for restarted containers to stabilise..."
        Start-Sleep 15
    }

    # 5. HTTP health check against the backend
    if (Test-BackendHttp) {
        Write-Log "Backend HTTP health check PASSED."
    }
    else {
        Write-Log "Backend HTTP health check FAILED — restarting backend + nginx..." "WARN"
        Invoke-ComposeCommand "restart", "backend", "nginx" | Out-Null
        Start-Sleep 15

        # Final HTTP check
        if (Test-BackendHttp) {
            Write-Log "Backend recovered after restart."
        }
        else {
            Write-Log "Backend still unhealthy after restart — manual intervention may be needed." "ERROR"

            # Write a Windows Event so it shows in Event Viewer
            Write-EventLog -LogName Application -Source "ShahGrid-AutoHeal" `
                -EntryType Error -EventId 1001 `
                -Message "ShahGrid backend failed to recover after auto-restart. Check logs at $LogFile" `
                -ErrorAction SilentlyContinue
        }
    }

    Write-Log "===== Health check complete ====="
}

# ── Entry point ───────────────────────────────────────────────────────────────

$null = New-Item -ItemType Directory -Path $LogDir -Force

# Register the event source once (silently ignore if already registered)
New-EventLog -LogName Application -Source "ShahGrid-AutoHeal" -ErrorAction SilentlyContinue

Invoke-Heal
