# NotarIA

> Notas de reuniones local-first para macOS. **Nota** + **IA**, con un guiño
> a "notaría": da fe de lo que se dijo en la reunión, sin que la conversación
> salga de tu equipo.

![Banner de NotarIA](docs/assets/banner.png)

NotarIA escucha tus reuniones (audio del sistema + micrófono, sin unirse a la
llamada), las transcribe **en tu Mac** con [whisper.cpp](https://github.com/ggml-org/whisper.cpp),
y funde el transcript con tus propias notas usando Claude en una nota
Markdown que cae en tu vault de Obsidian. El audio nunca sale del Mac.

Read this in English: [README.md](./README.md)

## Por qué

La mayoría de apps de notas de reuniones con IA son cajas cerradas: tu audio
va a la nube de otro, y tus notas viven en el workspace propietario de otro.
NotarIA invierte las dos cosas: la transcripción corre localmente con
whisper.cpp, y lo único que sale de tu Mac —y solo si tú lo pides— es texto
que se envía a Claude para convertir un transcript crudo en una nota
estructurada. La nota en sí es un archivo `.md` plano en tu propio vault de
Obsidian, no una fila en la base de datos de otra empresa.

## Cómo funciona

1. **Captura** — ScreenCaptureKit (audio del sistema) + AVAudioEngine (mic),
   dos canales (mic = tú, sistema = los demás).
2. **Transcripción** — whisper.cpp con Metal, en tu Mac, por chunks con
   solapamiento y detección básica de actividad de voz.
3. **Enhance** (opcional) — Claude funde el transcript con tus notas rápidas
   en una nota Markdown estructurada. Solo viaja texto, nunca audio.
4. **Salida** — una nota `.md` con fecha cae en tu vault de Obsidian, con
   frontmatter (título, fecha, participantes, duración) y transcript
   colapsable.

![Píldora de grabación](docs/assets/pill-mock.png)

## Funcionalidades

- **Detección de reuniones** — Detecta reuniones por tu calendario local
  (EventKit) o micrófono en uso; muestra un aviso de un clic "¿grabo esta
  reunión?" al encontrar una llamada.
- **Grabación** — Captura audio del sistema + micrófono en canales separados,
  con indicador persistente `● REC` y píldora flotante que muestra transcript
  en vivo al pasar el mouse. Pausa, reanuda y detén desde la píldora o el menú.
- **Transcripción** — 100% en tu Mac con whisper.cpp y aceleración Metal; el
  audio nunca sale de tu equipo.
- **Tus propias notas** — Edita notas en la ventana principal mientras grabas;
  al hacer enhance, Claude funde tus notas con el transcript en una nota única
  y coherente.
- **Ventana principal** — UI navegable con cinco solapas:
  - *Hoy*: tu agenda del calendario para el día y un brief de la próxima
    reunión basado en encuentros previos con las mismas personas.
  - *Historial*: lista de todas tus reuniones grabadas, buscable por texto
    completo (FTS5) sobre cache local cifrado.
  - *Detalle*: cada reunión muestra tus notas, el transcript diarizado (con
    atribución de hablantes desde asistentes del calendario), y un link directo
    para editarla en Obsidian.
  - *Chat*: haz preguntas sobre tu propio historial de reuniones ("¿qué le
    prometí a Ana?") o aplica recipes/plantillas reutilizables (follow-up
    email, action items, resumen ejecutivo) a cualquier reunión.
  - *Ajustes*: configura tu modelo de IA, carpeta de Obsidian, importación/
    exportación, permisos y más.
- **Importación** — Trae tus notas de otras fuentes: markdown plano
  (`.md` / `.txt`), transcripts de videollamadas (`.vtt` / `.srt` de Zoom/Teams/Meet),
  o JSON estructurado. Cada importación es idempotente (mismo archivo →
  misma reunión, sin duplicados).
- **Exportación** — Copia notas con formato, guarda a PDF, o empuja directamente
  a Notion o Slack.
- **Vault de Obsidian** — Cada nota es un archivo Markdown con fecha,
  frontmatter (título, asistentes, duración) y transcript colapsable; escribe
  directamente en tu vault, con stubs de personas y empresas vinculadas desde
  asistentes.
- **Chat con tu historial** — Servidor MCP local de solo lectura
  (`aria-capture mcp`) para que Claude u otras herramientas busquen y lean tu
  historial de reuniones sin enviar nada a la nube.
- **Modo dictado** — Graba solo micrófono (sin audio del sistema) para notas
  de voz rápidas.
- **Elige tu modelo de IA** — NotarIA elige el backend automáticamente:
  - Claude Code CLI (si lo tienes instalado; sin costo extra sobre tu
    suscripción).
  - API de Anthropic (trae tu propia key, guardada en Keychain).
  - Endpoints OpenAI-compatibles (OpenAI, OpenRouter, Groq, LM Studio, o tu
    propio servidor).
  - Ollama (local, en tu Mac; sin API key, nada sale de tu equipo).

## Privacidad

- El audio se transcribe en tu Mac y **nunca sale de tu equipo**.
- Solo texto (transcript + tus notas) se envía a Claude en el paso de
  enhance, y ese paso es completamente opcional — NotarIA también funciona
  100% sin conexión.
- Un indicador permanente `● REC` se muestra mientras grabas; no existe un
  modo de grabación silenciosa. Eres responsable de obtener el
  consentimiento de los demás participantes según tu legislación local.
- Los campos sensibles del cache local (títulos, texto del transcript,
  notas) están cifrados en reposo con AES-GCM; la clave vive en el Keychain
  de macOS.
- Los secretos (la API key opcional de Anthropic) se guardan solo en
  Keychain, nunca en disco ni en el repositorio.

Ver [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) y
[`docs/DECISIONS.md`](./docs/DECISIONS.md) para el detalle de diseño.

## Requisitos

- macOS 14 (Sonoma) o superior, se recomienda Apple Silicon (whisper.cpp usa
  Metal para transcribir).
- Xcode 15+ (el Xcode.app completo, no solo las Command Line Tools — los
  scripts de build y test necesitan el toolchain incluido para XCTest y
  concurrencia de Swift).
- Permisos: **Micrófono**, **Grabación de pantalla** (para capturar el audio
  del sistema, no tu pantalla — macOS agrupa ambos bajo este permiso) y,
  opcionalmente, **Calendario** para la detección de reuniones.

## Build

```bash
git clone https://github.com/criguex/notaria.git
cd notaria
./scripts/build.sh   # swift build, con el toolchain de Xcode
./scripts/test.sh    # tests unitarios headless, sin GUI/audio/cambio de foco
```

Para correr la app de barra de menú directamente en desarrollo:

```bash
swift run aria-capture menubar
```

Corre `aria-capture` sin argumentos para ver la lista completa de
subcomandos del CLI (transcribe, enhance, chat, search, recipe, brief,
calendar, mcp, config, import-granola, …) — la app de barra de menú es una
capa SwiftUI delgada sobre el mismo core.

## Proveedores de IA

Todas las notas son gratis de generar con solo transcripción. Si quieres que
Claude mejore tus notas, elige un backend — NotarIA los revisa en este orden,
y puedes cambiar en Ajustes:

1. **CLI de Claude Code** — si lo tienes instalado con suscripción activa,
   NotarIA usa `claude -p` gratis. Sin costo extra, sin necesidad de API key.
2. **API de Anthropic** — guarda tu key en Keychain:

   ```bash
   security add-generic-password -s aria-anthropic -a aria -w 'sk-ant-...' -U
   ```

   Consigue una key en [console.anthropic.com](https://console.anthropic.com)
   → API Keys.

3. **Compatible con OpenAI** — apunta NotarIA a cualquier endpoint compatible
   con OpenAI (OpenAI, OpenRouter, Groq, LM Studio, o el tuyo) y agrega tu
   API key al Keychain.

4. **Ollama** — corre `ollama serve` localmente (ej: `ollama pull mistral`);
   NotarIA lo detecta y lo usa sin configuración. Todo se queda en tu Mac.

Sin ninguno de estos, NotarIA sigue funcionando: `enhance --offline` produce
una nota a partir del transcript crudo y tus propias notas, sin paso de IA.

## Estructura del proyecto

```
PLAN.md                     Roadmap público (hecho / backlog)
Package.swift                Paquete de Swift (ejecutable: aria-capture)
Sources/aria-capture/         Código de la app + CLI
Tests/AriaTests/              Tests unitarios headless
Vendor/whisper.cpp/           whisper.cpp vendorizado (MIT), ver su propio LICENSE
docs/                         Arquitectura, decisiones, spec de la ventana principal
scripts/build.sh, test.sh     Puntos de entrada de build y test
```

## Contribuir

Ver [CONTRIBUTING.md](./CONTRIBUTING.md).

## Seguridad

Ver [SECURITY.md](./SECURITY.md) para reportar una vulnerabilidad.

## Licencia

MIT — ver [LICENSE](./LICENSE). El `Vendor/whisper.cpp` vendorizado conserva
su propia licencia MIT y aviso de copyright.
