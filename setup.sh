#!/bin/bash
# memory-sync/setup.sh
# Setup completo de Engram + rclone + Google Drive en una PC nueva.
# Uso: bash setup.sh
set -e

GDRIVE_REMOTE="gdrive:TRABAJO/engram-sync"
CRON_JOB="0 * * * * $HOME/.local/bin/engram-sync.sh >> $HOME/.engram/sync.log 2>&1"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}→${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
error()   { echo -e "${RED}✗${NC} $1"; exit 1; }

echo ""
echo "╔══════════════════════════════════════╗"
echo "║        memory-sync setup v1.0        ║"
echo "║  Engram + rclone + Google Drive      ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ─── 1. Detectar OS y package manager ─────────────────────────────────────────
info "Detectando sistema operativo..."
if command -v dnf &>/dev/null; then
  PKG="sudo dnf install -y"
elif command -v apt-get &>/dev/null; then
  PKG="sudo apt-get install -y"
elif command -v brew &>/dev/null; then
  PKG="brew install"
else
  error "No se encontró un package manager compatible (dnf/apt/brew)."
fi
success "Package manager: $PKG"

# ─── 2. Instalar dependencias ──────────────────────────────────────────────────
info "Instalando dependencias (rclone, curl)..."
if ! command -v rclone &>/dev/null; then
  $PKG rclone
  success "rclone instalado"
else
  success "rclone ya está instalado ($(rclone version --check 2>/dev/null | head -1 || rclone --version | head -1))"
fi

if ! command -v curl &>/dev/null; then
  $PKG curl
fi

# ─── 3. Instalar Engram ────────────────────────────────────────────────────────
info "Verificando Engram..."
if ! command -v engram &>/dev/null; then
  info "Instalando Engram..."
  curl -fsSL https://github.com/hyperling/engram/releases/latest/download/engram-linux-amd64 \
    -o "$HOME/.local/bin/engram" 2>/dev/null || true

  # Fallback: instalar via npm si el binario no existe
  if [ ! -f "$HOME/.local/bin/engram" ]; then
    warn "Binario no encontrado, intentando via npm..."
    npm install -g engram 2>/dev/null || error "No se pudo instalar Engram. Instalalo manualmente: https://engram.dev"
  else
    chmod +x "$HOME/.local/bin/engram"
  fi
  success "Engram instalado"
else
  success "Engram ya está instalado ($(engram version 2>/dev/null || echo 'version desconocida'))"
fi

mkdir -p "$HOME/.engram"
mkdir -p "$HOME/.local/bin"

# ─── 4. Configurar rclone con Google Drive ────────────────────────────────────
info "Verificando configuración de rclone..."
RCLONE_CONFIG="$HOME/.config/rclone/rclone.conf"

if ! rclone listremotes 2>/dev/null | grep -q "gdrive:"; then
  echo ""
  warn "rclone no tiene Google Drive configurado."
  warn "Se abrirá el asistente de configuración. Seguí estos pasos:"
  echo ""
  echo "  1. Ingresá 'n' para crear un nuevo remote"
  echo "  2. Name: gdrive"
  echo "  3. Storage: Google Drive (buscar por número)"
  echo "  4. Client ID y Secret: Enter (vacío)"
  echo "  5. Scope: 1 (full access)"
  echo "  6. Todo lo demás: Enter (defaults)"
  echo "  7. 'n' en Edit advanced config"
  echo "  8. 'y' en Use auto config → se abre el browser → autorizás"
  echo "  9. 'n' en Shared Drive"
  echo " 10. 'y' para confirmar"
  echo ""
  read -p "Presioná Enter para abrir el asistente de rclone..."
  rclone config
else
  success "rclone ya tiene Google Drive configurado"
fi

# Verificar conexión
info "Verificando conexión con Google Drive..."
if ! rclone lsd gdrive: &>/dev/null; then
  error "No se pudo conectar a Google Drive. Revisá la configuración con: rclone config"
fi
success "Google Drive conectado"

# Crear carpeta de sync si no existe
rclone mkdir "$GDRIVE_REMOTE" 2>/dev/null || true
success "Carpeta $GDRIVE_REMOTE lista"

# ─── 5. Instalar script de sync ───────────────────────────────────────────────
info "Instalando engram-sync.sh..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/engram-sync.sh" "$HOME/.local/bin/engram-sync.sh"
chmod +x "$HOME/.local/bin/engram-sync.sh"
success "Script instalado en ~/.local/bin/engram-sync.sh"

# ─── 6. Restaurar memorias desde Google Drive ─────────────────────────────────
echo ""
info "Buscando memorias existentes en Google Drive..."
CHUNK_COUNT=$(rclone ls "$GDRIVE_REMOTE" 2>/dev/null | grep -c ".jsonl.gz" || echo "0")

if [ "$CHUNK_COUNT" -gt 0 ]; then
  info "Encontrados $CHUNK_COUNT chunks. Restaurando..."

  # Descargar todos los chunks
  RESTORE_DIR="$HOME/.engram/restore-tmp"
  mkdir -p "$RESTORE_DIR"
  rclone copy "$GDRIVE_REMOTE" "$RESTORE_DIR" --include "*.jsonl.gz" --log-level ERROR

  # Importar a Engram
  find "$RESTORE_DIR" -name "*.jsonl.gz" | while read chunk; do
    engram sync --import "$chunk" 2>/dev/null || true
  done
  rm -rf "$RESTORE_DIR"
  success "Memorias restauradas desde Google Drive"
else
  warn "No se encontraron memorias previas en Google Drive. Empezando desde cero."
fi

# ─── 7. Configurar cron ───────────────────────────────────────────────────────
info "Configurando cron (sync cada hora)..."
if ! crontab -l 2>/dev/null | grep -q "engram-sync"; then
  (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
  success "Cron configurado: sync cada hora en punto"
else
  success "Cron ya estaba configurado"
fi

# ─── 8. Backup de config de rclone en Google Drive ───────────────────────────
info "Guardando config de rclone en Google Drive (para futuras PCs)..."
rclone copy "$RCLONE_CONFIG" "gdrive:TRABAJO/engram-sync/_config/" --log-level ERROR 2>/dev/null || true
success "Config de rclone respaldada"

# ─── 9. Primer sync ───────────────────────────────────────────────────────────
info "Ejecutando primer sync..."
"$HOME/.local/bin/engram-sync.sh"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║          Setup completado ✓          ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "  Sync automático: cada hora"
echo "  Sync manual:     engram-sync.sh"
echo "  Logs:            ~/.engram/sync.log"
echo "  Google Drive:    $GDRIVE_REMOTE"
echo ""
