#!/bin/bash
# engram-sync.sh
# Exporta memorias de Engram a Google Drive.
# Se instala en ~/.local/bin/ y se ejecuta via cron cada hora.
set -e

GDRIVE_REMOTE="gdrive:TRABAJO/engram-sync"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

# Verificar dependencias
if ! command -v engram &>/dev/null; then
  log "ERROR: engram no está instalado"
  exit 1
fi
if ! command -v rclone &>/dev/null; then
  log "ERROR: rclone no está instalado"
  exit 1
fi

log "Iniciando sync..."

# Exportar chunks nuevos desde todos los proyectos
engram sync --all 2>/dev/null

# Subir todos los chunks encontrados en el sistema
UPLOADED=0
find "$HOME" -path "*/.engram/chunks/*.jsonl.gz" 2>/dev/null | while read chunk; do
  project_dir=$(dirname "$(dirname "$chunk")")
  project_name=$(basename "$project_dir")
  rclone copy "$chunk" "$GDRIVE_REMOTE/$project_name/" --log-level ERROR 2>/dev/null
  UPLOADED=$((UPLOADED + 1))
done

# Subir también el manifest de cada proyecto
find "$HOME" -path "*/.engram/manifest.json" 2>/dev/null | while read manifest; do
  project_dir=$(dirname "$manifest")
  project_name=$(basename "$(dirname "$project_dir")")
  rclone copy "$manifest" "$GDRIVE_REMOTE/$project_name/" --log-level ERROR 2>/dev/null
done

log "Sync completado"
