# Empaquetado (NotarIA.app)

## Generar el .app
```bash
scripts/package-app.sh
```
Hace build release con el mismo toolchain de `scripts/build.sh` (Xcode, no CLT) y arma `dist/NotarIA.app`:
- `Contents/MacOS/aria-capture` — binario release.
- `Contents/Resources/AppIcon.icns` — desde `~/Projects/notaria-brand/out/AppIcon.icns`.
- `Contents/Resources/menubar-22.png`, `menubar-44.png`, `ggml-metal.metal` — copiados desde los `.bundle` que genera SwiftPM en `.build/release/` (ver más abajo por qué no se usan esos `.bundle` directamente).
- `Contents/Info.plist`.

Al final firma (con la identidad local estable si existe, o ad-hoc si no — ver "Firma" más abajo) y verifica (`codesign --verify --deep --strict`).

## Por qué los recursos no quedan como los puso SwiftPM
SwiftPM genera `Aria_aria-capture.bundle` (icono + glifos de barra de menú) y `whisper_whisper.bundle` (shader `ggml-metal.metal`) como carpetas sueltas junto al binario en `.build/release/`. El `resource_bundle_accessor.swift`/`.m` generado los busca en tiempo de ejecución con `Bundle.main.bundleURL.appendingPathComponent("<bundle>")`, que para un `.app` es la **raíz** del bundle (al lado de `Contents`), no `Contents/Resources`.

Eso choca con code signing: `codesign` rechaza de plano cualquier cosa en la raíz de un `.app` que no sea `Contents/` —

```
dist/NotarIA.app: unsealed contents present in the bundle root
```

(falla con exit 1, probado con y sin `--deep`). No se puede tocar el accessor generado (es código de SwiftPM, se regenera en cada build), así que en vez de pelear con eso:
- `BrandAssets.swift` (`Sources/aria-capture/BrandAssets.swift`) primero busca `menubar-22/44.png` y `AppIcon.icns` en `Bundle.main.resourceURL` (es decir, `Contents/Resources`) cuando corre empaquetado (`LoginItemManager.isRunningFromAppBundle`), y solo usa `Bundle.module` (el camino de siempre) cuando corre como binario suelto de desarrollo. Así nunca se toca `Bundle.module` dentro del `.app` — evita el `fatalError` que dispara ese accessor si no encuentra el bundle, que habría tumbado toda la app (se dispara en cuanto se pinta el ícono de la barra de menú).
- `main.swift` setea `GGML_METAL_PATH_RESOURCES` (variable que `ggml-metal.m` ya soporta de fábrica, sin tocar `Vendor/`) a `Bundle.main.resourceURL` cuando existe, así whisper.cpp encuentra `ggml-metal.metal` en `Contents/Resources` en vez de buscar su propio bundle. Es un no-op fuera del `.app` (ahí `Bundle.main.resourceURL` es `nil`).

Ningún cambio toca `Package.swift`, `Vendor/whisper.cpp/` ni el accessor generado.

## Identificador de bundle
`com.criguex.notaria` — **no cambiar** en builds futuros. TCC (permisos de Micrófono, Grabación de pantalla, Calendario, Automatización) y el registro de login item (`SMAppService`) quedan atados a este identificador; cambiarlo obliga al usuario a re-otorgar todos los permisos.

## Arranque sin argumentos
`aria-capture` sin argumentos (como lo lanza Launch Services desde el .app) entra directo en modo `menubar`. `aria-capture --version` imprime versión y build (leídos de `Info.plist`) y sale sin levantar UI — útil para scripts/smoke tests.

## Firma

### Identidad de firma local estable (recomendado)
```bash
scripts/setup-signing-identity.sh
```
Crea, si no existe, un certificado de firma de código **autofirmado** llamado `NotarIA Local Signing` en el llavero de login (`~/Library/Keychains/login.keychain-db`) y lo importa autorizando a `/usr/bin/codesign` a usarlo sin preguntar cada vez (`security import ... -T /usr/bin/codesign`). Es idempotente: si la identidad ya existe, no hace nada y sale con `0`.

`scripts/package-app.sh` detecta esa identidad con `security find-identity -p codesigning` y, si existe, firma con ella en vez de ad-hoc. **Por qué importa**: la firma ad-hoc (`-s -`) deriva el Designated Requirement (DR) del `cdhash` (hash del binario), que cambia en **cada build**; TCC usa el DR para identificar la app y conservar los permisos de Calendario/Micrófono/Grabación de pantalla, así que un DR que cambia hace que cada reinstalación se trate como una app nueva y pierda todos los permisos otorgados. Firmar con un certificado (aunque sea autofirmado) ancla el DR al **certificado + `CFBundleIdentifier`**, no al contenido del binario, así que permanece estable entre builds mientras no cambie el bundle id (`com.criguex.notaria`, no tocar).

