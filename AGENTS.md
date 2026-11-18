# Instrucciones para agentes de IA (Claude Code, Codex, Cursor…)

Si un usuario te pasó la liga de este repo y te pidió **«instálalo»**, **«instala este proyecto»** o algo parecido, sigue esto.

> Claude HQ es un proyecto independiente de código abierto (MIT), no afiliado ni respaldado por Anthropic.

## Lo importante

Claude HQ es una **app de macOS independiente**, no una dependencia ni una librería para el proyecto del usuario.

- **No clones este repo dentro del proyecto en el que estás trabajando.** Tampoco lo agregues como submódulo, paquete ni dependencia.
- **No compiles nada en el directorio actual.** La compilación genera `ClaudeHQ.xcodeproj` y `build/`, y esos archivos ensuciarían el git del usuario.
- **No crees ni modifiques archivos en el proyecto del usuario**, incluida su `.claude/settings.json`. Claude HQ usa solo la configuración global `~/.claude/settings.json`.

## Cómo instalarlo

1. Ejecuta el instalador. Clona y compila en `~/.claude-hq/src`, fuera del proyecto, sin importar el directorio actual:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/JonaRivera-RB/claude-hq/main/scripts/install.sh | bash
   ```

   Requiere macOS 14+, Xcode 15+ y XcodeGen (`brew install xcodegen`). Si falta algo, el script lo dice; avísale al usuario en lugar de improvisar otra instalación.

2. **Confirma con el usuario antes de este paso.** Explícale que modifica su configuración global `~/.claude/settings.json`: agrega hooks silenciosos y envuelve su status line (la actual se conserva). Antes guarda un respaldo en `~/.claude-hq/` y, si el archivo no es JSON válido, no lo toca. Con su OK:

   ```bash
   ~/Applications/ClaudeHQ.app/Contents/MacOS/ClaudeHQ install
   ```

   El usuario también puede hacerlo desde la app con el botón **CONECTAR**.

3. Verifica que el proyecto del usuario quedó intacto: `git status` debe verse igual que antes de instalar.

4. Dile al usuario que las sesiones ya abiertas empiezan a reportar desde su siguiente acción. La primera vez que use **IR A TERMINAL**, macOS le pedirá permiso para controlar Terminal.

## Dónde vive cada cosa

| Qué | Ruta |
|---|---|
| Código fuente | `~/.claude-hq/src` |
| App instalada | `~/Applications/ClaudeHQ.app` |
| Estado, límites, log y respaldos | `~/.claude-hq/` |
| Hooks y status line | `~/.claude/settings.json` (global) |

## Desinstalar

El orden importa: primero `uninstall`, después borrar. Si se borra la app sin desconectar, la status line del usuario queda apuntando a un programa que ya no existe.

```bash
~/Applications/ClaudeHQ.app/Contents/MacOS/ClaudeHQ uninstall   # quita hooks y restaura la status line
rm -rf ~/Applications/ClaudeHQ.app ~/.claude-hq
```
