#!/bin/bash
# Compila e instala "Prumo.app" (SwiftUI via SwiftPM, sem Xcode).
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP="dist/Prumo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Assistente "$APP/Contents/MacOS/Assistente"
cp Info.plist "$APP/Contents/Info.plist"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Pronto: $APP"
if [ "${1:-}" = "--instalar" ]; then
    osascript -e 'tell application id "io.github.ckpsantos.prumo" to quit' 2>/dev/null || true
    rm -rf "/Applications/Prumo.app"
    ditto "$APP" "/Applications/Prumo.app"
    echo "Instalado em /Applications/Prumo.app"
fi
