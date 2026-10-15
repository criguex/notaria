import XCTest
@testable import aria_capture

final class ToastLayoutTests: XCTestCase {

    private let screenArea = CGRect(x: 0, y: 0, width: 1_440, height: 900)

    // MARK: - ToastStackLayout

    func testSingleSlotSitsInTopRightCornerWithMargin() {
        let slots = ToastStackLayout.slots(for: [118], width: 360, in: screenArea)
        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots[0].x, 1_440 - 360 - ToastStackLayout.edgeMargin)
        XCTAssertEqual(slots[0].y, 900 - ToastStackLayout.edgeMargin - 118)
    }

    func testStackedSlotsNeverOverlapAndShareTheSameX() {
        let heights: [CGFloat] = [118, 132, 90]
        let slots = ToastStackLayout.slots(for: heights, width: 360, in: screenArea)
        XCTAssertEqual(slots.count, 3)
        XCTAssertEqual(Set(slots.map(\.x)).count, 1, "todos los avisos deben alinearse en la misma x")

        // De arriba hacia abajo: el borde superior de cada aviso queda exactamente
        // `gap` por debajo del borde inferior (= su origen, convención AppKit) del
        // anterior, nunca se solapan.
        for index in 1..<slots.count {
            let previousBottomEdge = slots[index - 1].y
            let currentTopEdge = slots[index].y + heights[index]
            XCTAssertEqual(currentTopEdge, previousBottomEdge - ToastStackLayout.gap)
            XCTAssertLessThan(currentTopEdge, previousBottomEdge)
        }
    }

    func testEmptyHeightsProduceNoSlots() {
        XCTAssertEqual(ToastStackLayout.slots(for: [], width: 360, in: screenArea), [])
    }

    // MARK: - ToastAnimation

    func testDurationIsZeroWithReduceMotionAndPositiveOtherwise() {
        XCTAssertEqual(ToastAnimation.duration(reduceMotion: true), 0)
        XCTAssertEqual(ToastAnimation.duration(reduceMotion: false), ToastAnimation.slideDuration)
        XCTAssertGreaterThan(ToastAnimation.slideDuration, 0)
    }

    // MARK: - ToastProgress

    func testFractionGoesFromZeroToOneAsTimeElapses() {
        XCTAssertEqual(ToastProgress.fraction(remaining: 30, total: 30), 0)
        XCTAssertEqual(ToastProgress.fraction(remaining: 15, total: 30), 0.5)
        XCTAssertEqual(ToastProgress.fraction(remaining: 0, total: 30), 1)
    }

    func testFractionClampsOutOfRangeInputs() {
        XCTAssertEqual(ToastProgress.fraction(remaining: 40, total: 30), 0, "no puede ir 'hacia atrás' de 0")
        XCTAssertEqual(ToastProgress.fraction(remaining: -5, total: 30), 1, "no puede pasar de 1")
        XCTAssertEqual(ToastProgress.fraction(remaining: 0, total: 0), 1, "total 0 y sin tiempo restante = completo")
        XCTAssertEqual(ToastProgress.fraction(remaining: 5, total: 0), 0, "total 0 pero con 'restante' > 0 no está completo")
    }
}
