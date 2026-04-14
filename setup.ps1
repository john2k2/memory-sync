# memory-sync/setup.ps1 — v2.0
# Setup y verificacion completa de Engram + Git sync en Windows.
# Uso: .\setup.ps1
# Requiere: PowerShell 5+ y Git for Windows instalado.

$ErrorActionPreference = "Continue"

$GITHUB_USER = "john2k2"
$REPO_NAME   = "engram-memory"
$REPO_URL    = "https://github.com/$GITHUB_USER/$REPO_NAME.git"
$ENGRAM_DIR  = "$env:USERPROFILE\.engram"
$SCRIPTS_DIR = "$env:USERPROFILE\bin"

$ERRORS = 0

function Ok   { param($msg) Write-Host "  [+] $msg" -ForegroundColor Green }
function Warn { param($msg) Write-Host "  [!] $msg" -ForegroundColor Yellow }
function Info { param($msg) Write-Host "  --> $msg" -ForegroundColor Cyan }
function Fail { param($msg) Write-Host "  [x] $msg" -ForegroundColor Red; $script:ERRORS++ }
function Step { param($n, $msg) Write-Host "`n[$n] $msg" -ForegroundColor Cyan }

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "       memory-sync setup v2.0              " -ForegroundColor Cyan
Write-Host "   Engram + Git sync -- Windows            " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ─── 1. Verificar dependencias ────────────────────────────────────────────────
Step "1/6" "Verificando dependencias"

# Git
if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitVersion = (git --version) -replace "git version ", ""
    Ok "git $gitVersion"
} else {
    Fail "git no esta instalado -- descargalo de https://gitforwindows.org"
}

# Engram
if (Get-Command engram -ErrorAction SilentlyContinue) {
    $engramVersion = (engram version 2>$null | Select-Object -First 1) ?? "(version desconocida)"
    Ok "engram $engramVersion"
} else {
    Info "engram no encontrado, instalando..."

    New-Item -ItemType Directory -Force -Path $SCRIPTS_DIR | Out-Null

    # Preferir go install si Go esta disponible
    if (Get-Command go -ErrorAction SilentlyContinue) {
        Info "Instalando via 'go install'..."
        go install github.com/Gentleman-Programming/engram/cmd/engram@latest
        if ($LASTEXITCODE -eq 0) {
            Ok "engram instalado via go"
        } else {
            Fail "go install fallo"
        }
    } else {
        Info "Go no encontrado, descargando binario..."

        $arch = if ([Environment]::Is64BitOperatingSystem) { "amd64" } else { "386" }
        $apiUrl = "https://api.github.com/repos/Gentleman-Programming/engram/releases/latest"
        try {
            $release = Invoke-RestMethod -Uri $apiUrl -Headers @{ "User-Agent" = "memory-sync-setup" }
            $latest = $release.tag_name
            $zipName = "engram_$($latest.TrimStart('v'))_windows_$arch.zip"
            $asset = $release.assets | Where-Object { $_.name -eq $zipName } | Select-Object -First 1

            if (-not $asset) {
                Fail "No se encontro el binario $zipName en los releases"
            } else {
                $zipPath = "$env:TEMP\engram.zip"
                Info "Descargando $zipName..."
                Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath

                Expand-Archive -Path $zipPath -DestinationPath "$env:TEMP\engram-extract" -Force
                $exePath = Get-ChildItem "$env:TEMP\engram-extract" -Filter "engram.exe" -Recurse | Select-Object -First 1
                if ($exePath) {
                    Copy-Item $exePath.FullName "$SCRIPTS_DIR\engram.exe" -Force
                    Ok "engram $latest instalado en $SCRIPTS_DIR"
                } else {
                    Fail "No se encontro engram.exe en el zip"
                }
                Remove-Item $zipPath -Force
                Remove-Item "$env:TEMP\engram-extract" -Recurse -Force
            }
        } catch {
            Fail "Error descargando engram: $_"
        }
    }

    # Verificar que este en el PATH
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$SCRIPTS_DIR*") {
        Info "Agregando $SCRIPTS_DIR al PATH del usuario..."
        [Environment]::SetEnvironmentVariable("Path", "$SCRIPTS_DIR;$userPath", "User")
        $env:PATH = "$SCRIPTS_DIR;$env:PATH"
        Warn "PATH actualizado -- reinicia la terminal para que tome efecto permanentemente"
    }
}

