import XCTest
@testable import OrientationCore

/// A2 — magnetic interference flagging.
final class MagneticEnvironmentTests: XCTestCase {

    private func assess(
        strength: Double?, accuracy: MagneticFieldAccuracy, heading: Double?
    ) -> MagneticAssessment {
        MagneticAssessment.assess(
            MagneticEnvironment(fieldStrength: strength, accuracy: accuracy, headingAccuracy: heading)
        )
    }

    func testAnUndisturbedReadingIsGood() {
        let good = assess(strength: 48, accuracy: .high, heading: 5)
        XCTAssertEqual(good.verdict, .good)
        XCTAssertTrue(good.reasons.isEmpty)
        XCTAssertFalse(good.isDisturbed)
        XCTAssertEqual(assess(strength: 48, accuracy: .medium, heading: nil).verdict, .good)
    }

    /// Field strength off the undisturbed range means something local is adding to it:
    /// magnetite in the rock, basic igneous rock, rebar, a guardrail, a parked vehicle.
    func testFieldStrengthOutsideTheEarthRangeIsDisturbed() {
        for strength in [120.0, 24.9, 65.1, 5.0] {
            let assessment = assess(strength: strength, accuracy: .high, heading: 5)
            XCTAssertEqual(assessment.verdict, .disturbed, "at \(strength) µT")
            XCTAssertTrue(assessment.reasons.contains(.fieldStrengthOutsideEarthRange))
        }
        // The range is inclusive at both ends.
        XCTAssertEqual(assess(strength: 25, accuracy: .high, heading: 5).verdict, .good)
        XCTAssertEqual(assess(strength: 65, accuracy: .high, heading: 5).verdict, .good)
    }

    /// The project rule: `.low` and `.uncalibrated` both raise the warning.
    func testPoorMagnetometerCalibrationIsDisturbed() {
        let low = assess(strength: 48, accuracy: .low, heading: 5)
        XCTAssertEqual(low.verdict, .disturbed)
        XCTAssertTrue(low.reasons.contains(.magnetometerPoorlyCalibrated))

        let uncalibrated = assess(strength: 48, accuracy: .uncalibrated, heading: 5)
        XCTAssertEqual(uncalibrated.verdict, .disturbed)
        XCTAssertTrue(uncalibrated.reasons.contains(.magnetometerUncalibrated))
    }

    /// CoreLocation reports an unusable heading as a negative accuracy, which is easy to
    /// treat as a very good one by accident.
    func testNegativeHeadingAccuracyMeansInvalidNotExcellent() {
        let assessment = assess(strength: 48, accuracy: .high, heading: -1)
        XCTAssertEqual(assessment.verdict, .disturbed)
        XCTAssertTrue(assessment.reasons.contains(.headingInvalid))
    }

    func testHeadingAccuracyGrades() {
        XCTAssertEqual(assess(strength: 48, accuracy: .high, heading: 9).verdict, .good)
        XCTAssertEqual(assess(strength: 48, accuracy: .high, heading: 15).verdict, .marginal)
        XCTAssertEqual(assess(strength: 48, accuracy: .high, heading: 25).verdict, .disturbed)
    }

    func testMissingFieldStrengthIsMarginalNotGood() {
        let assessment = assess(strength: nil, accuracy: .high, heading: 5)
        XCTAssertEqual(assessment.verdict, .marginal)
        XCTAssertTrue(assessment.reasons.contains(.fieldStrengthUnknown))
    }

    func testTheWorstReasonSetsTheVerdict() {
        let assessment = assess(strength: 120, accuracy: .high, heading: 15)
        XCTAssertEqual(assessment.verdict, .disturbed, "marginal heading must not soften a bad field")
        XCTAssertEqual(assessment.reasons.count, 2)
    }

    /// The point worth putting on screen: a magnetic warning costs the azimuth, not the
    /// dip. Dip comes from gravity, which magnetite cannot bend.
    func testAWarningAffectsAzimuthOnly() {
        XCTAssertTrue(assess(strength: 120, accuracy: .low, heading: 30).affectsAzimuthOnly)
    }

