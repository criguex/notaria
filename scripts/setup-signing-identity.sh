#!/bin/bash
# Crea (si no existe) una identidad de firma de código local y ESTABLE,
# "NotarIA Local Signing", en el llavero de login.
#
# Por qué: la firma ad-hoc (`codesign -s -`) deriva el Designated Requirement
# (DR) del hash del propio binario, que cambia en cada build. macOS (TCC)
# usa ese DR para identificar la app y conservar los permisos otorgados
# (Calendario, Micrófono, Grabación de pantalla); si cambia en cada
# reinstalación, TCC trata la app como nueva y los pierde todos.
# Firmar con un certificado (aunque sea autofirmado) ancla el DR al
# certificado — no al contenido del binario — así que permanece estable
# entre builds mientras el CFBundleIdentifier no cambie. No requiere
# marcar el certificado como "Siempre confiar": codesign, --verify y TCC
# funcionan igual sin ese paso (verificado); por eso este script NO lo hace,
# para no abrir una vía de bloqueo interactivo innecesaria.
#
# Uso: scripts/setup-signing-identity.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

IDENTITY_NAME="NotarIA Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
IMPORT_TIMEOUT_SECS=20
# La primera firma con una identidad recién importada puede tardar varios
# segundos (trustd evalúa el certificado, con reintentos de red de por
# medio); no es un cuelgue, solo lento la primera vez. 45s cubre ese caso
# sin dejar la terminal colgada indefinidamente si de verdad hay un diálogo
# de confianza pendiente de responder.
SELFTEST_TIMEOUT_SECS=45

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

run_with_timeout() {
    local secs="$1"
    shift
    "$@" &
    local pid=$!
    (
        sleep "$secs" 2>/dev/null
        kill -9 "$pid" 2>/dev/null
    ) &
    local watchdog=$!
    local status=0
    wait "$pid" 2>/dev/null || status=$?
    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null
    return "$status"
}

fail_with_instructions() {
    local reason="$1"
    local command="$2"
    echo "" >&2
    echo "[setup-signing-identity] $reason" >&2
    echo "[setup-signing-identity] No se insiste en automatizarlo: corre esto en tu Terminal" >&2
    echo "[setup-signing-identity] (puede pedir tu contraseña de llavero o confirmar acceso)" >&2
    echo "[setup-signing-identity] y vuelve a correr scripts/setup-signing-identity.sh:" >&2
    echo "" >&2
    echo "  $command" >&2
    echo "" >&2
    exit 1
}

if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -qF "\"$IDENTITY_NAME\""; then
    echo "[setup-signing-identity] Ya existe \"$IDENTITY_NAME\" en $KEYCHAIN:"
    security find-identity -p codesigning "$KEYCHAIN" | grep -F "$IDENTITY_NAME"
    exit 0
fi

echo "[setup-signing-identity] No existe todavía. Generando certificado autofirmado de firma de código..."

cat > "$WORKDIR/req.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = codesign_ext
prompt = no

[dn]
CN = ${IDENTITY_NAME}

[codesign_ext]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

if ! openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORKDIR/key.pem" -out "$WORKDIR/cert.pem" \
    -config "$WORKDIR/req.cnf" -extensions codesign_ext \
    >"$WORKDIR/openssl-req.log" 2>&1; then
    cat "$WORKDIR/openssl-req.log" >&2
    echo "[error] openssl no pudo generar la clave/certificado." >&2
    exit 1
fi

P12_PASS="$(openssl rand -base64 24)"
# -legacy: la codificación PKCS12 por defecto de OpenSSL 3.x no la entiende
# `security import` de macOS ("MAC verification failed", probado en este Mac).
if ! openssl pkcs12 -export -legacy \
    -inkey "$WORKDIR/key.pem" -in "$WORKDIR/cert.pem" \
    -out "$WORKDIR/identity.p12" -passout "pass:${P12_PASS}" \
    >"$WORKDIR/openssl-p12.log" 2>&1; then
    cat "$WORKDIR/openssl-p12.log" >&2
    echo "[error] openssl no pudo empaquetar el PKCS#12." >&2
    exit 1
fi

echo "[setup-signing-identity] Importando a $KEYCHAIN (autoriza a codesign a usar la clave sin preguntar cada vez)..."
IMPORT_CMD=(security import "$WORKDIR/identity.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign)
if ! run_with_timeout "$IMPORT_TIMEOUT_SECS" "${IMPORT_CMD[@]}" >"$WORKDIR/import.log" 2>&1; then
    cat "$WORKDIR/import.log" >&2
    fail_with_instructions \
        "\"security import\" no terminó en ${IMPORT_TIMEOUT_SECS}s (probablemente macOS está esperando que confirmes la contraseña del llavero de login, o que autorices el acceso, en un diálogo que no se puede responder desde este script)." \
        "security unlock-keychain \"$KEYCHAIN\"   # desbloquea el llavero de login con tu contraseña, luego: scripts/setup-signing-identity.sh"
fi
cat "$WORKDIR/import.log"

if ! security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -qF "\"$IDENTITY_NAME\""; then
    fail_with_instructions \
        "La importación terminó pero \"$IDENTITY_NAME\" no aparece en security find-identity -p codesigning." \
        "security find-identity -v -p codesigning \"$KEYCHAIN\""
fi

echo "[setup-signing-identity] Verificando que codesign puede firmar sin interacción..."
cp /bin/echo "$WORKDIR/selftest-bin"
SIGN_CMD=(codesign -s "$IDENTITY_NAME" -i com.criguex.notaria.signing-selftest --force "$WORKDIR/selftest-bin")
if ! run_with_timeout "$SELFTEST_TIMEOUT_SECS" "${SIGN_CMD[@]}" >"$WORKDIR/codesign.log" 2>&1; then
    cat "$WORKDIR/codesign.log" >&2
    fail_with_instructions \
        "codesign no pudo firmar con la identidad nueva en ${SELFTEST_TIMEOUT_SECS}s (probablemente un diálogo de confianza pendiente de responder)." \
        "codesign -s \"$IDENTITY_NAME\" --force /ruta/a/un/binario/de/prueba   # acepta el diálogo si aparece"
fi

echo "[ok] Identidad \"$IDENTITY_NAME\" creada e importada en $KEYCHAIN."
security find-identity -p codesigning "$KEYCHAIN" | grep -F "$IDENTITY_NAME"
echo "[ok] scripts/package-app.sh la usará automáticamente a partir de ahora."