if (-not (Get-Command engram -ErrorAction SilentlyContinue)) {
    Fail "engram no esta disponible en el PATH -- reinicia la terminal e intenta de nuevo"
}

# ─── 2. Verificar acceso a GitHub ────────────────────────────────────────────
Step "2/6" "Verificando acceso a GitHub"

if (Get-Command gh -ErrorAction SilentlyContinue) {
    $ghStatus = gh auth status 2>&1
    if ($LASTEXITCODE -eq 0) {
        $ghUser = gh api user --jq '.login' 2>$null
        Ok "GitHub CLI autenticado como $ghUser"

        $repoExists = gh repo view "$GITHUB_USER/$REPO_NAME" 2>$null
        if ($LASTEXITCODE -ne 0) {
            Info "Creando repo privado $REPO_NAME..."
            gh repo create $REPO_NAME --private --description "Engram memory sync across machines" | Out-Null
            Ok "Repo $GITHUB_USER/$REPO_NAME creado"
        } else {
            Ok "Repo $GITHUB_USER/$REPO_NAME ya existe"
        }
    } else {
        Warn "GitHub CLI no autenticado -- ejecuta: gh auth login"
    }
} else {
    Warn "GitHub CLI no instalado -- verificando acceso directo al repo..."
    try {
        $null = git ls-remote $REPO_URL HEAD 2>&1
        if ($LASTEXITCODE -eq 0) { Ok "Repo $REPO_URL accesible" }
        else { Warn "No se pudo verificar el repo -- puede fallar el clone" }
    } catch {
        Warn "No se pudo verificar acceso al repo"
    }
}

# ─── 3. Configurar ~/.engram como repo git ───────────────────────────────────
Step "3/6" "Configurando $ENGRAM_DIR"

New-Item -ItemType Directory -Force -Path $ENGRAM_DIR | Out-Null

if (Test-Path "$ENGRAM_DIR\.git") {
    Ok "$ENGRAM_DIR ya es un repositorio git"
    $currentRemote = git -C $ENGRAM_DIR remote get-url origin 2>$null
    if ($currentRemote -ne $REPO_URL) {
        Info "Actualizando remote: $currentRemote -> $REPO_URL"
        git -C $ENGRAM_DIR remote set-url origin $REPO_URL
        Ok "Remote actualizado"
    } else {
        Ok "Remote correcto: $REPO_URL"
    }
} else {
    Info "Inicializando git en $ENGRAM_DIR..."
    git -C $ENGRAM_DIR init -q
    git -C $ENGRAM_DIR branch -M main 2>$null

    $gitignoreContent = "engram.db`nengram.db-shm`nengram.db-wal`n*.log`n"
    Set-Content -Path "$ENGRAM_DIR\.gitignore" -Value $gitignoreContent -Encoding UTF8

    git -C $ENGRAM_DIR remote add origin $REPO_URL

    # Intentar traer historial remoto
    git -C $ENGRAM_DIR fetch origin main -q 2>$null
    if ($LASTEXITCODE -eq 0) {
        Info "Incorporando historial remoto..."
        git -C $ENGRAM_DIR reset --hard origin/main -q 2>$null
        Ok "Historial remoto incorporado"
    } else {
        Info "Sin historial remoto -- iniciando desde cero"
        git -C $ENGRAM_DIR add .gitignore 2>$null
        if (Test-Path "$ENGRAM_DIR\manifest.json") {
            git -C $ENGRAM_DIR add manifest.json 2>$null
        }
        if (Test-Path "$ENGRAM_DIR\chunks") {
            git -C $ENGRAM_DIR add chunks/ 2>$null
        }
        $staged = git -C $ENGRAM_DIR diff --staged --quiet 2>$null; $hasStaged = $LASTEXITCODE -ne 0
        if ($hasStaged) {
            git -C $ENGRAM_DIR commit -m "init: engram memory sync" -q
        }
        git -C $ENGRAM_DIR push -u origin main -q 2>$null
        if ($LASTEXITCODE -eq 0) { Ok "Repo subido a GitHub" }
        else { Warn "No se pudo hacer push -- verifica credenciales de GitHub" }
    }
}

