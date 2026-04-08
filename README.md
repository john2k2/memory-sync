# memory-sync

Setup automático de Engram + rclone + Google Drive.

Una sola línea en una PC nueva y tenés toda tu memoria de IA restaurada.

## PC nueva — setup completo

```bash
git clone https://github.com/john2k2/memory-sync.git
cd memory-sync
bash setup.sh
```

El script:
1. Instala `rclone` y `engram` si no están
2. Configura Google Drive (abre el browser para autorizar)
3. Restaura todas las memorias previas desde Google Drive
4. Instala el cron de sync automático (cada hora)
5. Respalda la config de rclone en Drive para la próxima vez

## Uso diario

No necesitás hacer nada. El sync es automático cada hora.

**Sync manual:**
```bash
engram-sync.sh
```

**Ver logs:**
```bash
tail -f ~/.engram/sync.log
```

**Ver memorias guardadas:**
```bash
engram context
engram search "lo que buscás"
```

## Estructura en Google Drive

```
TRABAJO/
  engram-sync/
    reservaloYa/       → memorias del proyecto ReservaYa
    programacion/      → memorias generales
    _config/           → backup de rclone.conf
```

## Restaurar en una PC sin internet previo

Si perdiste acceso a Google Drive temporalmente y tenés un backup manual:

```bash
# Importar desde archivo local
engram sync --import /ruta/al/chunk.jsonl.gz
```