    func testEnvironmentSurvivesStorage() throws {
        let environment = MagneticEnvironment(fieldStrength: 47.5, accuracy: .medium, headingAccuracy: 8)
        let data = try JSONEncoder().encode(environment)
        XCTAssertEqual(try JSONDecoder().decode(MagneticEnvironment.self, from: data), environment)
        // The raw values match CMMagneticFieldCalibrationAccuracy.
        XCTAssertEqual(MagneticFieldAccuracy.uncalibrated.rawValue, -1)
        XCTAssertEqual(MagneticFieldAccuracy.low.rawValue, 0)
        XCTAssertEqual(MagneticFieldAccuracy.medium.rawValue, 1)
        XCTAssertEqual(MagneticFieldAccuracy.high.rawValue, 2)
    }
}

/// A2 — calibration checks.
final class CalibrationCheckTests: XCTestCase {

    func testHorizontalCheckReportsTiltOnly() {
        let result = CalibrationCheck.againstHorizontal(PlaneOrientation(dip: 0.4, dipDirection: 210))
        XCTAssertEqual(result.tiltError, 0.4, accuracy: 1e-12)
        XCTAssertNil(result.azimuthError, "a horizontal plane has no azimuth to check")
        XCTAssertEqual(result.totalError, 0.4, accuracy: 1e-12)
        XCTAssertTrue(result.isWithin(1))
        XCTAssertFalse(result.isWithin(0.2))
    }

    func testVerticalCheckWithoutAKnownFacingReportsDeviationFromVertical() {
        let result = CalibrationCheck.againstVertical(PlaneOrientation(dip: 88.5, dipDirection: 0))
        XCTAssertEqual(result.tiltError, 1.5, accuracy: 1e-12)
        XCTAssertNil(result.azimuthError)
        XCTAssertEqual(result.totalError, 1.5, accuracy: 1e-12)
    }

    func testVerticalCheckAgainstAKnownWallChecksTheAzimuthToo() {
        let result = CalibrationCheck.againstVertical(
            PlaneOrientation(dip: 89, dipDirection: 97), facing: 90
        )
        XCTAssertEqual(result.tiltError, 1, accuracy: 1e-9)
        XCTAssertEqual(result.azimuthError!, 7, accuracy: 1e-9)
    }

    /// The split is the whole point: a tiny tilt error with a large azimuth error says
    /// the magnetometer is the problem, not the instrument as a whole.
    func testErrorIsSplitBetweenGravityAndMagnetometer() {
        let magnetic = CalibrationCheck.against(
            PlaneOrientation(dip: 45, dipDirection: 90),
            measured: PlaneOrientation(dip: 45, dipDirection: 95)
        )
        XCTAssertEqual(magnetic.tiltError, 0, accuracy: 1e-12, "gravity is fine")
        XCTAssertEqual(magnetic.azimuthError!, 5, accuracy: 1e-12)
        XCTAssertEqual(magnetic.totalError, 3.534973, accuracy: 1e-5)

        let tilt = CalibrationCheck.against(
            PlaneOrientation(dip: 45, dipDirection: 90),
            measured: PlaneOrientation(dip: 46, dipDirection: 90)
        )
        XCTAssertEqual(tilt.tiltError, 1, accuracy: 1e-12)
        XCTAssertEqual(tilt.azimuthError!, 0, accuracy: 1e-12)
        XCTAssertEqual(tilt.totalError, 1, accuracy: 1e-9)

        let both = CalibrationCheck.against(
            PlaneOrientation(dip: 45, dipDirection: 90),
            measured: PlaneOrientation(dip: 46, dipDirection: 95)
        )
        XCTAssertEqual(both.tiltError, 1, accuracy: 1e-12)
        XCTAssertEqual(both.azimuthError!, 5, accuracy: 1e-12)
        XCTAssertEqual(both.totalError, 3.703097, accuracy: 1e-5)
    }

