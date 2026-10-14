# Ventana principal de NotarIA — Spec

## Problema

NotarIA empezó como una app solo de barra de menú: `AriaMenuView` (menú) y dos
ventanas monotarea (`NotesWindowView` 440×300, `ChatWindowView` 540×400). Todo
el dato ya existe (`MeetingStore` SQLite, `.md` en Obsidian, `MeetingSearch`
FTS5, `RecipeStore`/`TemplateStore`) pero solo era accesible por CLI o por el
submenú "Recientes" (máx. 5). Hacía falta una ventana principal navegable que
exponga ese dato sin construir un cliente propietario tipo app de notas de
reuniones genérica, con su propia SPA de decenas de rutas dentro de una ventana
embebida.

## Identidad (propia, no un clon)

- Privacidad por defecto — la ventana es un visor/lanzador de datos 100%
  locales, no un servicio con login/workspace.
- Salida abierta — el `.md` en Obsidian sigue siendo la nota canónica. La
  ventana NO reemplaza a Obsidian como editor; muestra y enlaza, no compite.
- "Tus notas mandan" — el panel de notas propias nunca queda subordinado al
  resumen IA en la jerarquía visual.
- Consentimiento + indicador visible — ya resuelto (`ConsentManager`, `● REC`);
  la ventana no necesita un overlay flotante adicional para esto.

Consecuencia de diseño: NotarIA usa un **`NavigationSplitView` nativo de
macOS** (sidebar + detalle, como Mail.app/Notes.app) en vez de una interfaz
web empotrada con decenas de secciones de configuración de equipo. Menos
superficie, más Mac-nativo.

## Qué NO entra en v1

- Login / workspace / multi-usuario (NotarIA es local-first, mono-usuario por
  diseño).
- Overlay flotante enriquecido durante la llamada más allá de la píldora
  actual (el indicador de barra ya cumple el principio de transparencia).
- Settings de equipo/SaaS (Slack, Notion, HubSpot, API keys de terceros) —
  backlog separado, nice-to-have de equipo.
- Editor de documento por bloques — las notas siguen siendo `.md` planos
  editados en Obsidian.

## Navegación

```
NavigationSplitView
├── Sidebar
│   ├── Hoy              (próxima reunión + detección de llamada — ya en el menú, se refleja aquí)
│   ├── Historial         (todas las reuniones, MeetingStore, con buscador FTS5)
│   ├── Chat              (mover ChatWindowView aquí, con historial de preguntas)
│   ├── Recipes & Plantillas
│   └── Ajustes           (AriaConfig visual + estado de permisos)
└── Detail (según selección de la lista en Historial)
    └── Detalle de reunión: notas propias + transcript diarizado + acciones
```

- Ventana nueva `Window(id: "aria-main")`, mismo patrón SwiftUI que las 2
  ventanas existentes — no requiere Dock icon ni cambiar `activationPolicy`
  por defecto (`.accessory` se mantiene; abrir la ventana no convierte a
  NotarIA en app "regular" salvo mientras está abierta).
