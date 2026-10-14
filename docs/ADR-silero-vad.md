# ADR — Silero VAD nativo en whisper.cpp vendorizado

## Contexto

`Vendor/whisper.cpp` está vendorizado en v1.7.1 (parche a mano: `ggml-metal.metal`
tiene `ggml/src/ggml-common.h` inlineado porque el Package.swift usa el manifiesto
SPM viejo de `spm-headers`, sin soporte de recursos con `#include` locales). ADR-06
(vault, 2026-10-13) dejó la arquitectura (`VoiceActivityDetector`, `EnergyVAD`,
`SileroVAD`/`SileroModel`/`VADFactory`) con `SileroVAD` cayendo siempre a
`EnergyVAD`, y recomendó retomar por bump de whisper.cpp antes que sumar ONNX
Runtime, reusando el toolchain ggml/Metal ya parcheado.

## Decisión

**No se hizo bump completo del repo.** Se vendorizó solo lo necesario para VAD,
backporteado a mano sobre el v1.7.1 existente, tomando como referencia
whisper.cpp **v1.7.6** (primera versión de la serie 1.7.x con
`whisper_vad_init_from_file_with_params` / `whisper_vad_detect_speech` /
`whisper_vad_segments_*`).

### Por qué no el bump completo

Entre v1.7.1 y v1.7.6 el backend de `ggml` se reestructuró: `ggml-metal.m` pasó a
directorio (`ggml-metal/`), aparecieron `ggml-cpu/` y `ggml-backend-reg.cpp`, y
`ggml.c` se dividió en `ggml.c` + `ggml.cpp` + `gguf.cpp`. Migrar seguiría
rompiendo el Package.swift a mano (lista explícita de fuentes, sin CMake) y el
shader Metal ya parcheado. Riesgo real **M**, igual que estimó el ADR-06, y
afecta la transcripción principal — justo lo que no queremos tocar sin poder
validar con audio real en cada paso.

### Qué se backporteó (solo aditivo, nada del pipeline de transcripción existente cambia)

1. **`ggml.h` / `ggml.c`**: un op nuevo, `GGML_OP_PAD_REFLECT_1D` (usado por el
   front-end STFT de Silero para el padding reflejado). Es CPU-only — el kernel
   Metal no se tocó porque whisper.cpp fuerza `use_gpu = false` para VAD
   (`// TODO: GPU VAD is forced disabled until the performance is improved`,
   comentario real de upstream). Se añadió: entrada de enum, nombre/símbolo en
   las tablas `GGML_OP_NAME`/`GGML_OP_SYMBOL` (con su `static_assert` de conteo),
   builder `ggml_pad_reflect_1d()`, kernel CPU `ggml_compute_forward_pad_reflect_1d`
   y los tres `case` que ya existían para `GGML_OP_PAD` (forward, backward-abort,
   `get_n_tasks`).
2. **`whisper.h`**: declaraciones públicas de la API standalone de VAD
   (`whisper_vad_context_params`, `whisper_vad_params`,
   `whisper_vad_init_from_file_with_params`, `whisper_vad_detect_speech`,
   `whisper_vad_segments_from_samples`, getters de segmentos, `whisper_vad_free*`).
   **No** se tocó `whisper_full_params` (los campos `vad`/`vad_model_path` de la
   integración profunda de upstream, que reemplazarían el VAD dentro de
   `whisper_full`, se dejaron fuera a propósito).
3. **`whisper.cpp`**: la implementación de VAD de v1.7.6 (grafo Silero: capa STFT
   vía `ggml_pad_reflect_1d` + `ggml_conv_1d`, encoder de 4 conv1d, LSTM manual
   con puertas sigmoid/tanh, conv final + sigmoid; loader del `.bin` con el mismo
   formato de magic+hparams+tensores que usa el modelo principal). Se simplificó
   un punto respecto a upstream: upstream resuelve el `ggml_backend_buffer_type_t`
   de cada tensor con una lista de prioridad multi-dispositivo
   (`buft_list_t`/`make_buft_list`/`select_weight_buft`, no presente en v1.7.1);
   como VAD es siempre CPU-only, se reemplazó por asignación directa al único
   backend CPU vía `ggml_backend_alloc_ctx_tensors`, evitando portar esa
   maquinaria completa. Se corrigió además un bug de dimensionamiento del propio
   backport (ver "Bug encontrado" abajo) y se cerró una fuga menor en
   `whisper_vad_free` (upstream no libera `vctx->buffer`, el de `h_state`/`c_state`;
   aquí sí).
4. **`ggml_graph_compute_helper`** (helper interno de `whisper.cpp`, no público):
   se le agregó un 4º parámetro `sched_reset = true` con default, para que VAD
   pueda reusar el grafo entre ventanas sin resetear el scheduler en cada chunk
   (igual que v1.7.6). Los tres call-sites existentes (transcripción principal)
   siguen pasando 3 argumentos y mantienen el comportamiento exacto de antes.

### Bug encontrado y corregido durante el backport

El primer intento crasheaba con `GGML_ASSERT(obj_new) failed` en `ggml.c` al
cargar el modelo: el contexto de metadata (`ctx`, dimensionado para
`n_tensors * ggml_tensor_overhead()`) se usaba tanto para los tensores "meta"
temporales (`ggml_new_tensor_*`) como para los reales (`ggml_dup_tensor` dentro
de `create_tensor`), duplicando el conteo real de objetos sin duplicar el
tamaño reservado. Se separó en `meta_ctx` (temporal, se libera tras construir
los 15 tensores) y `ctx` (persistente, va a `model.ctxs`), como hace upstream
con sus dos contextos (`ctx` de meta + `ctx_map`/`get_ctx` del loader real).

## Modelo

`ggml-silero-v5.1.2.bin`, Hugging Face `ggml-org/whisper-vad`
(`https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin`).
885098 bytes, sha256 `29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf`
(ambos verificados por `aria-capture model vad` tras la descarga). El nombre de
archivo ya coincidía con `SileroModel.fileName` desde el ADR-06 original.

## Validación real hecha en esta sesión

- `scripts/build.sh` y `scripts/test.sh` en verde (223/223).
- Descarga real del modelo a una ruta temporal de test (no al directorio real
  del usuario), con verificación de tamaño y sha256.
- Silencio puro → 0 regiones. Tono senoidal puro + ruido blanco → 0 regiones
  (la red neuronal correctamente no confunde energía con habla, a diferencia
  de `EnergyVAD`). Voz sintetizada con `say -o ... --data-format=LEF32@16000`
  (archivo, sin reproducir audio) → región detectada que cubre el tramo de voz
  con el padding esperado.
- Transcripción principal (`WhisperTranscriber`/`whisper_full`) con el modelo
  `tiny` sobre el mismo fixture de voz: sigue transcribiendo correctamente con
  Metal activo (`METAL = 1` en `whisper_print_system_info`) tras el parche —
  cero regresión.

## Riesgos conocidos que quedan

- Upstream documenta corrupción de memoria con VAD en algunos archivos
  específicos y crashes en builds CoreML (ADR-06, sin reproducir aquí).
- No se validó con audio real de reuniones (multi-hablante, ruido de sala,
  eco) ni con el modelo `v6.2.0` (más nuevo, no descargado ni probado).
- El backport no se ha corrido bajo sanitizers; la única validación de memoria
  es "no crashea y no sale basura" en los casos de prueba de esta sesión.
