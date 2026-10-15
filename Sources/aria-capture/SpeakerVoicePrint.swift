import Accelerate
import Foundation

struct SpeakerEmbedding: Codable, Equatable {
    var vector: [Float]

    static func cosineSimilarity(_ a: SpeakerEmbedding, _ b: SpeakerEmbedding) -> Float {
        guard a.vector.count == b.vector.count, !a.vector.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        vDSP_dotpr(a.vector, 1, b.vector, 1, &dot, vDSP_Length(a.vector.count))
        vDSP_dotpr(a.vector, 1, a.vector, 1, &normA, vDSP_Length(a.vector.count))
        vDSP_dotpr(b.vector, 1, b.vector, 1, &normB, vDSP_Length(b.vector.count))
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }
}

protocol SpeakerEmbedder {
    func embedding(samples: [Float], sampleRate: Double) -> SpeakerEmbedding?
}

/// Embedding de voz "simple" (sin red neuronal ni modelo descargable): coeficientes de reflexión
/// LPC (Levinson-Durbin sobre autocorrelación, ventana Hamming) promediados sobre los frames
/// sonoros de un segmento. Es el clásico LPCC pre-MFCC de reconocimiento de hablante; captura
/// formantes (timbre/tracto vocal), suficiente para distinguir voces claramente distintas sin
/// sumar un runtime binario nuevo. El pitch se usa solo para decidir qué frames son sonoros, no se
/// concatena al vector (diluía la separación entre hablantes, ver docs/ADR-hablantes.md).
struct SpectralSpeakerEmbedder: SpeakerEmbedder {
    var lpcOrder: Int = 10
    var frameSeconds: Double = 0.03
    var hopSeconds: Double = 0.015
    var minPitchHz: Double = 70
    var maxPitchHz: Double = 400

    func embedding(samples: [Float], sampleRate: Double) -> SpeakerEmbedding? {
        let frameLen = max(lpcOrder + 2, Int(frameSeconds * sampleRate))
        guard samples.count >= frameLen else { return nil }
        let hopLen = max(1, Int(hopSeconds * sampleRate))

        var lpcSum = [Float](repeating: 0, count: lpcOrder)
        var lpcFrames = 0

        // Solo se promedian frames SONOROS (voz real, no silencio/consonantes/ruido): mezclar
        // frames no sonoros diluye la diferencia de timbre entre hablantes. El pitch en sí no se
        // concatena al vector — validado con voces reales (`say`) en esta sesión: sumarlo diluye
        // la separación entre hablantes de tono similar, mientras que los coeficientes de
        // reflexión solos ya discriminan mejor el timbre/formantes.
        var start = 0
        while start + frameLen <= samples.count {
            let frame = Array(samples[start..<(start + frameLen)])
            if Self.estimatePitch(frame: frame, sampleRate: sampleRate, minHz: minPitchHz, maxHz: maxPitchHz) != nil,
               let lpc = Self.reflectionCoefficients(frame: frame, order: lpcOrder) {
                for i in 0..<lpcOrder { lpcSum[i] += lpc[i] }
                lpcFrames += 1
            }
            start += hopLen
        }
        guard lpcFrames > 0 else { return nil }

        let vector = lpcSum.map { $0 / Float(lpcFrames) }

        var normSquared: Float = 0
        vDSP_svesq(vector, 1, &normSquared, vDSP_Length(vector.count))
        let norm = normSquared.squareRoot()
        guard norm > 0 else { return nil }
        return SpeakerEmbedding(vector: vector.map { $0 / norm })
    }

    /// Coeficientes de reflexión (PARCOR) vía autocorrelación + recursión de Levinson-Durbin.
    /// Se usan los coeficientes de reflexión (acotados a [-1, 1] por construcción) en vez de los
    /// coeficientes LPC finales ("a"): el primer coeficiente "a" tiende a dominar la magnitud del
    /// vector para cualquier sonido sonoro y diluye la similitud coseno entre voces distintas,
    /// mientras que PARCOR es la métrica clásica de identificación de hablante pre-MFCC — más
    /// discriminativa entre formantes distintos y más estable frente a variación natural del mismo
    /// hablante (validado con tonos sintéticos de dos formantes en esta sesión). `nil` si el frame
    /// está en silencio (energía ~0) o la recursión degenera.
    static func reflectionCoefficients(frame: [Float], order: Int) -> [Float]? {
        guard frame.count > order else { return nil }
        var window = [Float](repeating: 0, count: frame.count)
        vDSP_hamm_window(&window, vDSP_Length(frame.count), 0)
        var windowed = [Float](repeating: 0, count: frame.count)
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(frame.count))

        var autocorrelation = [Double](repeating: 0, count: order + 1)
        for lag in 0...order {
            let count = windowed.count - lag
            guard count > 0 else { return nil }
            var sum: Float = 0
            windowed.withUnsafeBufferPointer { buffer in
                vDSP_dotpr(buffer.baseAddress!, 1, buffer.baseAddress! + lag, 1, &sum, vDSP_Length(count))
            }
            autocorrelation[lag] = Double(sum)
        }
        guard autocorrelation[0] > 1e-9 else { return nil }
        autocorrelation[0] *= 1.0001

        var coefficients = [Double](repeating: 0, count: order + 1)
        var reflections = [Double](repeating: 0, count: order + 1)
        var error = autocorrelation[0]
        for i in 1...order {
            guard error > 1e-12 else { break }
            var accumulator = autocorrelation[i]
            for j in 1..<i { accumulator -= coefficients[j] * autocorrelation[i - j] }
            var reflection = accumulator / error
            guard reflection.isFinite else { break }
            reflection = min(max(reflection, -0.9999), 0.9999)
            reflections[i] = reflection
            var updated = coefficients
            updated[i] = reflection
            for j in 1..<i { updated[j] = coefficients[j] - reflection * coefficients[i - j] }
            coefficients = updated
            error *= (1 - reflection * reflection)
        }
        guard reflections[1...order].allSatisfy(\.isFinite) else { return nil }
        return reflections[1...order].map(Float.init)
    }

    /// Pitch (F0) por autocorrelación normalizada en el rango de voz humana; `nil` si el frame
    /// no parece sonoro (pico de autocorrelación débil respecto a la energía del frame).
    static func estimatePitch(frame: [Float], sampleRate: Double, minHz: Double, maxHz: Double) -> Double? {
        let minLag = max(1, Int(sampleRate / maxHz))
        let maxLag = Int(sampleRate / minHz)
        guard maxLag < frame.count, minLag < maxLag else { return nil }

        var energy: Float = 0
        vDSP_dotpr(frame, 1, frame, 1, &energy, vDSP_Length(frame.count))
        guard energy > 1e-9 else { return nil }

        var bestLag = -1
        var bestCorrelation: Float = 0
        frame.withUnsafeBufferPointer { buffer in
            for lag in minLag...maxLag {
                let count = frame.count - lag
                var sum: Float = 0
                vDSP_dotpr(buffer.baseAddress!, 1, buffer.baseAddress! + lag, 1, &sum, vDSP_Length(count))
                if sum > bestCorrelation {
                    bestCorrelation = sum
                    bestLag = lag
                }
            }
        }
        guard bestLag > 0, bestCorrelation / energy > 0.45 else { return nil }
        return sampleRate / Double(bestLag)
    }
}
