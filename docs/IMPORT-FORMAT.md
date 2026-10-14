# Importador genérico — formatos soportados

`aria-capture import <ruta> [--source nombre]` importa una carpeta (recorre
subcarpetas) o un archivo suelto. También hay un botón "Importar…" en
Ajustes (NSOpenPanel) que hace lo mismo.

Es idempotente: cada nota importada queda ligada a un `external_id`
(`fuente:id`). Si vuelves a importar el mismo archivo/registro sin cambios,
se actualiza en el mismo lugar en vez de duplicarse. El resumen final
reporta `importadas` / `actualizadas` / `fallidas`.

`--source nombre` fija la fuente para todo lo importado en esa corrida
(se ve como etiqueta en Historial). Si no se pasa, se usa el `source` del
propio archivo/registro cuando lo trae, o un valor por defecto según el
formato (`notes`, `vtt`, `srt`, `json`).

## .md / .txt

Frontmatter YAML opcional al inicio del archivo:

```markdown
---
title: Reunión con el equipo de ventas
date: 2026-01-15T10:00:00-05:00
attendees: [Ana Pérez, Juan Gómez]
source: notion
id: nota-123
---

## Resumen

Contenido en markdown libre, tal cual queda en la nota.
```

- `title`: si falta, se usa el nombre del archivo (guiones/underscores → espacios).
- `date`: ISO 8601, `yyyy-MM-dd HH:mm` o `yyyy-MM-dd`. Si falta, se usa la fecha de modificación del archivo.
- `attendees`: lista `[a, b]` o `a, b` separado por comas.
- `source`: nombre de la fuente (override de `--source` si no se pasó el flag).
- `id`: identificador estable para idempotencia. Si falta, se usa un hash del contenido del archivo.

Sin frontmatter, el archivo completo es el cuerpo de la nota.

## .vtt / .srt

Transcripts de Zoom/Teams/Meet u otros exports de subtítulos. Se convierten
a segmentos con tiempo de inicio/fin y, si viene, hablante:

- WebVTT con `<v Nombre>texto`.
- Texto plano con prefijo `Nombre: texto` (una línea por turno).

Ejemplo VTT:

```
WEBVTT

00:00:00.000 --> 00:00:02.500
<v Ana>Hola a todos, empecemos.

00:00:02.500 --> 00:00:05.000
<v Juan>Perfecto, arranco compartiendo pantalla.
```

Ejemplo SRT:

```
1
00:00:00,000 --> 00:00:02,500
Ana: Hola a todos, empecemos.

2
00:00:02,500 --> 00:00:05,000
Juan: Perfecto, arranco compartiendo pantalla.
```

El título sale del nombre del archivo y la fecha de la fecha de
modificación del archivo. Los hablantes detectados se usan como
participantes.

## .json

Un objeto, o un arreglo de objetos (una nota por elemento):

```json
{
  "source": "zoom",
  "id": "abc-123",
  "title": "Reunión con el equipo de ventas",
  "date": "2026-01-15T10:00:00-05:00",
  "attendees": ["Ana Pérez", "Juan Gómez"],
  "body": "## Resumen\n\nContenido en markdown.",
  "transcript": "Ana: Hola a todos\nJuan: Arranco compartiendo pantalla.",
  "url": "https://ejemplo.com/reunion/abc-123"
}
```

Campos:

- `title` (opcional; si falta, nombre del archivo o `"<nombre> N"` dentro de un arreglo).
- `date` (opcional; ISO 8601 o `yyyy-MM-dd[ HH:mm]`; si falta, fecha de modificación del archivo).
- `attendees` (opcional, lista de strings).
- `source` (opcional; lo pisa `--source` si se pasó).
- `id` (opcional; si falta, hash del contenido resuelto).
- `body` (opcional; markdown del cuerpo de la nota).
- `transcript` (opcional; texto plano, una línea por turno).
- `url` (opcional; se agrega como enlace "Ver original" al final del cuerpo).

### JSON de otras fuentes

El importador también reconoce nombres de campo alternativos comunes en
exports JSON de otras apps de notas de reuniones. Se soportan alias de
campos: `meeting_at` ↔ `date`, `summary_markdown` ↔ `body`, `participants` ↔
`attendees`. Si tu JSON ya incluye un campo `"source"`, no es necesario
pasar el flag `--source`.
