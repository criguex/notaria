import Foundation

/// Clustering incremental puro: agrupa embeddings de voz en "hablantes" estables dentro de UNA
/// reunión (sin modelo, sin estado entre reuniones — eso es `VoiceMemoryStore`). Vecino más
/// cercano por similitud coseno contra centroides (media ponderada por duración), con fusión de
/// clusters minúsculos (ruido/alucinación corta) y tope de clusters simultáneos.
enum SpeakerClustering {

    struct Options {
        // Recalibrado con voces reales sintetizadas (say, dos voces distintas) en QA E2E:
        // mismo hablante ~0.983-0.999 de similitud coseno, hablantes distintos ~0.94-0.96.
        // 0.93 (valor anterior) caía DENTRO del rango de hablantes distintos, así que nunca
        // separaba voces reales — 0.97 cae en el hueco entre ambos rangos.
        var similarityThreshold: Float = 0.97
        var minClusterSeconds: Double = 1.2
        var maxClusters: Int = 6
        static let `default` = Options()
    }

    struct Point {
        let index: Int
        let embedding: SpeakerEmbedding
        let duration: Double
    }

    private struct Centroid {
        var vector: [Float]
        var duration: Double
    }

    /// Devuelve `point.index -> id de cluster normalizado (0-based, en orden de primera aparición)`.
    static func cluster(_ points: [Point], options: Options = .default) -> [Int: Int] {
        guard !points.isEmpty else { return [:] }

        var centroids: [Int: Centroid] = [:]
        var assignment: [Int: Int] = [:]
        var nextID = 0

        for point in points {
            var bestID = -1
            var bestSimilarity: Float = -1
            for (id, centroid) in centroids {
                let similarity = SpeakerEmbedding.cosineSimilarity(
                    SpeakerEmbedding(vector: centroid.vector), point.embedding
                )
                if similarity > bestSimilarity {
                    bestSimilarity = similarity
                    bestID = id
                }
            }

            if bestID >= 0, bestSimilarity >= options.similarityThreshold, let existing = centroids[bestID] {
                centroids[bestID] = merged(existing, with: point)
                assignment[point.index] = bestID
            } else {
                centroids[nextID] = Centroid(vector: point.embedding.vector, duration: point.duration)
                assignment[point.index] = nextID
                nextID += 1
            }
        }

        mergeClustersBelowMinDuration(assignment: &assignment, centroids: &centroids, options: options)
        mergeSmallestUntilWithinCap(assignment: &assignment, centroids: &centroids, maxClusters: options.maxClusters)

        return normalizedLabels(assignment: assignment, order: points.map(\.index))
    }

    private static func merged(_ centroid: Centroid, with point: Point) -> Centroid {
        let totalDuration = centroid.duration + point.duration
        guard totalDuration > 0 else { return centroid }
        var vector = [Float](repeating: 0, count: centroid.vector.count)
        for i in 0..<vector.count {
            let weighted = Double(centroid.vector[i]) * centroid.duration
                + Double(point.embedding.vector[i]) * point.duration
            vector[i] = Float(weighted / totalDuration)
        }
        return Centroid(vector: vector, duration: totalDuration)
    }

    private static func merged(_ a: Centroid, _ b: Centroid) -> Centroid {
        let totalDuration = a.duration + b.duration
        guard totalDuration > 0 else { return a }
        var vector = [Float](repeating: 0, count: a.vector.count)
        for i in 0..<vector.count {
            let weighted = Double(a.vector[i]) * a.duration + Double(b.vector[i]) * b.duration
            vector[i] = Float(weighted / totalDuration)
        }
        return Centroid(vector: vector, duration: totalDuration)
    }

    private static func nearestOther(to id: Int, centroids: [Int: Centroid]) -> Int? {
        guard let target = centroids[id] else { return nil }
        var bestID: Int?
        var bestSimilarity: Float = -1
        for (otherID, centroid) in centroids where otherID != id {
            let similarity = SpeakerEmbedding.cosineSimilarity(
                SpeakerEmbedding(vector: target.vector), SpeakerEmbedding(vector: centroid.vector)
            )
            if similarity > bestSimilarity {
                bestSimilarity = similarity
                bestID = otherID
            }
        }
        return bestID
    }

    private static func mergeCluster(_ sourceID: Int, into targetID: Int, assignment: inout [Int: Int], centroids: inout [Int: Centroid]) {
        guard let source = centroids[sourceID], let target = centroids[targetID] else { return }
        centroids[targetID] = merged(target, source)
        centroids.removeValue(forKey: sourceID)
        for (pointIndex, clusterID) in assignment where clusterID == sourceID {
            assignment[pointIndex] = targetID
        }
    }

    private static func mergeClustersBelowMinDuration(assignment: inout [Int: Int], centroids: inout [Int: Centroid], options: Options) {
        while centroids.count > 1 {
            let tiny = centroids.filter { $0.value.duration < options.minClusterSeconds }
            guard let smallestID = tiny.min(by: { $0.value.duration < $1.value.duration })?.key,
                  let targetID = nearestOther(to: smallestID, centroids: centroids) else { break }
            mergeCluster(smallestID, into: targetID, assignment: &assignment, centroids: &centroids)
        }
    }

    private static func mergeSmallestUntilWithinCap(assignment: inout [Int: Int], centroids: inout [Int: Centroid], maxClusters: Int) {
        while centroids.count > maxClusters {
            guard let smallestID = centroids.min(by: { $0.value.duration < $1.value.duration })?.key,
                  let targetID = nearestOther(to: smallestID, centroids: centroids) else { break }
            mergeCluster(smallestID, into: targetID, assignment: &assignment, centroids: &centroids)
        }
    }

    private static func normalizedLabels(assignment: [Int: Int], order: [Int]) -> [Int: Int] {
        var remap: [Int: Int] = [:]
        var next = 0
        var result: [Int: Int] = [:]
        for pointIndex in order {
            guard let clusterID = assignment[pointIndex] else { continue }
            if remap[clusterID] == nil {
                remap[clusterID] = next
                next += 1
            }
            result[pointIndex] = remap[clusterID]
        }
        return result
    }
}
