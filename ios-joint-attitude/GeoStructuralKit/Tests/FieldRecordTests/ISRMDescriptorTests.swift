import XCTest
import OrientationCore
@testable import FieldRecord

/// Every ISRM class boundary, pinned. These are the tests to read against a copy of the
/// standard: if a boundary here is wrong, every record classified by it is wrong, and no
/// other test in the project would notice.
final class ISRMBoundaryTests: XCTestCase {

    /// Boundaries are half-open throughout: a value exactly on a boundary belongs to the
    /// upper class.
    func testSpacingBoundaries() {
        let cases: [(Double, SpacingClass)] = [
            (0, .extremelyClose), (19.999, .extremelyClose),
            (20, .veryClose), (59.999, .veryClose),
            (60, .close), (199.999, .close),
            (200, .moderate), (599.999, .moderate),
            (600, .wide), (1999.999, .wide),
            (2000, .veryWide), (5999.999, .veryWide),
            (6000, .extremelyWide), (100_000, .extremelyWide)
        ]
        for (millimetres, expected) in cases {
            XCTAssertEqual(SpacingClass(millimetres: millimetres), expected, "at \(millimetres) mm")
        }
    }

    func testPersistenceBoundaries() {
        let cases: [(Double, PersistenceClass)] = [
            (0, .veryLow), (0.999, .veryLow),
            (1, .low), (2.999, .low),
            (3, .medium), (9.999, .medium),
            (10, .high), (19.999, .high),
            (20, .veryHigh), (1000, .veryHigh)
        ]
        for (metres, expected) in cases {
            XCTAssertEqual(PersistenceClass(metres: metres), expected, "at \(metres) m")
        }
    }

    func testApertureBoundaries() {
        let cases: [(Double, ApertureClass)] = [
            (0, .veryTight), (0.099, .veryTight),
            (0.1, .tight), (0.249, .tight),
            (0.25, .partlyOpen), (0.499, .partlyOpen),
            (0.5, .open), (2.499, .open),
            (2.5, .moderatelyWide), (9.999, .moderatelyWide),
            (10, .veryWide), (99.999, .veryWide),
            (100, .extremelyWide), (999.999, .extremelyWide),
            (1000, .cavernous), (5000, .cavernous)
        ]
        for (millimetres, expected) in cases {
            XCTAssertEqual(ApertureClass(millimetres: millimetres), expected, "at \(millimetres) mm")
        }
    }

    func testApertureGroups() {
        XCTAssertEqual(ApertureClass.veryTight.group, .closed)
        XCTAssertEqual(ApertureClass.partlyOpen.group, .closed)
        XCTAssertEqual(ApertureClass.open.group, .gapped)
        XCTAssertEqual(ApertureClass.moderatelyWide.group, .gapped)
        XCTAssertEqual(ApertureClass.veryWide.group, .open)
        XCTAssertEqual(ApertureClass.cavernous.group, .open)
    }

    /// No value may fall into two classes, and none between them. A gap or an overlap
    /// would make a classification depend on the order the cases happen to be declared
    /// in — which is exactly the defect in the published aperture table.
    func testClassesTileTheirScaleWithoutGapsOrOverlaps() {
        // The aperture scale tiles only across `derivable`: the published open-ended
        // `wide` deliberately overlaps three of the others.
        for value in stride(from: 0.0, through: 7000.0, by: 0.5) {
            let matches = SpacingClass.allCases.filter { $0.millimetreRange.contains(value) }
            XCTAssertEqual(matches.count, 1, "spacing \(value) mm matched \(matches)")
        }
        for value in stride(from: 0.0, through: 25.0, by: 0.01) {
            let matches = PersistenceClass.allCases.filter { $0.metreRange.contains(value) }
            XCTAssertEqual(matches.count, 1, "persistence \(value) m matched \(matches)")
        }
        for value in stride(from: 0.0, through: 1200.0, by: 0.05) {
            let matches = ApertureClass.derivable.filter { $0.millimetreRange.contains(value) }
            XCTAssertEqual(matches.count, 1, "aperture \(value) mm matched \(matches)")
        }
    }

    /// The published "wide, > 10 mm" is kept so a notebook value can be stored as it was
    /// written, but it is never produced from a measurement — otherwise classifying
    /// 50 mm would depend on the order the cases are declared in.
    func testTheOverlappingPublishedApertureClassIsStorableButNeverDerived() {
        XCTAssertTrue(ApertureClass.allCases.contains(.wide))
        XCTAssertFalse(ApertureClass.derivable.contains(.wide))
        XCTAssertTrue(ApertureClass.wide.isLegacyPublishedClass)
        XCTAssertFalse(ApertureClass.veryWide.isLegacyPublishedClass)

        // Its published range really does overlap the others, which is why it is excluded.
        XCTAssertTrue(ApertureClass.wide.millimetreRange.contains(50))
        XCTAssertTrue(ApertureClass.veryWide.millimetreRange.contains(50))

        for millimetres in [10.0, 50.0, 99.0, 500.0, 5000.0] {
            XCTAssertNotEqual(
                ApertureClass(millimetres: millimetres), .wide,
                "a measurement of \(millimetres) mm must not derive the legacy class"
            )
        }
        XCTAssertEqual(ApertureClass(millimetres: 50), .veryWide)

        // It can still be stored and read back, which is the point of keeping it.
        let data = try! JSONEncoder().encode(ApertureClass.wide)
        XCTAssertEqual(try! JSONDecoder().decode(ApertureClass.self, from: data), .wide)
        XCTAssertEqual(ApertureClass.wide.group, .gapped)
    }

