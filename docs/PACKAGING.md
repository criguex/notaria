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

Al final firma ad-hoc y verifica (`codesign --verify --deep --strict`).

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
Firma ad-hoc: `codesign --force --deep -s - --entitlements scripts/entitlements.plist dist/NotarIA.app`.
`scripts/entitlements.plist` está vacío a propósito: NotarIA corre **sin App Sandbox**, así que no necesita entitlements de sandbox (`com.apple.security.device.*`, `com.apple.security.automation.apple-events`, etc.) — los permisos de Micrófono/Pantalla/Calendario/Automatización los arbitra TCC directamente contra las *usage descriptions* del `Info.plist` y las llamadas a las APIs correspondientes (`AVCaptureDevice`, `CGRequestScreenCaptureAccess`, `EventKit`, `osascript`). Si en el futuro se adopta App Sandbox, ahí sí haría falta declarar esos entitlements y revalidar que ScreenCaptureKit/AppleEvents siguen funcionando dentro del sandbox.

**Firma ad-hoc = solo para este Mac.** Para distribución pública (otros Macs, Gatekeeper sin aviso) haría falta:
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
