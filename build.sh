#!/bin/bash
# Compila o Uso IA, monta o .app e instala em /Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Uso IA.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/UsoIA "$APP/Contents/MacOS/UsoIA"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x UsoIA 2>/dev/null || true
    rm -rf "/Applications/Uso IA.app"
    ditto "$APP" "/Applications/Uso IA.app"
    open "/Applications/Uso IA.app"
    echo "Instalado e aberto: /Applications/Uso IA.app"
else
    echo "Gerado: $APP  (use --install para instalar e abrir)"
fi
