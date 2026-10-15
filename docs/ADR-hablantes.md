# ADR — Identificación de hablantes ("Otros" → nombres reales)

## Contexto

Hoy la diarización es por canal + pausas (ADR previo, Fase 3): mic = "Yo", sistema = "Otros"/"Ellos",
sin distinguir cuántas personas hay del otro lado ni quiénes son. El objetivo (visión del usuario,
vault `17 - Detección de reuniones y Nub de Granola`) es que el resumen atribuya decisiones y tareas
a personas reales. Se diseñan 4 capas independientes — cada una aporta aunque las otras fallen o
estén apagadas.

## Capa 1 — Separar voces dentro del canal del sistema

### Opciones evaluadas

**(a) sherpa-onnx** (MIT): diarización offline real (segmentación pyannote + embeddings de hablante
tipo 3D-Speaker/WeSpeaker), vía binario/xcframework + modelos ONNX descargables (decenas de MB,
dos modelos: segmentación + embedding).

**(b) Embeddings simples, sin modelo ni runtime nuevo**: coeficientes LPC/reflexión (PARCOR) vía
autocorrelación + Levinson-Durbin sobre cada segmento de voz ya detectado por el VAD existente,
clustering por similitud coseno contra centroides — el clásico LPCC pre-MFCC de identificación de
hablante.

### Decisión: (b)

**Riesgo.** `Vendor/whisper.cpp` ya documentó en el ADR de Silero VAD lo costoso de vendorizar un
solo runtime binario a mano (parches de `Package.swift`, shader Metal con headers inlineados,
backport puntual de una API). Sumar sherpa-onnx sería un **segundo** runtime binario nuevo —sin
patrón de vendoring limpio en este repo— para una capa que, por diseño, es la única de las 4 que
puede no aportar nada sin que el usuario note degradación (cae a "Otros" sin separar). El mismo
razonamiento que descartó ONNX Runtime para VAD en el ADR-06 (riesgo real **M**, desproporcionado
frente al valor marginal cuando hay una alternativa de menor riesgo) aplica aquí con más fuerza:
VAD es el pipeline principal; separar voces dentro de "Otros" es una mejora incremental sobre algo
que ya funciona razonablemente (el enhance ya infiere nombres del contexto). Dos modelos ONNX
adicionales (segmentación + embedding) también duplican la superficie de fallos de descarga/formato
frente a un solo `.bin` como el de Silero.

**Validación bajo las reglas de esta sesión.** Sin poder grabar/reproducir audio real ni abrir la
app, la única evidencia posible es con voces sintéticas (`say`). Un pipeline neuronal pesado es
difícil de validar con rigor bajo esa restricción, mientras que (b) es 100% determinista y
testeable con lógica pura.

**Camino de mejora futuro sin romper la arquitectura.** Se definió `SpeakerEmbedder` (protocolo,
igual patrón que `VoiceActivityDetector`/`SileroVAD`/`VADFactory` del ADR de Silero): el día que se
quiera un backend neuronal, se implementa como otro `SpeakerEmbedder` sin tocar `SpeakerDiarizer`,
`SpeakerClustering` ni ninguno de sus llamantes.

### Implementación

- `SpeakerVoicePrint.swift`: `SpectralSpeakerEmbedder` — por cada frame de 30 ms (hop 15 ms) de un
  segmento, calcula coeficientes de **reflexión** (PARCOR, no los coeficientes LPC "a" finales) vía
  autocorrelación (Accelerate/vDSP) + Levinson-Durbin en `Double` con los reflection coefficients
  acotados a `[-0.9999, 0.9999]`. Solo se promedian frames **sonoros** (gate de voicing por
  autocorrelación normalizada, el mismo check que decide el pitch). El vector final (10 dims, orden
  LPC) se normaliza L2 para comparar por similitud coseno.
- `SpeakerClustering.swift`: clustering incremental puro — vecino más cercano contra centroides
  (media ponderada por duración), fusión de clusters por debajo de `minClusterSeconds` (ruido/
  alucinación corta) y tope `maxClusters`; etiquetas normalizadas por orden de primera aparición.
- `SpeakerDiarizer.swift`: conecta ambos con los segmentos reales de un canal — slicea las muestras
  crudas por `start`/`end` de cada segmento "Otros", embebe, clusteriza, y relabela a
  "Hablante 1/2/3…"; si el resultado es 1 solo cluster (o hay muy pocos/muy cortos segmentos para
  embeber con confianza), **no toca nada** — se mantiene "Otros"/"Ellos" tal cual hoy.
- Integrado en el único punto donde se genera el transcript final (`transcribeWav` en `main.swift`,
  usado tanto por el CLI `enhance` como por `MenuBarApp.stopAndGenerate`): el canal del sistema pasa
  por `SpeakerDiarizer.relabel` solo si `AriaConfig.speakerSeparationEnabled` (opt-in, default
  `false` — sin validación con audio real de reuniones, apagado por defecto como el resto de capas
  nuevas de esta sesión).
