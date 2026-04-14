#!/bin/bash
# memory-sync/setup.sh — v2.0
# Setup y verificación completa de Engram + Git sync en Linux/macOS.
# Uso: bash setup.sh
set -e

GITHUB_USER="john2k2"
REPO_NAME="engram-memory"
REPO_URL="https://github.com/$GITHUB_USER/$REPO_NAME.git"
ENGRAM_DIR="$HOME/.engram"
SCRIPTS_DIR="$HOME/.local/bin"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

ok()   { echo -e "${GREEN}  ✓${NC} $1"; }
warn() { echo -e "${YELLOW}  ⚠${NC}  $1"; }
err()  { echo -e "${RED}  ✗${NC} $1"; }
info() { echo -e "${CYAN}  →${NC} $1"; }
step() { echo -e "\n${CYAN}[$1]${NC} $2"; }

ERRORS=0
fail() { err "$1"; ERRORS=$((ERRORS + 1)); }

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       memory-sync setup v2.0             ║"
echo "║   Engram + Git sync — Linux / macOS      ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ─── 1. Verificar dependencias ────────────────────────────────────────────────
step "1/6" "Verificando dependencias"

if command -v git &>/dev/null; then
  ok "git $(git --version | awk '{print $3}')"
else
  fail "git no está instalado — sudo dnf install git / sudo apt install git"
fi

if command -v engram &>/dev/null; then
  ok "engram $(engram version 2>/dev/null | head -1 || echo '(versión desconocida)')"
else
  info "engram no encontrado, instalando..."

  mkdir -p "$SCRIPTS_DIR"

  if command -v go &>/dev/null; then
    go install github.com/Gentleman-Programming/engram/cmd/engram@latest
    ok "engram instalado via go"
  elif command -v brew &>/dev/null; then
    brew install gentleman-programming/tap/engram
    ok "engram instalado via brew"
  else
    ARCH=$(uname -m); OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    [ "$ARCH" = "x86_64" ]  && ARCH="amd64"
    [ "$ARCH" = "aarch64" ] && ARCH="arm64"

    LATEST=$(curl -fsSL "https://api.github.com/repos/Gentleman-Programming/engram/releases/latest" \
      | grep '"tag_name"' | cut -d'"' -f4)
    [ -z "$LATEST" ] && { fail "No se pudo obtener última versión de engram"; exit 1; }

    TARBALL="engram_${LATEST#v}_${OS}_${ARCH}.tar.gz"
    curl -fsSL "https://github.com/Gentleman-Programming/engram/releases/download/$LATEST/$TARBALL" \
      -o "/tmp/engram.tar.gz" || { fail "Error descargando engram"; exit 1; }
    tar -xzf "/tmp/engram.tar.gz" -C "$SCRIPTS_DIR" engram 2>/dev/null \
      || tar -xzf "/tmp/engram.tar.gz" -C "/tmp/" && mv /tmp/engram "$SCRIPTS_DIR/"
    chmod +x "$SCRIPTS_DIR/engram"
    rm -f /tmp/engram.tar.gz
    export PATH="$SCRIPTS_DIR:$PATH"
    ok "engram $LATEST instalado en $SCRIPTS_DIR"
  fi

  command -v engram &>/dev/null || { fail "engram no quedó en el PATH"; exit 1; }
fi

if ! echo "$PATH" | grep -q "$SCRIPTS_DIR"; then
  warn "$SCRIPTS_DIR no está en el PATH — agregá a tu shell: export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# ─── 2. Verificar acceso a GitHub ────────────────────────────────────────────
step "2/6" "Verificando acceso a GitHub"

if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "")
  ok "GitHub CLI autenticado como $GH_USER"

  if ! gh repo view "$GITHUB_USER/$REPO_NAME" &>/dev/null 2>&1; then
    info "Creando repo privado $REPO_NAME..."
    gh repo create "$REPO_NAME" --private --description "Engram memory sync across machines" &>/dev/null
    ok "Repo $GITHUB_USER/$REPO_NAME creado"
  else
    ok "Repo $GITHUB_USER/$REPO_NAME ya existe"
  fi
