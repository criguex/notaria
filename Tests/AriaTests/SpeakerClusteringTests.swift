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
}
