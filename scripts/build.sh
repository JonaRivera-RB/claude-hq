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

mkdir -p build
echo "→ Compilando…"
BUILD_ARGS=(-project ClaudeHQ.xcodeproj -scheme ClaudeHQ -configuration Release
  -derivedDataPath build/dd -destination "platform=macOS,arch=$(uname -m)")
if ! xcodebuild "${BUILD_ARGS[@]}" -allowProvisioningUpdates build -quiet > build/xcodebuild.log 2>&1; then
  # Sin acceso al equipo de desarrollo de project.yml (otra Mac u otra cuenta de Apple):
  # firma local ad-hoc. La app funciona igual; solo el widget nativo de WidgetKit no carga.
  echo "  (sin el equipo de firma del proyecto: compilando con firma local)"
  xcodebuild "${BUILD_ARGS[@]}" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    PROVISIONING_PROFILE_SPECIFIER= CODE_SIGN_ENTITLEMENTS= build -quiet > build/xcodebuild.log 2>&1 \
    || { tail -30 build/xcodebuild.log; echo "✗ Falló la compilación. Log completo: $PWD/build/xcodebuild.log" >&2; exit 1; }
fi

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
