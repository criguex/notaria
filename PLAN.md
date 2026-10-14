# NotarIA — PLAN de construcción

> Roadmap público. El histórico detallado de decisiones de diseño vive en
> `docs/DECISIONS.md` y `docs/ARCHITECTURE.md`.

## Qué es NotarIA
App macOS que toma notas de reuniones: captura audio del sistema + micrófono
(sin unirse a la llamada), transcribe **local** con whisper.cpp, y funde
transcript + tus notas con **Claude** en una nota Markdown que cae en tu
**Obsidian**. Privacidad: el audio nunca sale del Mac.

## Stack
Swift / SwiftUI (menubar) · ScreenCaptureKit + AVAudioEngine (audio) ·
whisper.cpp + Metal (transcripción) · API de Claude o CLI de Claude Code
(enhance) · SQLite cifrado (cache) · salida Markdown.

---

## Hecho

- **Captura de audio** — `SystemAudioCapture` (ScreenCaptureKit) +
  `MicCapture` (AVAudioEngine) en dos canales (mic=Yo, sistema=Otros);
  grabador growable hasta 2 h; aserción `NoDisplaySleep` mientras se graba.
- **Transcripción local** — whisper.cpp vendorizado con Metal; chunking con
  solapamiento, VAD por energía, filtros anti-alucinación; arquitectura de
  VAD intercambiable (`VoiceActivityDetector`) con fallback a energía
  mientras no haya un modelo de red neuronal instalado.
- **Notas + Enhance + Obsidian** — notas rápidas en vivo, doble backend de
  Claude (CLI de Claude Code o API con key en Keychain), `ObsidianWriter` con
  frontmatter YAML y transcript colapsable, modo offline sin enhance.
- **App de barra de menú** — `MenuBarExtra` con Grabar/Detener, ícono de
  estado, historial en SQLite cifrado (AES-GCM, clave en Keychain), detección
  de llamada por micrófono + apps conocidas + URLs de pestañas del navegador.
- **Privacidad y always-on** — consentimiento explícito en el primer uso,
  indicador permanente `● REC`, modo always-on opt-in con auto-stop tras
  silencio, retención configurable.
- **Paridad de producto con apps de notas de reuniones similares** —
  calendario local (EventKit), chat sobre el historial, recipes/plantillas
  reutilizables, atribución de hablantes por nombre, pre-meeting brief,
  People & Companies como notas de Obsidian con backlinks, búsqueda FTS5,
  idioma configurable, modo dictado (solo micrófono), servidor MCP local de
  solo lectura (`aria-capture mcp`), pulido de transcript con Claude.
- **Ventana principal** — `NavigationSplitView` nativo (Hoy / Historial /
  Chat / Ajustes), detalle de reunión con transcript + notas + enlace a
  Obsidian, filtro por origen (nativo vs. importado).
- **Experiencia en reunión** — píldora flotante con tiempo y transcript en
  vivo por hover, prompt "¿Tomar notas?" de un clic al detectar una llamada o
  un evento de calendario que empieza, aviso para sumar calendarios de
  Google/Outlook desde Ajustes del Sistema.
- **Importar desde Granola** — `aria-capture import-granola <directorio-json>`
  trae tus propias notas exportadas (JSON) a tu vault de Obsidian, sin perder
  el historial que ya tenías. Pensado para usarse junto al MCP oficial de
  Granola cuando lo expongas como fuente de datos.

## Backlog

| Feature | Esfuerzo | Prioridad |
|---|---|---|
| VAD por red neuronal (bump de whisper.cpp u ONNX Runtime) | M | ALTA |
| ASR alternativo más rápido como fallback | M | BAJA |
| Exportes avanzados (PDF/email/Slack) | M | BAJA |
| Edición visual de transcript | M | MEDIA |
| Share directo a Slack (brief/follow-up) | L | MEDIA |
| Tono/longitud configurable en enhance (formal/casual/corto) | S | MEDIA |
| OAuth directo a Google/Microsoft Calendar (alternativa a cuentas de Sistema) | L | BAJA |
| Diagnóstico de red para debug de la API de Claude | L | BAJA |
| Recipes & Plantillas dentro de la ventana principal | S | MEDIA |
| Onboarding guiado de permisos en un solo flujo | S | BAJA |

## Testing
`scripts/test.sh` → suite headless (XCTest): lógica de chunking/VAD/
anti-alucinación, formatter, cifrado, SQLite+purga, writer/YAML, config,
recorder growable, importador. Sin GUI, sin audio, sin cambio de foco.
Los smoke tests con GUI/audio real viven aparte y no corren en CI.
