# Claude HQ

Oficina pixel flotante para ver tus límites de Claude y lo que hace cada sesión de Claude Code.

## Qué incluye

| Formato | Dónde |
|---|---|
| Ventana flotante (compacta / expandida) | Se abre al iniciar la app; clic en el ícono de la barra de menú para mostrar u ocultar |
| Barra de menú | `5h 42%` y `· N!` cuando hay agentes esperando permiso; clic derecho para el menú |
| Tarjeta de escritorio | Sobre el escritorio, detrás de tus ventanas. Clic para abrir la oficina; arrástrala para moverla. Tamaño: clic derecho en el ícono de la barra de menú → *Widget de escritorio* |
| Status line de Claude Code | Tu status line anterior + `5h 42% · sem 18%` al final |

## Funciones

- **Oficina pixel** con día y noche según tu hora real; los agentes llegan caminando y se despiden al cerrar su sesión.
- **Toca un agente** para ver qué hace ahora; **IR A TERMINAL** (o doble clic) te lleva a su pestaña exacta.
- **Historial** por agente, agrupado por hora, con inicio, tokens de hoy, contexto y subagentes.
- **Alertas** al 80% y 95% del límite, cuando un agente pide permiso o se detiene por error (con o sin sonido).
- **Login con Claude** (el mismo de Claude Code), modelo y permisos por defecto, Admin API opcional.

## De dónde salen los datos (nada gasta tokens)

- **Límites 5 h y semana**: dato oficial que Claude Code entrega a la status line (`rate_limits`). Se actualiza cada vez que una sesión responde.
- **Sesiones vivas**: `~/.claude/sessions/*.json`.
- **Qué hace cada agente y sus subagentes**: hooks silenciosos (no imprimen nada) → `~/.claude-hq/sessions/`.
- **Tokens de hoy**: transcripts locales en `~/.claude/projects` (entrada + salida + escritura de caché).
- **Cuenta y plan**: `claude auth status` (el mismo login de Claude Code). *Iniciar sesión* abre `claude auth login`.
- **API (opcional)**: Admin API key guardada en el Llavero → reportes de uso y costo de la organización.

## Comandos

```bash
./scripts/build.sh            # compila app + widget, instala en ~/Applications y la abre
~/Applications/ClaudeHQ.app/Contents/MacOS/ClaudeHQ install     # conectar con Claude Code (también desde la app)
~/Applications/ClaudeHQ.app/Contents/MacOS/ClaudeHQ uninstall   # desconectar y restaurar tu status line
~/Applications/ClaudeHQ.app/Contents/MacOS/ClaudeHQ dump        # ver el estado que lee la app (JSON)
~/Applications/ClaudeHQ.app/Contents/MacOS/ClaudeHQ snapshot out.png [compact|expanded]  # render de la interfaz
~/Applications/ClaudeHQ.app/Contents/MacOS/ClaudeHQ focus <sessionId>   # prueba "ir a la terminal" en la app abierta
```

El registro de la app está en `~/.claude-hq/app.log`.

## Widget nativo (WidgetKit)

El proyecto incluye una extensión de WidgetKit, pero macOS no la carga si la app está firmada con un equipo de desarrollador gratuito. Por eso la versión 1.0 usa su propia tarjeta de escritorio. Con una cuenta de desarrollador de pago, el widget nativo debería aparecer en *Editar widgets*.

Cada vez que conectas o desconectas se guarda un respaldo de `~/.claude/settings.json` en `~/.claude-hq/`.

## Ir a la terminal

La app recorre el árbol de procesos de cada sesión para saber en qué app corre:

- **Terminal / iTerm2**: va a la pestaña exacta (por TTY). La primera vez macOS pide permiso de Automatización.
- **VS Code / Cursor**: abre la ventana del proyecto.
- **Otras (Warp, Ghostty…)**: trae la app al frente.

## Estructura

- `App/`: app de macOS (barra de menú, panel flotante, colector, hooks, status line, instalador)
- `web/index.html`: interfaz pixel (la carga un WKWebView)
- `Widget/`: widget de WidgetKit (lee `~/.claude-hq/snapshot.json`)
- `Shared/`: modelos y rutas comunes
- `project.yml`: proyecto de XcodeGen (firma con tu equipo personal de Apple Development)
