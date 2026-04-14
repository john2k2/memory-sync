# memory-sync

Memoria persistente de IA sincronizada entre máquinas (Linux, Windows, macOS).

Un solo comando en una PC nueva y tenés toda tu memoria restaurada — compatible con Claude Code, OpenCode y Qwen Code.

## PC nueva — setup completo

**Linux / macOS:**
```bash
git clone https://github.com/john2k2/memory-sync.git
cd memory-sync
bash setup.sh
```

**Windows (PowerShell):**
```powershell
git clone https://github.com/john2k2/memory-sync.git
cd memory-sync
.\setup.ps1
```

El script hace todo solo:
1. Verifica e instala `engram` si no está (via Go, Homebrew o binario)
2. Verifica acceso a GitHub y crea el repo privado si hace falta
3. Inicializa `~/.engram` como repo git
4. Sincroniza la memoria existente
5. Instala los scripts de sync (`engram-pull` / `engram-push`)
6. Configura Claude Code, OpenCode y Qwen Code automáticamente

## Uso diario

```bash
# Al empezar a trabajar:
engram-pull.sh        # Linux/macOS
engram-pull.ps1       # Windows

# Al terminar:
engram-push.sh        # Linux/macOS
engram-push.ps1       # Windows
```

## Flujo entre máquinas

```
Linux   →  engram-pull.sh   →  trabajás  →  engram-push.sh
Windows →  engram-pull.ps1  →  trabajás  →  engram-push.ps1
           (Claude / OpenCode / Qwen — todos leen la misma memoria)
```

## Herramientas compatibles

| Herramienta | Soporte |
|---|---|
| Claude Code | Nativo (`engram setup claude-code`) |
| OpenCode | Nativo (`engram setup opencode`) |
| Qwen Code | MCP stdio (`qwen mcp add`) |
| Cursor / Windsurf / VS Code | Manual vía `.mcp.json` |

## Requisitos

- Git
- Una de estas opciones para instalar Engram: Go 1.24+, Homebrew (macOS/Linux), o descarga del binario
- GitHub CLI (`gh`) recomendado para crear el repo automáticamente

## Estructura del repo de memoria

```
~/.engram/                  (o %USERPROFILE%\.engram en Windows)
├── .gitignore              → excluye engram.db (DB local, no se sube)
├── manifest.json           → índice de chunks
└── chunks/
    ├── a3f8c1d2.jsonl.gz   → chunk de memoria comprimido
    └── ...
```

Los chunks son append-only — nunca hay merge conflicts.
La DB local (`engram.db`) se regenera desde los chunks en cada máquina.
