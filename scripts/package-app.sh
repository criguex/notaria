#!/bin/bash
# Empaqueta NotarIA como dist/NotarIA.app (firma ad-hoc, sin notarizar).
# CFBundleIdentifier es ESTABLE (com.criguex.notaria): no cambiarlo entre builds,
# TCC (mic/pantalla/calendario/automatización) y el login item quedan atados a él.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

APP_NAME="NotarIA"
BUNDLE_ID="com.criguex.notaria"
VERSION="0.9.0"
BUILD_NUMBER="1"
EXECUTABLE="aria-capture"
ICON_SRC="$HOME/Projects/notaria-brand/out/AppIcon.icns"
SIGNING_IDENTITY_NAME="NotarIA Local Signing"

echo "[package] Build release (toolchain de scripts/build.sh)..."
./scripts/build.sh -c release

BIN_DIR=".build/release"
if [ ! -x "$BIN_DIR/$EXECUTABLE" ]; then
    echo "[error] No se encontró $BIN_DIR/$EXECUTABLE tras el build." >&2
    exit 1
fi

DIST_DIR="dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

echo "[package] Armando $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_DIR/$EXECUTABLE" "$CONTENTS/MacOS/$EXECUTABLE"

if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$CONTENTS/Resources/AppIcon.icns"
else
    echo "[aviso] No se encontró el icono en $ICON_SRC; el .app quedará sin AppIcon.icns." >&2
fi

# codesign exige que la raíz de un .app solo tenga Contents/ (rechaza cualquier otra
# cosa junto a Contents, incluidos los *.bundle sueltos que genera SwiftPM). El
# accessor generado (resource_bundle_accessor.swift/.m) busca esos bundles junto a
# Bundle.main.bundleURL y no se toca (es código generado); en vez de pelear con eso,
# se copian los recursos reales a Contents/Resources y el propio código (BrandAssets,
# GGML_METAL_PATH_RESOURCES seteado en main.swift) los busca ahí cuando corre
# empaquetado. Ver docs/PACKAGING.md.
ARIA_BUNDLE="$BIN_DIR/Aria_aria-capture.bundle/Resources"
WHISPER_BUNDLE="$BIN_DIR/whisper_whisper.bundle"
for res in menubar-22.png menubar-44.png; do
    if [ -f "$ARIA_BUNDLE/$res" ]; then
        cp "$ARIA_BUNDLE/$res" "$CONTENTS/Resources/$res"
    else
        echo "[aviso] No se encontró $ARIA_BUNDLE/$res" >&2
    fi
done
if [ -f "$WHISPER_BUNDLE/ggml-metal.metal" ]; then
    cp "$WHISPER_BUNDLE/ggml-metal.metal" "$CONTENTS/Resources/ggml-metal.metal"
else
    echo "[aviso] No se encontró $WHISPER_BUNDLE/ggml-metal.metal" >&2
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>NotarIA usa el micrófono para grabar tu voz durante las reuniones y transcribirla localmente en tu Mac (whisper.cpp); el audio no sale de tu equipo salvo que tú actives el enhance con Claude, que solo envía el texto transcrito.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>NotarIA usa este permiso para capturar el audio del sistema durante tus reuniones (la voz de los demás participantes, vía ScreenCaptureKit). Si activas el contexto visual opcional en Ajustes, también se usa para leer contenido de la pantalla; nunca se graba ni sube video, y sin tu acción explícita no se usa para capturar pantalla.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>NotarIA lee tu calendario para detectar reuniones en curso o próximas, asociar título y participantes a cada nota, y avisarte cuando vas a empezar una.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>NotarIA lee tu calendario para detectar reuniones en curso o próximas, asociar título y participantes a cada nota, y avisarte cuando vas a empezar una.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>NotarIA usa eventos de Apple para leer las pestañas abiertas en tu navegador y detectar si estás en una videollamada (Zoom, Meet, Teams), sin acceder a su contenido.</string>
</dict>
</plist>
PLIST

# Firma ad-hoc (-s -) deriva el Designated Requirement del hash del binario,
# que cambia en cada build y hace que TCC (Calendario/Micrófono/Pantalla)
# trate cada reinstalación como una app nueva, perdiendo los permisos. Si
# existe la identidad local estable (scripts/setup-signing-identity.sh), se
# usa esa en su lugar: su DR queda anclado al certificado, no al binario.
if security find-identity -p codesigning 2>/dev/null | grep -qF "\"$SIGNING_IDENTITY_NAME\""; then
    SIGN_IDENTITY="$SIGNING_IDENTITY_NAME"
    echo "[package] Firmando con identidad local estable \"$SIGN_IDENTITY\" (codesign --force --deep -s \"$SIGN_IDENTITY\")..."
else
    SIGN_IDENTITY="-"
    echo "[aviso] No existe la identidad \"$SIGNING_IDENTITY_NAME\" (corre scripts/setup-signing-identity.sh)." >&2
    echo "[aviso] Firmando ad-hoc (codesign --force --deep -s -): el DR cambiará en cada build y TCC" >&2
    echo "        volverá a pedir Calendario/Micrófono/Grabación de pantalla tras cada reinstalación." >&2
fi
codesign --force --deep -s "$SIGN_IDENTITY" --entitlements scripts/entitlements.plist "$APP_DIR"

echo "[package] Verificando firma..."
codesign --verify --deep --strict "$APP_DIR"
codesign -dv "$APP_DIR" 2>&1 | sed 's/^/[codesign] /'
codesign -d -r- "$APP_DIR" 2>&1 | sed 's/^/[codesign] /'

echo "[ok] Listo: $APP_DIR"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "      Firma ad-hoc, solo para uso local en este Mac (DR inestable entre builds)."
else
    echo "      Firma con \"$SIGN_IDENTITY\", solo para uso local en este Mac (DR estable entre builds)."
fi
echo "      Para distribución pública haría falta Developer ID + notarización (no incluido aquí)."
