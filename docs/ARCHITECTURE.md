# Arquitectura (resumen)

## Pipeline
```
Captura (ScreenCaptureKit sistema + AVAudioEngine mic, 2 canales)
   → Transcripción (whisper.cpp local, Metal) → segmentos {start,end,speaker,text}
   → Enhance (Claude: transcript + tus notas → Markdown)   [solo texto sale del Mac]
   → Salida (nota .md en Obsidian) + cache SQLite cifrado
```

## Componentes
- **AudioCapture** — sistema (ScreenCaptureKit) + mic (AVAudioEngine), dos canales lógicos (mic=Yo, system=Otros), PCM 16 kHz mono.
- **Transcriber** — whisper.cpp con Metal; chunking con solapamiento; casi tiempo real.
- **Enhancer** — Claude API (streaming); prompt de sistema que fija formato de nota.
- **ObsidianWriter** — escribe `<fecha> - <titulo>.md` con frontmatter en carpeta configurable.
- **Store** — SQLite (GRDB) para meetings/segments/notes, cifrado en reposo.

## Frontera de privacidad
El **audio nunca cruza la red**. Solo **texto** va a Claude (opt-in por reunión). Sin enhance, Aria es 100% offline.
