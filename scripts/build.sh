#!/bin/bash
# Compila Claude HQ (app + widget) y la instala en ~/Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

FONT=web/fonts/PixelifySans.ttf
if [ ! -s "$FONT" ]; then
  mkdir -p web/fonts
  echo "→ Descargando fuente Pixelify Sans (OFL)…"
  curl -fsSL -o "$FONT" "https://github.com/google/fonts/raw/main/ofl/pixelifysans/PixelifySans%5Bwght%5D.ttf" || echo "  (sin fuente: se usará monoespaciada)"
fi

echo "→ Generando proyecto Xcode…"
xcodegen generate --quiet

echo "→ Compilando…"
xcodebuild -project ClaudeHQ.xcodeproj -scheme ClaudeHQ -configuration Release \
  -derivedDataPath build/dd -destination 'platform=macOS,arch=arm64' -allowProvisioningUpdates build -quiet

APP=build/dd/Build/Products/Release/ClaudeHQ.app
DEST="$HOME/Applications/ClaudeHQ.app"
mkdir -p "$HOME/Applications"

echo "→ Instalando en ${DEST}…"
# Reemplazo casi atómico: los hooks de Claude Code usan esta ruta y no deben encontrarla vacía.
rm -rf "$DEST.new" "$DEST.old"
cp -R "$APP" "$DEST.new"
pkill -x ClaudeHQ 2>/dev/null || true
[ -d "$DEST" ] && mv "$DEST" "$DEST.old"
mv "$DEST.new" "$DEST"
rm -rf "$DEST.old"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" >/dev/null 2>&1 || true
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# Solo debe quedar registrada la copia instalada (la de build/ se reemplaza en cada compilación).
pluginkit -r "$PWD/$APP/Contents/PlugIns/ClaudeHQWidget.appex" 2>/dev/null || true
$LSREG -u "$PWD/$APP" >/dev/null 2>&1 || true
pluginkit -a "$DEST/Contents/PlugIns/ClaudeHQWidget.appex" 2>/dev/null || true
pluginkit -e use -i com.jonarivera.ClaudeHQ.Widget 2>/dev/null || true
# Borramos la copia de compilación para que macOS solo conozca una app con este identificador.
rm -rf "$APP"

if [ "${1:-}" != "--no-open" ]; then
  open "$DEST"
fi
echo "✓ Listo: ${DEST}"