    func testNonsensicalValuesAreRejectedRatherThanClamped() {
        XCTAssertNil(SpacingClass(millimetres: -1))
        XCTAssertNil(PersistenceClass(metres: -0.5))
        XCTAssertNil(ApertureClass(millimetres: -0.01))
        XCTAssertNil(SpacingClass(millimetres: .nan))
        XCTAssertNil(ApertureClass(millimetres: .infinity))
    }

    /// The nine ISRM roughness classes, I–IX: stepped first, then undulating, then
    /// planar, each running rough → smooth → slickensided.
    func testRoughnessClassNumbering() {
        let expected: [(RoughnessProfile, RoughnessWaviness, Int)] = [
            (.rough, .stepped, 1), (.smooth, .stepped, 2), (.slickensided, .stepped, 3),
            (.rough, .undulating, 4), (.smooth, .undulating, 5), (.slickensided, .undulating, 6),
            (.rough, .planar, 7), (.smooth, .planar, 8), (.slickensided, .planar, 9)
        ]
        for (profile, waviness, number) in expected {
            let roughness = RoughnessClass(profile: profile, waviness: waviness)
            XCTAssertEqual(roughness.isrmClass, number, "\(profile) \(waviness)")
        }
        XCTAssertEqual(RoughnessClass(profile: .rough, waviness: .stepped).romanNumeral, "I")
        XCTAssertEqual(RoughnessClass(profile: .slickensided, waviness: .planar).romanNumeral, "IX")
        XCTAssertEqual(RoughnessClass.allCases.count, 9)
        XCTAssertEqual(Set(RoughnessClass.allCases.map(\.isrmClass)).count, 9)
    }

    func testWeatheringGrades() {
        XCTAssertEqual(WeatheringGrade.fresh.code, "W1")
        XCTAssertEqual(WeatheringGrade.residualSoil.code, "W6")
        XCTAssertEqual(WeatheringGrade(grade: 3), .moderatelyWeathered)
        XCTAssertNil(WeatheringGrade(grade: 0))
        XCTAssertNil(WeatheringGrade(grade: 7))
        XCTAssertEqual(Set(WeatheringGrade.allCases.map(\.grade)), Set(1...6))
    }

    func testBothSeepageScalesAreNumberedOneToFive() {
        XCTAssertEqual(Set(UnfilledSeepageRating.allCases.map(\.rating)), Set(1...5))
        XCTAssertEqual(Set(FilledSeepageRating.allCases.map(\.rating)), Set(1...5))
        XCTAssertEqual(UnfilledSeepageRating(rating: 4), .seepage)
        XCTAssertEqual(FilledSeepageRating(rating: 3), .fillingWetWithOccasionalDrops)
        XCTAssertNil(UnfilledSeepageRating(rating: 6))
        XCTAssertNil(FilledSeepageRating(rating: 0))
    }

    /// The two scales share their numbers but not their meanings, so a stored reading
    /// has to say which table it came from. Rating III is "damp, no free water" on one
    /// and "filling wet, occasional drops" on the other.
    func testSeepageObservationCarriesWhichScaleWasUsed() {
        let unfilled = SeepageObservation.unfilled(.damp)
        let filled = SeepageObservation.filled(.fillingWetWithOccasionalDrops)

        XCTAssertEqual(unfilled.rating, 3)
        XCTAssertEqual(filled.rating, 3)
        XCTAssertEqual(unfilled.romanNumeral, "III")
        XCTAssertEqual(filled.romanNumeral, "III")
        XCTAssertNotEqual(unfilled, filled, "same number, different reading")

        XCTAssertFalse(unfilled.usesFilledScale)
        XCTAssertTrue(filled.usesFilledScale)
        XCTAssertEqual(unfilled.qualifiedDescription, "III (unfilled)")
        XCTAssertEqual(filled.qualifiedDescription, "III (filled)")
    }

    func testSeepageObservationSurvivesStorage() throws {
        let values: [SeepageObservation] = [
            .unfilled(.tightAndDry), .unfilled(.continuousFlow),
            .filled(.fillingConsolidatedAndDry), .filled(.fillingWashedOutWithHeavyFlow)
        ]
        for value in values {
            let data = try JSONEncoder().encode(value)
            XCTAssertEqual(try JSONDecoder().decode(SeepageObservation.self, from: data), value)
        }
    }

