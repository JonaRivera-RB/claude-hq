#!/bin/bash
# Instalador de Claude HQ en un solo comando.
# Clona (o actualiza) el código en ~/.claude-hq/src y lo compila ahí,
# sin importar desde qué carpeta se ejecute. No toca el directorio actual.
#
#   curl -fsSL https://raw.githubusercontent.com/JonaRivera-RB/claude-hq/main/scripts/install.sh | bash
set -euo pipefail

REPO="https://github.com/JonaRivera-RB/claude-hq.git"
SRC="${CLAUDE_HQ_SRC:-$HOME/.claude-hq/src}"

fail() { echo "✗ $*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Claude HQ solo funciona en macOS."
command -v git >/dev/null        || fail "Falta git. Instala las Command Line Tools: xcode-select --install"
command -v xcodebuild >/dev/null || fail "Falta Xcode 15 o superior (App Store)."
xcodebuild -version >/dev/null 2>&1 || fail "xcodebuild no funciona. Abre Xcode una vez o corre: sudo xcode-select -s /Applications/Xcode.app"
command -v xcodegen >/dev/null   || fail "Falta XcodeGen: brew install xcodegen"
command -v claude >/dev/null     || echo "⚠ No encontré 'claude' en el PATH. Claude HQ necesita Claude Code instalado y con sesión iniciada."

mkdir -p "$(dirname "$SRC")"
if [ -d "$SRC/.git" ]; then
  echo "→ Actualizando código en $SRC…"
  # Esta carpeta es del instalador: se alinea con main aunque la compilación haya generado archivos.
  git -C "$SRC" fetch --depth 1 --quiet origin main
  git -C "$SRC" reset --hard --quiet FETCH_HEAD
else
  if [ -e "$SRC" ]; then
    BAK="$SRC.bak-$(date +%Y%m%d-%H%M%S)"
    echo "→ $SRC existe pero no es un repo de git; lo muevo a $BAK"
    mv "$SRC" "$BAK"
  fi
  echo "→ Descargando código en $SRC…"
  git clone --depth 1 --quiet "$REPO" "$SRC"
fi

"$SRC/scripts/build.sh" "$@"

echo
echo "Siguiente paso: en la app toca CONECTAR, o desde la terminal:"
echo "  ~/Applications/ClaudeHQ.app/Contents/MacOS/ClaudeHQ install"
