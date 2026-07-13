import XCTest
@testable import AnkyProtocol

final class LevelTests: XCTestCase {
    // Parity fixtures — the same values are asserted by the TypeScript
    // implementation (protocol test/level.test.ts). If one side changes, both must.
    private let requirements = [
        480, 778, 1260, 2041, 3306, 5356, 8677, 14057, 22772, 36891, 59763, 96816,
    ]
    private let thresholds = [
        0, 480, 1258, 2518, 4559, 7865, 13221, 21898, 35955, 58727, 95618, 155381,
    ]

    func testLevelOneToTwoCostsExactly480Seconds() {
        XCTAssertEqual(AnkyLevel.baseSeconds, 480)
        XCTAssertEqual(AnkyLevel.requirementSeconds(forLevel: 1), 480)
        XCTAssertEqual(AnkyLevel.thresholdSeconds(forLevel: 2), 480)
        XCTAssertEqual(AnkyLevel.level(forTotalSeconds: 479), 1)
        XCTAssertEqual(AnkyLevel.level(forTotalSeconds: 480), 2)
    }

    func testRequirementsAndThresholdsMatchParityFixtures() {
        for (index, want) in requirements.enumerated() {
            XCTAssertEqual(AnkyLevel.requirementSeconds(forLevel: index + 1), want)
        }
        for (index, want) in thresholds.enumerated() {
            XCTAssertEqual(AnkyLevel.thresholdSeconds(forLevel: index + 1), want)
        }
    }

    func testProgressIsMonotonicAndNeverDecays() {
        var lastLevel = 1
        var total = 0
        while total <= 10_000 {
            let progress = AnkyLevel.progress(forTotalSeconds: total)
            XCTAssertGreaterThanOrEqual(progress.level, lastLevel)
            XCTAssertGreaterThanOrEqual(progress.secondsIntoLevel, 0)
            XCTAssertLessThanOrEqual(progress.secondsIntoLevel, progress.secondsRequired)
            XCTAssertGreaterThanOrEqual(progress.percent, 0)
            XCTAssertLessThanOrEqual(progress.percent, 1)
            lastLevel = progress.level
            total += 97
        }
    }

    func testProgressAtExactBoundaries() {
        let atBoundary = AnkyLevel.progress(forTotalSeconds: 480)
        XCTAssertEqual(atBoundary.level, 2)
        XCTAssertEqual(atBoundary.secondsIntoLevel, 0)
        XCTAssertEqual(atBoundary.secondsRequired, 778)
        XCTAssertEqual(atBoundary.percent, 0)

        let justBefore = AnkyLevel.progress(forTotalSeconds: 479)
        XCTAssertEqual(justBefore.level, 1)
        XCTAssertEqual(justBefore.secondsIntoLevel, 479)
    }

    func testNegativeInputClampsSanely() {
        XCTAssertEqual(AnkyLevel.level(forTotalSeconds: -100), 1)
        XCTAssertEqual(AnkyLevel.progress(forTotalSeconds: -100).secondsIntoLevel, 0)
    }

    func testLevelIsBoundedForAnyRepresentableTotal() {
        let level = AnkyLevel.level(forTotalSeconds: Int.max)
        XCTAssertLessThanOrEqual(level, AnkyLevel.maxLevel)
        // the geometric curve outruns 2^53 seconds long before maxLevel
        XCTAssertGreaterThan(level, 60)
        XCTAssertLessThanOrEqual(AnkyLevel.progress(forTotalSeconds: Int.max).percent, 1)
    }
}