else
  warn "GitHub CLI no disponible o no autenticado"
  if git ls-remote "$REPO_URL" HEAD &>/dev/null 2>&1; then
    ok "Repo $REPO_URL accesible via HTTPS"
  else
    warn "No se pudo verificar acceso al repo — si falla el clone, ejecutá: gh auth login"
  fi
fi

# ─── 3. Configurar ~/.engram como repo git ───────────────────────────────────
step "3/6" "Configurando ~/.engram"

mkdir -p "$ENGRAM_DIR"

if [ -d "$ENGRAM_DIR/.git" ]; then
  ok "~/.engram ya es un repositorio git"
  CURRENT_REMOTE=$(git -C "$ENGRAM_DIR" remote get-url origin 2>/dev/null || echo "")
  if [ "$CURRENT_REMOTE" != "$REPO_URL" ]; then
    info "Actualizando remote: $CURRENT_REMOTE → $REPO_URL"
    git -C "$ENGRAM_DIR" remote set-url origin "$REPO_URL"
    ok "Remote actualizado"
  else
    ok "Remote correcto: $REPO_URL"
  fi
else
  info "Inicializando git en ~/.engram..."
  git -C "$ENGRAM_DIR" init -q
  git -C "$ENGRAM_DIR" branch -M main 2>/dev/null || true

  cat > "$ENGRAM_DIR/.gitignore" << 'EOF'
engram.db
engram.db-shm
engram.db-wal
*.log
EOF

  git -C "$ENGRAM_DIR" remote add origin "$REPO_URL"

  # Traer historial remoto si existe
  if git -C "$ENGRAM_DIR" fetch origin main -q &>/dev/null 2>&1; then
    info "Incorporando historial remoto..."
    git -C "$ENGRAM_DIR" reset --hard origin/main -q 2>/dev/null || \
      git -C "$ENGRAM_DIR" checkout -B main origin/main -q 2>/dev/null || true
    ok "Historial remoto incorporado"
  else
    info "Sin historial remoto previo — iniciando desde cero"
    git -C "$ENGRAM_DIR" add .gitignore 2>/dev/null || true
    [ -f "$ENGRAM_DIR/manifest.json" ] && git -C "$ENGRAM_DIR" add manifest.json 2>/dev/null || true
    ls "$ENGRAM_DIR/chunks/"*.jsonl.gz &>/dev/null 2>&1 && \
      git -C "$ENGRAM_DIR" add chunks/ 2>/dev/null || true
    git -C "$ENGRAM_DIR" diff --staged --quiet 2>/dev/null || \
      git -C "$ENGRAM_DIR" commit -m "init: engram memory sync" -q
    git -C "$ENGRAM_DIR" push -u origin main -q && ok "Repo subido a GitHub" || \
      warn "No se pudo hacer push — verificá credenciales de GitHub"
  fi
fi

# ─── 4. Sincronizar memoria ───────────────────────────────────────────────────
step "4/6" "Sincronizando memoria"

info "Trayendo cambios remotos..."
git -C "$ENGRAM_DIR" pull --rebase --autostash -q 2>/dev/null || \
  warn "pull falló — puede no haber conexión o ser el primer setup"

info "Importando chunks a la DB local..."
engram sync --import 2>/dev/null && ok "Chunks importados" || \
  warn "Sin chunks nuevos para importar"

info "Exportando memoria local como chunks..."
engram sync 2>/dev/null && ok "Chunks exportados" || \
  warn "Sin observaciones nuevas para exportar"

git -C "$ENGRAM_DIR" add chunks/ manifest.json &>/dev/null 2>/dev/null || true
if ! git -C "$ENGRAM_DIR" diff --staged --quiet 2>/dev/null; then
  git -C "$ENGRAM_DIR" commit -m "sync: setup $(date '+%Y-%m-%d %H:%M:%S')" -q
  git -C "$ENGRAM_DIR" push -q && ok "Memoria subida a GitHub" || warn "Push falló"
else
  ok "Sin cambios pendientes"
fi

# ─── 5. Instalar scripts de sync ─────────────────────────────────────────────
step "5/7" "Instalando scripts de sync"

mkdir -p "$SCRIPTS_DIR"