# ─── 4. Sincronizar memoria ───────────────────────────────────────────────────
Step "4/6" "Sincronizando memoria"

Info "Trayendo cambios remotos..."
git -C $ENGRAM_DIR pull --rebase --autostash -q 2>$null
if ($LASTEXITCODE -ne 0) { Warn "git pull fallo -- puede no haber conexion" }
else { Ok "Pull exitoso" }

Info "Importando chunks a la DB local..."
engram sync --import 2>$null
if ($LASTEXITCODE -eq 0) { Ok "Chunks importados" } else { Warn "Sin chunks nuevos para importar" }

Info "Exportando memoria local como chunks..."
engram sync 2>$null
if ($LASTEXITCODE -eq 0) { Ok "Chunks exportados" } else { Warn "Sin observaciones nuevas para exportar" }

git -C $ENGRAM_DIR add chunks/ manifest.json 2>$null
$hasChanges = (git -C $ENGRAM_DIR diff --staged --quiet 2>$null; $LASTEXITCODE -ne 0)
if ($hasChanges) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    git -C $ENGRAM_DIR commit -m "sync: setup $timestamp" -q
    git -C $ENGRAM_DIR push -q 2>$null
    if ($LASTEXITCODE -eq 0) { Ok "Memoria subida a GitHub" } else { Warn "Push fallo" }
} else {
    Ok "Sin cambios pendientes"
}

# ─── 5. Instalar scripts de sync ─────────────────────────────────────────────
Step "5/7" "Instalando scripts de sync"

New-Item -ItemType Directory -Force -Path $SCRIPTS_DIR | Out-Null

$pullScript = @'
$ErrorActionPreference = "Continue"
Set-Location "$env:USERPROFILE\.engram"
git pull --rebase --autostash 2>$null
engram sync --import 2>$null
Write-Host "[+] Memoria sincronizada" -ForegroundColor Green
'@

$pushScript = @'
$ErrorActionPreference = "Stop"
Set-Location "$env:USERPROFILE\.engram"
engram sync
git add chunks/ manifest.json 2>$null
$hasChanges = (git diff --staged --quiet 2>$null; $LASTEXITCODE -ne 0)
if ($hasChanges) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    git commit -m "sync: $timestamp"
    git push
    Write-Host "[+] Memoria subida a GitHub" -ForegroundColor Green
} else {
    Write-Host "-- Sin cambios para sincronizar" -ForegroundColor Gray
}
'@

Set-Content -Path "$SCRIPTS_DIR\engram-pull.ps1" -Value $pullScript -Encoding UTF8
Set-Content -Path "$SCRIPTS_DIR\engram-push.ps1" -Value $pushScript -Encoding UTF8
Ok "engram-pull.ps1 y engram-push.ps1 instalados en $SCRIPTS_DIR"

# ─── 6. Configurar herramientas de IA ────────────────────────────────────────
Step "6/7" "Configurando herramientas de IA"

# Claude Code
if (Get-Command claude -ErrorAction SilentlyContinue) {
    $claudeSettings = "$env:USERPROFILE\.claude\settings.json"
    $alreadyConfigured = (Test-Path $claudeSettings) -and ((Get-Content $claudeSettings -Raw) -match '"engram"')
    if ($alreadyConfigured) {
        Ok "Claude Code -- Engram ya configurado"
    } else {
        Info "Configurando Engram en Claude Code..."
        engram setup claude-code 2>$null
        if ($LASTEXITCODE -eq 0) { Ok "Claude Code configurado" }
        else { Warn "Configura manualmente -- ver README" }
    }
} else {
    Warn "Claude Code no instalado -- saltando"
}