- `aria-capture model speakers`: activa el flag y explica el enfoque. **No hay modelo que descargar
  en esta versión** (el embedder es Swift puro, sin red neuronal) — se deja documentado que, si en
  el futuro se suma sherpa-onnx u otro backend neuronal, su modelo caería en la misma carpeta que ya
  usa Silero/Whisper (`~/Library/Application Support/Aria/models`) con el mismo patrón de
  descarga+verificación+fallback.

### Validación real hecha en esta sesión (voces sintéticas, sin reproducir audio)

Con `say -v <voz> -o archivo.wav --data-format=LEF32@16000 "..."` (nunca por altavoz), tres voces de
macOS: Mónica (es_ES, mujer), Paulina/"Sandy (Español México)" (es_MX, mujer) y Daniel (en_GB,
hombre). Comparando embeddings reales (sin pasar por VAD/whisper, solo `SpeakerDiarizer` sobre
segmentos con límites conocidos):

- **Mismo hablante** (dos frases distintas de la misma voz): similitud coseno 0.998–0.999 siempre.
- **Hablantes claramente distintos** (Mónica vs. "Sandy"): 0.918–0.933 — **se separan
  correctamente** en una conversación alternada de 4 turnos (100% de los turnos al hablante
  correcto, 0 falsos positivos).
- **Hablantes parecidos** (Mónica vs. Paulina, mismo género y familia de voz del motor de macOS):
  0.963–0.978 — **no se separan**, caen al comportamiento actual (fail-safe, no es un error).
- **3 voces en una sola conversación**: el resultado depende de qué tan distinguibles sean las 3
  entre sí — con Mónica/"Sandy"/Daniel, el clustering aisló correctamente una de las tres pero
  fusionó las otras dos (el embedder no captura pitch/género en absoluto, solo forma espectral vía
  LPC; dos timbres que resultan cercanos en ese espacio se fusionan aunque "suenen" distinto al
  oído). **En ningún caso de esta sesión se fragmentó una sola voz en varios "Hablante N" falsos**
  — el error siempre fue de sub-separación (fusionar de más), nunca de sobre-separación, que es la
  dirección de falla preferible (perder la mejora es menos dañino que inventar personas).
- El umbral de similitud (`SpeakerClustering.Options.default.similarityThreshold = 0.93`) se
  calibró con estos números: deja un margen claro contra el piso de "mismo hablante" (0.998) y
  separa el caso de voces claramente distintas, a costa de no separar voces muy parecidas.

**Conclusión honesta:** la Capa 1 con este embedder simple separa bien voces **claramente**
distintas y es inofensiva (no fragmenta) cuando no puede distinguirlas, pero no es un sustituto de
un embedding neuronal entrenado (sherpa-onnx/pyannote) para voces parecidas — exactamente el
trade-off de riesgo/beneficio por el que se eligió (b) en vez de (a). Pendiente de Cristian:
validar con audio real de reuniones (varias personas, ruido de sala, eco), que es lo único que
puede mover la aguja en reconstruir mejor este umbral o decidir sumar un backend neuronal más
adelante.

## Capa 2 — Ponerle nombre a "Hablante N"

`SpeakerNaming.swift` (puro, salvo donde se indica):

- **(a) Asistentes de calendario**: si el número de "Hablante N" sin otro indicio coincide con el
  número de asistentes del evento, se sugiere por orden de primera aparición — confianza **baja**
  (0.35, fuente `.calendarOrder`), es una corazonada de orden, no un hecho.
- **(b) Nombres dichos en la conversación**: `extractMentionedNames` detecta patrones vocativos
  ("gracias, Ana", "oye Juan") y nombre-al-inicio-de-frase-con-coma ("Ana, ¿qué opinas?"), con
  stopwords de arranques de frase comunes. `attributedMentions` atribuye la mención al hablante
  ADYACENTE de turno distinto (a quien se dirige o quien responde), no a quien la dice. Si el
  nombre mencionado coincide con un asistente real del calendario → confianza **alta** (0.85,
  `.mentionedAndAttendee`); si no hay ese cruce → confianza **baja** (0.4, `.mentioned`), puede ser
  ruido o una tercera persona nombrada de paso.
- **(c) Accesibilidad (Zoom/Teams), opt-in y apagado por defecto**: `MeetingParticipantsAccessibility.swift`
  — `AccessibilityPermission` (AXIsProcessTrusted) + `MeetingParticipantsAccessibilityReader`
  (recorre el árbol AXUIElement de la app de llamada, mejor esfuerzo) + `ParticipantNameFilter`
  (lógica PURA y testeada: descarta chrome de UI, emails, timers, se queda con candidatos tipo
  "Nombre Apellido"). Config `participantsAccessibilityEnabled`, default `false`. Sin poder abrir
  una llamada real en esta sesión, el recorrido AX en sí no está validado end-to-end — mismo
  patrón de honestidad que `VisualContextCapture` (Fase 11): la pieza impura no se prueba con un
  mock de ventana real, solo su filtro puro.