cat > "$SCRIPTS_DIR/engram-pull.sh" << 'SCRIPT'
#!/bin/bash
set -e
cd "$HOME/.engram"
git pull --rebase --autostash 2>/dev/null || true
engram sync --import 2>/dev/null || true
echo "✓ Memoria sincronizada"
SCRIPT

cat > "$SCRIPTS_DIR/engram-push.sh" << 'SCRIPT'
#!/bin/bash
set -e
cd "$HOME/.engram"
engram sync
git add chunks/ manifest.json 2>/dev/null || true
if git diff --staged --quiet; then
  echo "— Sin cambios para sincronizar"
else
  git commit -m "sync: $(date '+%Y-%m-%d %H:%M:%S')"
  git push
  echo "✓ Memoria subida a GitHub"
fi
SCRIPT

chmod +x "$SCRIPTS_DIR/engram-pull.sh" "$SCRIPTS_DIR/engram-push.sh"
ok "engram-pull.sh y engram-push.sh instalados en $SCRIPTS_DIR"

# ─── 6. Configurar herramientas de IA ────────────────────────────────────────
step "6/7" "Configurando herramientas de IA"

# Claude Code
if command -v claude &>/dev/null; then
  if grep -q '"engram"' "$HOME/.claude/settings.json" 2>/dev/null; then
    ok "Claude Code — Engram ya configurado"
  else
    info "Configurando Engram en Claude Code..."
    engram setup claude-code 2>/dev/null && ok "Claude Code configurado" || \
      warn "Configurá manualmente — ver README"
  fi
else
  warn "Claude Code no instalado — saltando"
fi

# OpenCode
if command -v opencode &>/dev/null; then
  OPENCODE_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json"
  if grep -q '"engram"' "$OPENCODE_CFG" 2>/dev/null; then
    ok "OpenCode — Engram ya configurado"
  else
    info "Configurando Engram en OpenCode..."
    engram setup opencode 2>/dev/null && ok "OpenCode configurado" || \
      warn "Configurá manualmente — ver README"
  fi
else
  warn "OpenCode no instalado — saltando"
fi

# Qwen Code
if command -v qwen &>/dev/null; then
  if grep -q '"engram"' "$HOME/.qwen/settings.json" 2>/dev/null; then
    ok "Qwen Code — Engram ya configurado"
  else
    info "Configurando Engram en Qwen Code..."
    qwen mcp add --scope user --transport stdio engram engram mcp 2>/dev/null && \
      ok "Qwen Code configurado" || warn "Configurá manualmente — ver README"
  fi
else
  warn "Qwen Code no instalado — saltando"
fi

# ─── 7. Configurar sync automático cada 30 minutos ───────────────────────────
step "7/7" "Configurando sync automático"

CRON_JOB="*/30 * * * * $SCRIPTS_DIR/engram-push.sh >> $ENGRAM_DIR/sync.log 2>&1"

if crontab -l 2>/dev/null | grep -q "engram-push.sh"; then
  ok "Cron ya configurado — sin cambios"
else
  # Limpiar entradas viejas de engram si las hay
  (crontab -l 2>/dev/null | grep -v "engram"; echo "$CRON_JOB") | crontab -
  ok "Cron configurado: sync cada 30 minutos en segundo plano"
fi

# ─── Resumen ──────────────────────────────────────────────────────────────────
CHUNK_COUNT=$(ls "$ENGRAM_DIR/chunks/"*.jsonl.gz 2>/dev/null | wc -l || echo 0)
DB_SIZE=$(du -sh "$ENGRAM_DIR/engram.db" 2>/dev/null | cut -f1 || echo "—")

echo ""
echo "╔══════════════════════════════════════════╗"
[ "$ERRORS" -eq 0 ] && \
  echo "║          Setup completado ✓              ║" || \
  echo "║    Setup con $ERRORS error(es) — revisá ✗       ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Base de datos:   $DB_SIZE"
echo "  Chunks:          $CHUNK_COUNT"
echo "  Repo GitHub:     https://github.com/$GITHUB_USER/$REPO_NAME"
echo ""
echo "  Al iniciar sesión:  engram-pull.sh"
echo "  Al terminar:        engram-push.sh"
echo ""
if [ "$ERRORS" -gt 0 ]; then echo "  ✗ Revisá los errores marcados arriba."; echo ""; fi
