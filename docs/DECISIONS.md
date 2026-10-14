# Decisiones (ADRs resumidos)

- **ADR-01 — Swift nativo, no Electron.** El core es la captura de audio del sistema; ScreenCaptureKit + Core Audio son mucho más directos en Swift. Costo: Mac-only (aceptable en v1).
- **ADR-02 — Transcripción local (whisper.cpp + Metal).** Privacidad (audio no sale), costo cero, offline. Diarización por canal (mic vs sistema) en MVP; pyannote luego.
- **ADR-03 — Enhance con Claude, solo texto sale.** `claude-opus-4-8` por defecto (`claude-fable-5` opcional). Audio nunca se envía; enhance es opt-in.
- **ADR-04 — Salida Markdown a Obsidian.** Evita el silo cerrado de las apps de notas de reuniones típicas. Nota canónica = `.md`; cache interno en SQLite cifrado.
- **ADR-05 — Empezar por CLI (SwiftPM).** Validar lo riesgoso (captura+transcripción) sin pelear con bundle/entitlements. Envolver en app menubar en Fase 3.