    func testTerminationCodes() {
        XCTAssertEqual(TerminationType.extendsBeyondExposure.code, "x")
        XCTAssertEqual(TerminationType.terminatesInRock.code, "r")
        XCTAssertEqual(TerminationType.terminatesAgainstDiscontinuity.code, "d")
        XCTAssertEqual(TerminationType(code: "R"), .terminatesInRock)
        XCTAssertNil(TerminationType(code: "q"))
        XCTAssertEqual(Set(TerminationType.allCases.map(\.code)).count, 3)
    }

    /// A JRC outside the chart is a typing error, and rejecting it is the point: clamped
    /// to 20 it would look like a measurement of the roughest surface on the chart.
    func testJointRoughnessCoefficientRange() {
        XCTAssertEqual(JointRoughnessCoefficient(0)?.value, 0)
        XCTAssertEqual(JointRoughnessCoefficient(20)?.value, 20)
        XCTAssertEqual(JointRoughnessCoefficient(12)?.value, 12)
        XCTAssertNil(JointRoughnessCoefficient(-1))
        XCTAssertNil(JointRoughnessCoefficient(21))
        XCTAssertNil(JointRoughnessCoefficient(25))
    }

    /// `InfillingMaterial.clean` is not called `none`, so that an optional cannot
    /// silently swallow it.
    func testUnfilledDiscontinuityIsDistinctFromNoRecord() {
        let recorded: Infilling? = Infilling.clean
        let notRecorded: Infilling? = nil
        XCTAssertNotNil(recorded)
        XCTAssertNil(notRecorded)
        XCTAssertEqual(recorded?.material, .clean)
    }
}

/// Measured and estimated observations must stay distinguishable.
final class ObservationTests: XCTestCase {

    func testMeasuredObservationCarriesBothTheValueAndTheClass() {
        let aperture = ApertureObservation.measured(millimetres: 3)
        XCTAssertEqual(aperture.millimetres, 3)
        XCTAssertEqual(aperture.apertureClass, .moderatelyWide)
        XCTAssertTrue(aperture.wasMeasured)
    }

    /// The distinction worth keeping: an eyeballed class has no number, and inventing one
    /// would put a guess into a DFN model as though someone had put a ruler on it.
    func testEstimatedObservationHasNoMeasuredValue() {
        let aperture = ApertureObservation.estimated(.moderatelyWide)
        XCTAssertNil(aperture.millimetres)
        XCTAssertEqual(aperture.apertureClass, .moderatelyWide)
        XCTAssertFalse(aperture.wasMeasured)
    }

    func testAnOutOfRangeMeasurementHasNoClass() {
        XCTAssertNil(ApertureObservation.measured(millimetres: -1).apertureClass)
        XCTAssertNil(SpacingObservation.measured(millimetres: .nan).spacingClass)
    }

    func testPersistenceAndSpacingBehaveTheSameWay() {
        XCTAssertEqual(PersistenceObservation.measured(metres: 5).persistenceClass, .medium)
        XCTAssertEqual(PersistenceObservation.measured(metres: 5).metres, 5)
        XCTAssertNil(PersistenceObservation.estimated(.high).metres)
        XCTAssertEqual(SpacingObservation.measured(millimetres: 150).spacingClass, .close)
        XCTAssertNil(SpacingObservation.estimated(.wide).millimetres)
    }

    func testObservationsSurviveStorage() throws {
        let values: [ApertureObservation] = [.measured(millimetres: 1.5), .estimated(.cavernous)]
        for value in values {
            let data = try JSONEncoder().encode(value)
            XCTAssertEqual(try JSONDecoder().decode(ApertureObservation.self, from: data), value)
        }
    }

    func testDescriptionCountsWhatHasBeenFilledIn() {
        XCTAssertTrue(DiscontinuityDescription.empty.isEmpty)
        XCTAssertEqual(DiscontinuityDescription.empty.completedFieldCount, 0)

        var description = DiscontinuityDescription()
        description.weathering = .moderatelyWeathered
        description.jrc = JointRoughnessCoefficient(8)
        description.spacing = .measured(millimetres: 150)
        XCTAssertFalse(description.isEmpty)
        XCTAssertEqual(description.completedFieldCount, 3)

        let full = DiscontinuityDescription(
            roughness: RoughnessClass(profile: .rough, waviness: .undulating),
            jrc: JointRoughnessCoefficient(10),
            aperture: .measured(millimetres: 0.3),
            infilling: .clean,
            weathering: .slightlyWeathered,
            seepage: .damp,
            persistence: .measured(metres: 4),
            spacing: .measured(millimetres: 300),
            termination: .terminatesInRock
        )
        XCTAssertEqual(full.completedFieldCount, DiscontinuityDescription.fieldCount)
    }
}