    /// The azimuth error is signed and wraps, so a reference at 002 and a reading at 358
    /// are 4° apart, not 356°.
    func testAzimuthErrorIsSignedAndWraps() {
        let result = CalibrationCheck.against(
            PlaneOrientation(dip: 30, dipDirection: 2),
            measured: PlaneOrientation(dip: 30, dipDirection: 358)
        )
        XCTAssertEqual(result.azimuthError!, -4, accuracy: 1e-12)
    }

    func testPerfectCheckHasNoError() {
        let plane = PlaneOrientation(dip: 33, dipDirection: 147)
        let result = CalibrationCheck.against(plane, measured: plane)
        XCTAssertEqual(result.tiltError, 0, accuracy: 1e-12)
        XCTAssertEqual(result.azimuthError!, 0, accuracy: 1e-12)
        XCTAssertTrue(result.isWithin(1e-9))
    }
}

/// A2 — figure-of-eight coverage.
final class MagnetometerCoverageTests: XCTestCase {

    func testCoverageCountsOctants() {
        var coverage = MagnetometerCoverage()
        XCTAssertEqual(coverage.visitedOctants, 0)
        XCTAssertEqual(coverage.fraction, 0)
        XCTAssertFalse(coverage.isComplete)

        for x in [1.0, -1.0] {
            for y in [1.0, -1.0] {
                for z in [1.0, -1.0] {
                    coverage.add(deviceFrameDirection: Vector3(x * 0.5, y * 0.5, z * 0.5))
                }
            }
        }
        XCTAssertEqual(coverage.visitedOctants, 8)
        XCTAssertEqual(coverage.fraction, 1)
        XCTAssertTrue(coverage.isComplete)
    }

    func testRepeatedDirectionsDoNotInflateCoverage() {
        var coverage = MagnetometerCoverage()
        for _ in 0..<100 {
            coverage.add(deviceFrameDirection: Vector3(0.1, 0.2, 0.97))
        }
        XCTAssertEqual(coverage.visitedOctants, 1)
        XCTAssertEqual(coverage.fraction, 0.125, accuracy: 1e-12)
    }

    func testDegenerateDirectionsAreIgnored() {
        var coverage = MagnetometerCoverage()
        coverage.add(deviceFrameDirection: .zero)
        coverage.add(deviceFrameDirection: Vector3(.nan, 0, 0))
        XCTAssertEqual(coverage.visitedOctants, 0)
    }

    func testOctantIndexIsDistinctPerSignCombination() {
        var indices: Set<Int> = []
        for x in [1.0, -1.0] {
            for y in [1.0, -1.0] {
                for z in [1.0, -1.0] {
                    indices.insert(MagnetometerCoverage.octant(of: Vector3(x, y, z)))
                }
            }
        }
        XCTAssertEqual(indices.count, 8)
        XCTAssertEqual(MagnetometerCoverage.octant(of: Vector3(1, 1, 1)), 7)
        XCTAssertEqual(MagnetometerCoverage.octant(of: Vector3(-1, -1, -1)), 0)
    }

    func testResetClearsCoverage() {
        var coverage = MagnetometerCoverage()
        coverage.add(deviceFrameDirection: Vector3(1, 1, 1))
        coverage.reset()
        XCTAssertEqual(coverage.visitedOctants, 0)
    }
}

/// A2 — the placement cross-check. It warns; it never changes anything.
final class PlacementCrossCheckTests: XCTestCase {

    private func samples(_ accelerations: [Vector3]) -> [MotionSample] {
        accelerations.enumerated().map { index, acceleration in
            MotionSample(
                timestamp: Double(index) / 64,
                attitude: .identity,
                userAcceleration: acceleration
            )
        }
    }

