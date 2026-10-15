import XCTest
@testable import aria_capture

final class SpeakerClusteringTests: XCTestCase {

    private func point(_ index: Int, _ vector: [Float], duration: Double = 2) -> SpeakerClustering.Point {
        SpeakerClustering.Point(index: index, embedding: SpeakerEmbedding(vector: vector), duration: duration)
    }

    func testTwoClearlyDistinctVoicesGetTwoClusters() {
        let points = [
            point(0, [1, 0, 0, 0]),
            point(1, [0, 1, 0, 0]),
            point(2, [1, 0, 0, 0]),
            point(3, [0, 1, 0, 0])
        ]
        let assignment = SpeakerClustering.cluster(points)
        XCTAssertEqual(assignment[0], assignment[2])
        XCTAssertEqual(assignment[1], assignment[3])
        XCTAssertNotEqual(assignment[0], assignment[1])
        XCTAssertEqual(Set(assignment.values).count, 2)
    }

    func testIdenticalVoiceStaysOneCluster() {
        let points = (0..<5).map { point($0, [1, 0, 0, 0]) }
        let assignment = SpeakerClustering.cluster(points)
        XCTAssertEqual(Set(assignment.values).count, 1)
    }

    func testClusterLabelsAreOrderedByFirstAppearance() {
        let points = [
            point(0, [0, 1, 0, 0]),
            point(1, [1, 0, 0, 0]),
            point(2, [0, 1, 0, 0]),
            point(3, [1, 0, 0, 0])
        ]
        let assignment = SpeakerClustering.cluster(points)
        XCTAssertEqual(assignment[0], 0)
        XCTAssertEqual(assignment[1], 1)
    }

    func testTinyClusterMergesIntoNearestLargerOne() {
        var options = SpeakerClustering.Options.default
        options.minClusterSeconds = 3
        let points = [
            point(0, [1, 0, 0, 0], duration: 5),
            point(1, [1, 0, 0, 0], duration: 5),
            point(2, [0.3, 0.95, 0, 0], duration: 0.4)
        ]
        let assignment = SpeakerClustering.cluster(points, options: options)
        XCTAssertEqual(Set(assignment.values).count, 1)
    }

    func testClusterCountRespectsMaxClustersCap() {
        var options = SpeakerClustering.Options.default
        options.maxClusters = 2
        options.minClusterSeconds = 0
        let vectors: [[Float]] = [
            [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]
        ]
        let points = vectors.enumerated().map { index, vector in point(index, vector, duration: 3) }
        let assignment = SpeakerClustering.cluster(points, options: options)
        XCTAssertLessThanOrEqual(Set(assignment.values).count, 2)
    }

    func testEmptyInputReturnsEmptyAssignment() {
        XCTAssertTrue(SpeakerClustering.cluster([]).isEmpty)
    }

    func testSimilarityThresholdControlsSplitting() {
        var permissive = SpeakerClustering.Options.default
        permissive.similarityThreshold = 0.1
        var strict = SpeakerClustering.Options.default
        strict.similarityThreshold = 0.999

        let points = [
            point(0, [1, 0, 0, 0]),
            point(1, [0.9, 0.1, 0, 0])
        ]
        XCTAssertEqual(Set(SpeakerClustering.cluster(points, options: permissive).values).count, 1)
        XCTAssertEqual(Set(SpeakerClustering.cluster(points, options: strict).values).count, 2)
    }

    /// Embeddings LPC reales (SpectralSpeakerEmbedder) extraídos de dos voces `say` distintas
    /// (Paulina es_MX y "Grandpa" es_ES) grabadas en una reunión sintética de QA E2E. Con el
    /// umbral anterior (0.93) la similitud cruzada entre estas voces (hasta ~0.964) caía DENTRO
    /// del "mismo hablante" y el clustering las fusionaba siempre en un solo cluster.
    func testRealSynthesizedVoicesFromTwoDistinctSpeakersSplitIntoTwoClusters() {
        let ana: [[Float]] = [
            [0.7873849, -0.5459983, 0.043707892, -0.22204794, -0.08294013, -0.123317696, -0.0388167, -0.051606674, -0.05491758, -0.037719075],
            [0.7710579, -0.5651936, 0.049289122, -0.22760065, -0.10137591, -0.11434787, -0.038578328, -0.06086307, -0.053218734, -0.020419408],
            [0.78050303, -0.57048595, 0.026521524, -0.19459558, -0.060535498, -0.10677429, -0.04296416, -0.059571285, -0.06488653, -0.04604187],
            [0.75446886, -0.54026896, 0.1474483, -0.22736567, -0.14621943, -0.17447822, -0.09003618, -0.06356973, -0.03601737, -0.013501682],
            [0.8290823, -0.46248147, 0.06453906, -0.23065789, -0.10495359, -0.15966275, -0.028288199, -0.055399816, -0.029049864, -0.012013184]
        ]
        let juan: [[Float]] = [
            [0.7146657, -0.6499256, 0.20158614, -0.03695401, -0.12160165, -0.05547561, -0.03216786, -0.057839368, -0.050803397, -0.004631587],
            [0.70289564, -0.6363804, 0.25769567, -0.066650234, -0.13147964, -0.038369052, -0.038374122, -0.0789517, -0.060352772, 0.0009524279],
            [0.7085283, -0.6422986, 0.23310883, -0.042897984, -0.13762693, -0.04896328, -0.03325829, -0.06516627, -0.05063922, -0.0021337753],
            [0.70754653, -0.64717907, 0.20754677, 0.0022558812, -0.14861412, -0.084949486, -0.039736643, -0.05951199, -0.054576058, -0.007386866]
        ]
        var index = 0
        var points: [SpeakerClustering.Point] = []
        for vector in ana + juan {
            points.append(point(index, vector, duration: 3.5))
            index += 1
        }
        let assignment = SpeakerClustering.cluster(points)
        let anaClusters = Set((0..<ana.count).map { assignment[$0] })
        let juanClusters = Set((ana.count..<(ana.count + juan.count)).map { assignment[$0] })
        XCTAssertEqual(anaClusters.count, 1, "Los 5 segmentos de la misma voz deben quedar en un solo cluster")
        XCTAssertEqual(juanClusters.count, 1, "Los 4 segmentos de la otra voz deben quedar en un solo cluster")
        XCTAssertNotEqual(anaClusters, juanClusters, "Dos voces distintas deben quedar en clusters distintos")
        XCTAssertEqual(Set(assignment.values).count, 2)
    }
}