Verificado en este repo firmando dos builds reales consecutivos (`scripts/package-app.sh` dos veces, con una recompilación real de por medio) y comparando `codesign -d -r- dist/NotarIA.app`:
- Con `NotarIA Local Signing`: `designated => identifier "com.criguex.notaria" and certificate leaf = H"<hash del certificado>"` — **idéntico** en ambos builds.
- Con ad-hoc (`-s -`): `designated => cdhash H"<hash del binario>"` — **distinto** en cada build (esto es la causa raíz del bug "Hoy no ve el calendario pero `aria-capture calendar` sí").

No requiere marcar el certificado como "Siempre confiar" en Keychain Access: `codesign`, `codesign --verify --deep --strict` y la firma real del `.app` funcionan igual sin ese paso (probado). Por eso `setup-signing-identity.sh` no lo hace — evita abrir una vía de bloqueo interactivo que no hace falta.

Si `security import` o la firma de verificación no terminan en segundos razonables (macOS pidiendo la contraseña del llavero de login o una confirmación de confianza que el script no puede responder), `setup-signing-identity.sh` no se queda colgado: corta por timeout, imprime el comando exacto a correr manualmente en Terminal, y sale con código `1`.

### Firma ad-hoc (fallback)
Si no existe la identidad `NotarIA Local Signing`, `scripts/package-app.sh` cae a `codesign --force --deep -s - --entitlements scripts/entitlements.plist dist/NotarIA.app` con un aviso en stderr. Sirve para compilar/probar, pero cada reinstalación pierde los permisos TCC (ver arriba) — para uso diario conviene correr `scripts/setup-signing-identity.sh` una vez.

`scripts/entitlements.plist` está vacío a propósito: NotarIA corre **sin App Sandbox**, así que no necesita entitlements de sandbox (`com.apple.security.device.*`, `com.apple.security.automation.apple-events`, etc.) — los permisos de Micrófono/Pantalla/Calendario/Automatización los arbitra TCC directamente contra las *usage descriptions* del `Info.plist` y las llamadas a las APIs correspondientes (`AVCaptureDevice`, `CGRequestScreenCaptureAccess`, `EventKit`, `osascript`). Si en el futuro se adopta App Sandbox, ahí sí haría falta declarar esos entitlements y revalidar que ScreenCaptureKit/AppleEvents siguen funcionando dentro del sandbox.

**Ninguna de las dos firmas (identidad local o ad-hoc) sirve para distribución pública** (otros Macs, Gatekeeper sin aviso). Para eso haría falta:
1. Developer ID Application (cuenta de pago de Apple Developer).
2. `codesign` con ese certificado + hardened runtime.
3. `xcrun notarytool submit` y pegar el ticket (`stapler`).

Nada de esto está hecho ni se automatizó aquí.

## Permisos declarados (Info.plist)
| Clave | Para qué |
|---|---|
| `NSMicrophoneUsageDescription` | Grabar tu voz (mic), transcripción local |
| `NSScreenCaptureUsageDescription` | Audio del sistema (ScreenCaptureKit) y, si activas el contexto visual opcional, contenido de pantalla |
| `NSCalendarsUsageDescription` / `NSCalendarsFullAccessUsageDescription` | Leer el calendario para detectar/titular reuniones |
| `NSAppleEventsUsageDescription` | Leer pestañas del navegador (vía `osascript`) para detectar videollamadas |
| `LSUIElement = true` | App de barra de menú, sin ícono en el Dock salvo cuando abre su ventana principal (ya manejado en código: `NSApp.setActivationPolicy(.regular/.accessory)` en `MainWindowBridge`/`MainWindowView`) |

## Abrir al iniciar sesión
Ajustes → sección "Inicio" → toggle respaldado por `SMAppService.mainApp` (`Sources/aria-capture/LoginItemManager.swift`). Solo funciona ejecutando desde el `.app` instalado (requiere `CFBundleIdentifier` estable); desde el binario suelto de desarrollo el toggle se reemplaza por un aviso.

## Instalar en /Applications
```bash
scripts/install-local.sh
```
Copia `dist/NotarIA.app` a `/Applications`, respaldando una instalación previa a la Papelera (`osascript`/Finder, no `rm`). No se ejecuta como parte del empaquetado — lo corre quien instala.

## Smoke test sin abrir la UI real
```bash
open dist/NotarIA.app --args --version
```
Sale por el caso `--version` de `main.swift` antes de tocar AppKit/menubar, así que no hay ventana ni ícono que cerrar (verificado: `open` retorna, no queda proceso en `pgrep`, sin crash report). Si por lo que sea quedara un proceso vivo en `dist/NotarIA.app/Contents/MacOS/aria-capture`, se mata por ruta exacta (nunca el `aria-capture menubar` que corre desde `.build/` en el repo principal).