    func testAPressAlongTheScreenAxisImpliesTheBackWasUsed() {
        let verdict = PlacementCrossCheck.assess(
            contactImpulse: samples([
                Vector3(0.01, 0.01, -0.4),
                Vector3(0.02, -0.01, -0.9),
                Vector3(0.0, 0.01, -0.5),
                Vector3(0.01, 0.0, -0.1)
            ]),
            selected: .backOnFace
        )
        XCTAssertEqual(verdict.impliedAxis, .z)
        XCTAssertEqual(verdict.selectedAxis, .z)
        XCTAssertFalse(verdict.disagrees)
        XCTAssertTrue(verdict.hasOpinion)
        XCTAssertGreaterThan(verdict.confidence, 0.99)
        XCTAssertEqual(verdict.peakAcceleration, 0.9, accuracy: 1e-3)
    }

    /// The case the whole thing exists for: the geologist left the selector on "back"
    /// but pressed the phone's left side against the rock.
    func testDisagreementIsReported() {
        let verdict = PlacementCrossCheck.assess(
            contactImpulse: samples([
                Vector3(0.7, 0.02, 0.01),
                Vector3(0.4, -0.01, 0.02),
                Vector3(0.1, 0.0, 0.0)
            ]),
            selected: .backOnFace
        )
        XCTAssertEqual(verdict.impliedAxis, .x)
        XCTAssertEqual(verdict.selectedAxis, .z)
        XCTAssertTrue(verdict.disagrees)
    }

    /// Placing the phone gently produces no impulse worth reading, and the check must
    /// stay quiet rather than invent an axis.
    func testGentlePlacementProducesNoOpinion() {
        let verdict = PlacementCrossCheck.assess(
            contactImpulse: samples([Vector3(0.01, 0, -0.03), Vector3(0, 0.01, -0.02)]),
            selected: .backOnFace
        )
        XCTAssertNil(verdict.impliedAxis)
        XCTAssertFalse(verdict.hasOpinion)
        XCTAssertFalse(verdict.disagrees, "no opinion is not a disagreement")
    }

    /// Sliding the phone into place, or hand tremor, spreads the impulse across all
    /// three axes. Below the confidence floor the check offers nothing.
    func testUndirectedImpulseProducesNoOpinion() {
        let verdict = PlacementCrossCheck.assess(
            contactImpulse: samples([Vector3(0.3, 0.31, 0.29), Vector3(0.28, 0.3, 0.32)]),
            selected: .backOnFace
        )
        XCTAssertNil(verdict.impliedAxis)
        XCTAssertLessThan(verdict.confidence, 0.4)
        XCTAssertGreaterThan(verdict.peakAcceleration, 0.15, "it was not a gentle placement")
    }

    func testEmptyWindowProducesNoOpinion() {
        let verdict = PlacementCrossCheck.assess(contactImpulse: [], selected: .leftSideOnFace)
        XCTAssertNil(verdict.impliedAxis)
        XCTAssertEqual(verdict.selectedAxis, .x)
        XCTAssertEqual(verdict.peakAcceleration, 0)
    }

    /// Opposite placements share an axis, so pressing the left side while "right side"
    /// is selected is not a disagreement — both give the same attitude.
    func testOppositePlacementsDoNotDisagree() {
        let impulse = samples([Vector3(0.7, 0.02, 0.01), Vector3(0.4, -0.01, 0.02)])
        for selected in [DevicePlacement.leftSideOnFace, .rightSideOnFace] {
            let verdict = PlacementCrossCheck.assess(contactImpulse: impulse, selected: selected)
            XCTAssertEqual(verdict.impliedAxis, .x)
            XCTAssertFalse(verdict.disagrees, "\(selected) is on the implied axis")
        }
    }

    /// There is deliberately no API that returns a corrected placement. The verdict
    /// carries what was selected and what the impulse implied, and nothing else.
    func testTheCheckOffersNoWayToOverrideTheSelection() {
        let verdict = PlacementCrossCheck.assess(
            contactImpulse: samples([Vector3(0.7, 0, 0), Vector3(0.5, 0, 0)]),
            selected: .backOnFace
        )
        XCTAssertEqual(verdict.selectedAxis, DevicePlacement.backOnFace.contactAxisPair)
        XCTAssertTrue(verdict.disagrees)
    }
}