- Shortcut global para abrirla (`⌘⇧A`) + ítem nuevo en `AriaMenuView` ("Abrir
  NotarIA") en todos los estados del menú.
- Comportamiento de cierre: cerrar la ventana la oculta (no mata el proceso —
  NotarIA sigue viva en la barra); `MenuBarExtra` ya cumple el rol de tray.

## Vistas — modelo de datos (ya existe, solo se expone)

| Vista | Fuente de datos | Métodos ya existentes |
|---|---|---|
| Hoy | `MeetingCalendar.shared.nextMeeting()`, `CallDetector.currentSignal()` | ya usados en `MenuBarApp.swift` |
| Historial | `MeetingStore` tabla `meetings` (`id, date, title, duration, note_path, wav_path, source, external_id`) | reemplazar `recentMeetings(limit:5)` por listado completo + paginación simple |
| Buscador (dentro de Historial) | `MeetingSearch` (FTS5 en memoria sobre filas descifradas) | `MeetingSearch.search(query:)` ya implementado, solo falta UI |
| Detalle de reunión | `MeetingStore.segments(meetingID:)` (transcript diarizado) + `MeetingStore.quickNotes(meetingID:)` + `note_path` (abrir en Obsidian) | ya expuestos, usados hoy solo desde `MeetingChat`/CLI |
| Chat | `MeetingChat.answer(question:onChunk:)` | igual que `ChatWindowView` hoy, se mueve de ventana standalone a sección |
| Recipes & Plantillas | `RecipeStore` (carpeta `~/Documents/Aria/Recipes/`), `TemplateStore` (`~/Documents/Aria/Plantillas/`) | **nunca expuestos en UI** — cada `.md` ES el prompt/plantilla; la vista puede ser tan simple como listar + botón "Revelar en Finder/Obsidian" + aplicar desde el detalle de una reunión |
| Ajustes | `AriaConfig` (JSON): `obsidianDir`, `claudeModel`, `whisperModel`, `language`, `keepAudio`, `retentionDays`, `alwaysOn`, `showUpcoming`, `ignoreNoParticipants`, `calendarIgnore`, `transcriptPolish` | hoy solo `aria-capture config get/set`; la vista es un formulario 1:1 sobre estos campos + estado de permisos (`Permissions.swift`) con botones a System Settings |

La columna `source`/`external_id` de `meetings` (usada por `GranolaImporter`)
permite marcar en Historial qué reuniones son nativas de NotarIA vs.
importadas desde Granola.

## Identidad visual

- Sidebar + detail nativos de AppKit/SwiftUI (`NavigationSplitView`), con el
  chrome estándar de macOS.
- El vínculo a Obsidian es un diferenciador a reforzar: cada reunión en
  Historial/Detalle lleva un botón "Abrir en Obsidian" (usa `note_path`, ya en
  la DB) en vez de una vista propietaria que compita con el vault.
- Colores de marca (ver `BRAND.md` del paquete de identidad): Sello como
  acento único, resto de la paleta en fondos/texto; sin paleta genérica de
  producto de IA.

## Prioridades

### MVP (v1 de la ventana)

| Casilla | Feature | Esfuerzo | Prioridad |
|---|---|---|---|
| 10.1 | `Window(id: "aria-main")` con `NavigationSplitView` (sidebar: Hoy/Historial/Chat/Ajustes) | M | ALTA |
| 10.2 | Historial: lista completa de `MeetingStore` + buscador conectado a `MeetingSearch` | M | ALTA |
| 10.3 | Detalle de reunión: notas propias + transcript diarizado (`segments`) + botón "Abrir en Obsidian" (`note_path`) | S | ALTA |
| 10.4 | Chat: migrar `ChatWindowView` a sección de la ventana principal, con historial de preguntas en la sesión | S | MEDIA |
| 10.5 | Ajustes visual: formulario sobre `AriaConfig` + estado de permisos (mic/pantalla/calendario) con acceso directo a System Settings | M | ALTA |
| 10.6 | Ítem "Abrir NotarIA…" en `AriaMenuView` (todos los estados) + shortcut global para abrir la ventana | S | MEDIA |

### Después (v1.1+)

| Casilla | Feature | Esfuerzo | Prioridad |
|---|---|---|---|
| 10.7 | Recipes & Plantillas: listar `RecipeStore`/`TemplateStore` + aplicar recipe desde el detalle de una reunión | S | MEDIA |
| 10.8 | Filtro por origen en Historial (nativo vs. importado) | S | BAJA |
| 10.9 | Vista "Hoy" enriquecida (mini-agenda del día, no solo el próximo evento) | M | BAJA |
| 10.10 | Onboarding guiado de permisos en un solo flujo (reemplaza el diálogo plano de `ConsentManager`) | S | BAJA |
| 10.11 | Overlay flotante enriquecido (mini-transcript en vivo durante la llamada) | L | BAJA — ya resuelto por la píldora propia |

## No aplica / descartado explícitamente

- Login/workspace, Settings de equipo, integraciones SaaS → fuera de alcance
  de una app local-first mono-usuario.
- Editor de documento por bloques → las notas siguen siendo `.md` en Obsidian.
- Copiar el layout/strings/diseño visual de otras apps de notas de reuniones
  → por diseño; la identidad visual propia está en `BRAND.md`.
