import Foundation

struct SpeakerDiarizationResult {
    let segments: [TranscriptSegment]
    let speakerCount: Int
    /// Centroide por etiqueta ("Hablante 1", ...). Vacío si no se logró separar (speakerCount <= 1).
    let embeddings: [String: SpeakerEmbedding]
}

/// Capa 1: separar voces dentro de UN canal (el del sistema, "Otros"/"Ellos") usando el embedder
/// de `SpeakerVoicePrint.swift` + el clustering de `SpeakerClustering.swift`. Si no hay suficiente
/// señal (pocos segmentos, muy cortos, o el clustering no distingue más de una voz), se mantiene
/// el comportamiento actual sin tocar los segmentos.
enum SpeakerDiarizer {

    struct Options {
        var minSegmentSecondsForEmbedding: Double = 0.6
        var maxSegmentSecondsForEmbedding: Double = 12
        var embedder: SpeakerEmbedder = SpectralSpeakerEmbedder()
        var clustering: SpeakerClustering.Options = .default
        static let `default` = Options()
    }

    static func relabel(
        segments: [TranscriptSegment],
        originalSpeaker: String,
        channelSamples: [Float],
        sampleRate: Double,
        options: Options = .default
    ) -> SpeakerDiarizationResult {
        let targetIndices = segments.indices.filter { segments[$0].speaker == originalSpeaker }
        guard targetIndices.count >= 2 else {
            return SpeakerDiarizationResult(segments: segments, speakerCount: targetIndices.isEmpty ? 0 : 1, embeddings: [:])
        }

        var points: [SpeakerClustering.Point] = []
        for index in targetIndices {
            let segment = segments[index]
            let duration = segment.end - segment.start
            guard duration >= options.minSegmentSecondsForEmbedding else { continue }
            let cappedEnd = min(segment.end, segment.start + options.maxSegmentSecondsForEmbedding)
            let startSample = max(0, Int(segment.start * sampleRate))
            let endSample = min(channelSamples.count, Int(cappedEnd * sampleRate))
            guard endSample > startSample else { continue }
            guard let embedding = options.embedder.embedding(
                samples: Array(channelSamples[startSample..<endSample]), sampleRate: sampleRate
            ) else { continue }
            points.append(SpeakerClustering.Point(index: index, embedding: embedding, duration: duration))
        }

        guard points.count >= 2 else {
            return SpeakerDiarizationResult(segments: segments, speakerCount: 1, embeddings: [:])
        }

        let assignment = SpeakerClustering.cluster(points, options: options.clustering)
        let clusterCount = Set(assignment.values).count
        guard clusterCount > 1 else {
            return SpeakerDiarizationResult(segments: segments, speakerCount: 1, embeddings: [:])
        }

        var relabeled = segments
        var centroids: [Int: (vector: [Float], duration: Double)] = [:]
        for point in points {
            guard let clusterID = assignment[point.index] else { continue }
            relabeled[point.index].speaker = label(for: clusterID)
            var sum = centroids[clusterID] ?? (vector: [Float](repeating: 0, count: point.embedding.vector.count), duration: 0)
            let total = sum.duration + point.duration
            if total > 0 {
                for i in 0..<sum.vector.count {
                    let weighted = Double(sum.vector[i]) * sum.duration + Double(point.embedding.vector[i]) * point.duration
                    sum.vector[i] = Float(weighted / total)
                }
            }
            sum.duration = total
            centroids[clusterID] = sum
        }

        assignLeftoverSegments(targetIndices: targetIndices, embeddedIndices: Set(points.map(\.index)), relabeled: &relabeled)

        var embeddings: [String: SpeakerEmbedding] = [:]
        for (id, sum) in centroids {
            embeddings[label(for: id)] = SpeakerEmbedding(vector: sum.vector)
        }
        return SpeakerDiarizationResult(segments: relabeled, speakerCount: clusterCount, embeddings: embeddings)
    }

    static func label(for clusterID: Int) -> String {
        "Hablante \(clusterID + 1)"
    }

    /// Segmentos del canal demasiado cortos para embebir quedan sin cluster propio; se les asigna
    /// la etiqueta del segmento embebido temporalmente más cercano (mismo canal), así todo el canal
    /// queda consistente en vez de mezclar "Hablante N" con la etiqueta genérica original.
    private static func assignLeftoverSegments(targetIndices: [Int], embeddedIndices: Set<Int>, relabeled: inout [TranscriptSegment]) {
        let leftover = targetIndices.filter { !embeddedIndices.contains($0) }
        guard !leftover.isEmpty else { return }
        for index in leftover {
            guard let position = targetIndices.firstIndex(of: index) else { continue }
            var offset = 1
            while true {
                let left = position - offset
                let right = position + offset
                if left < 0 && right >= targetIndices.count { break }
                if right < targetIndices.count, embeddedIndices.contains(targetIndices[right]) {
                    relabeled[index].speaker = relabeled[targetIndices[right]].speaker
                    break
                }
                if left >= 0, embeddedIndices.contains(targetIndices[left]) {
                    relabeled[index].speaker = relabeled[targetIndices[left]].speaker
                    break
                }
                offset += 1
            }
        }
    }
}