# OpenCode
if (Get-Command opencode -ErrorAction SilentlyContinue) {
    $opencodeSettings = "$env:APPDATA\opencode\opencode.json"
    $alreadyConfigured = (Test-Path $opencodeSettings) -and ((Get-Content $opencodeSettings -Raw) -match '"engram"')
    if ($alreadyConfigured) {
        Ok "OpenCode -- Engram ya configurado"
    } else {
        Info "Configurando Engram en OpenCode..."
        engram setup opencode 2>$null
        if ($LASTEXITCODE -eq 0) { Ok "OpenCode configurado" }
        else { Warn "Configura manualmente -- ver README" }
    }
} else {
    Warn "OpenCode no instalado -- saltando"
}

# Qwen Code
if (Get-Command qwen -ErrorAction SilentlyContinue) {
    $qwenSettings = "$env:USERPROFILE\.qwen\settings.json"
    $alreadyConfigured = (Test-Path $qwenSettings) -and ((Get-Content $qwenSettings -Raw) -match '"engram"')
    if ($alreadyConfigured) {
        Ok "Qwen Code -- Engram ya configurado"
    } else {
        Info "Configurando Engram en Qwen Code..."
        qwen mcp add --scope user --transport stdio engram engram mcp 2>$null
        if ($LASTEXITCODE -eq 0) { Ok "Qwen Code configurado" }
        else { Warn "Configura manualmente -- ver README" }
    }
} else {
    Warn "Qwen Code no instalado -- saltando"
}

# ─── 7. Configurar sync automático cada 30 minutos (Task Scheduler) ──────────
Step "7/7" "Configurando sync automatico"

$taskName = "EngramSync"
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($existingTask) {
    Ok "Task Scheduler ya configurado -- sin cambios"
} else {
    try {
        $action = New-ScheduledTaskAction `
            -Execute "powershell.exe" `
            -Argument "-WindowStyle Hidden -NonInteractive -File `"$SCRIPTS_DIR\engram-push.ps1`""

        # Trigger: repetir cada 30 minutos indefinidamente
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
            -RepetitionInterval (New-TimeSpan -Minutes 30) `
            -RepetitionDuration ([TimeSpan]::MaxValue)

        $settings = New-ScheduledTaskSettingsSet `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
            -StartWhenAvailable `
            -RunOnlyIfNetworkAvailable

        Register-ScheduledTask `
            -TaskName $taskName `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Description "Engram memory sync to GitHub every 30 minutes" `
            -RunLevel Highest | Out-Null

        Ok "Task Scheduler configurado: sync cada 30 min en segundo plano"
    } catch {
        Warn "No se pudo configurar Task Scheduler: $_"
        Warn "Ejecuta el setup como Administrador si el problema persiste"
    }
}

# ─── Resumen ──────────────────────────────────────────────────────────────────
$chunkCount = (Get-ChildItem "$ENGRAM_DIR\chunks" -Filter "*.jsonl.gz" -ErrorAction SilentlyContinue).Count
$dbSize = if (Test-Path "$ENGRAM_DIR\engram.db") {
    "{0:N0} KB" -f ((Get-Item "$ENGRAM_DIR\engram.db").Length / 1KB)
} else { "--" }

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
if ($ERRORS -eq 0) {
    Write-Host "         Setup completado [+]              " -ForegroundColor Green
} else {
    Write-Host "   Setup con $ERRORS error(es) -- revisa [x]  " -ForegroundColor Red
}
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Base de datos:   $dbSize"
Write-Host "  Chunks:          $chunkCount"
Write-Host "  Repo GitHub:     https://github.com/$GITHUB_USER/$REPO_NAME"
Write-Host ""
Write-Host "  Al iniciar sesion:  engram-pull.ps1"
Write-Host "  Al terminar:        engram-push.ps1"
Write-Host ""
if ($ERRORS -gt 0) {
    Write-Host "  [x] Revisa los errores marcados arriba." -ForegroundColor Red
    Write-Host ""
}