- **(d) Memoria de voces, opt-in y apagado por defecto**: `VoiceMemoryStore.swift` — al confirmar/
  renombrar un "Hablante N" a un nombre real desde el panel de Participantes, si
  `voiceMemoryEnabled` está activo se guarda el embedding de ese cluster cifrado (AES-GCM,
  `CacheCipher`, mismo patrón que el resto del cache) en `~/Library/Application Support/Aria/voice-memory.json`,
  indexado por nombre. En la siguiente reunión, `SpeakerResolutionPipeline` compara los nuevos
  centroides contra los perfiles guardados (similitud ≥ 0.86 = confianza alta, fuente
  `.voiceMemory`, pisa cualquier otra señal). Borrable (`VoiceMemoryStore.delete`).

`SpeakerAssignment.displayLabel(for:)` traduce confianza a texto: **≥ 0.7** → nombre tal cual
(confirmado); **0.3–0.7** → `"Hablante N (¿Nombre?)"` (dudoso, pendiente de confirmar); `< 0.3` → se
ignora, queda `"Hablante N"`. `SpeakerResolutionPipeline.swift` es el único punto de integración
(usado por el CLI `enhance` y por `MenuBarApp.stopAndGenerate`) para no duplicar esta lógica.

## Capa 3 — El enhance recibe nombres y pistas de confianza

Cambio mínimo y de bajo riesgo: como el transcript que recibe Claude ya trae literalmente las
etiquetas finales ("Ana", "Hablante 2 (¿Juan?)", "Hablante 1"), no hace falta mandar un bloque de
contexto aparte — alcanza con enseñarle la convención al modelo. Se reescribió el párrafo
"Hablantes" del `MeetingEnhancer.systemPrompt`: una etiqueta `(¿Nombre?)` es DUDOSA (puede
mencionarse como contexto, nunca como hecho confirmado ni para atribuir una decisión/action item);
un nombre sin paréntesis SÍ está confirmado (calendario, memoria de voz o el usuario) y se puede
usar con naturalidad; sin ninguna pista, se conserva "Hablante N"/"Otros" — nunca inventar.

## Capa 4 — UI "Participantes"

`ParticipantsPanelView.swift` (archivo propio, no en `MainWindowView.swift` para minimizar el diff
en un archivo compartido con otro agente en paralelo): por cada hablante detectado en los segmentos
de la reunión — tiempo de habla (suma de duraciones), sugerencia pendiente con botón
"Confirmar: `<nombre>`" con un clic (parsea `"Hablante N (¿Nombre?)"` y renombra), renombrar manual
libre, y fusionar dos hablantes (selecciona dos etiquetas, reutiliza `MeetingStore.renameSpeaker`
— renombrar A a B ya fusiona sus segmentos). Si `voiceMemoryEnabled` está activo y el hablante tiene
un embedding guardado para esta reunión, aparece el checkbox "Recordar esta voz" al confirmar/
renombrar. Integrado en `MeetingDetailView` con una sola inserción de 5 líneas.

## Esquema nuevo (aditivo, migración segura como `pauses`/`visual_captures`)

`speaker_profiles(id, meeting_id, speaker_label, embedding_json cifrado)` en `MeetingStore` —
guarda, por reunión, el embedding de cada "Hablante N" ya resuelto, para que el panel de
Participantes pueda ofrecer "recordar esta voz" tiempo después sin recalcular nada.

## Config nueva (todo opt-in, default `false`)

`speakerSeparationEnabled`, `voiceMemoryEnabled`, `participantsAccessibilityEnabled`.

## Riesgos conocidos que quedan

- El embedder simple no es neuronal: separa bien voces claramente distintas, no voces parecidas
  (ver números arriba). Sin validar con audio real de reuniones (ruido de sala, eco, solapamiento).
- `extractMentionedNames` es heurístico (regex/stopwords), puede dar falsos positivos — mitigado
  porque toda mención sin cruce con un asistente real queda en confianza baja (requiere confirmar).
- La lectura por Accesibilidad (capa 2c) no se validó contra una ventana de Zoom/Teams real en esta
  sesión (prohibido abrir apps/llamadas); su jerarquía AX puede no coincidir con lo esperado en
  producción — por eso es opt-in y con fallback silencioso a lista vacía.
- `SpeakerClustering` es online/secuencial (no re-evalúa asignaciones pasadas): el orden de llegada
  de los turnos puede afectar el resultado cuando hay 3+ voces con similitudes parecidas entre sí
  (ver caso Mónica/Sandy/Daniel arriba).
