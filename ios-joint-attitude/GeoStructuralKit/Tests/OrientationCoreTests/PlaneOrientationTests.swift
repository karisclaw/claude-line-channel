import XCTest
@testable import OrientationCore

/// A1 — the contact-method attitude conversion.
final class PlaneOrientationTests: XCTestCase {

    // MARK: - The specified round-trip accuracy requirement

    /// Synthesizes a device attitude for a known plane, converts it back, and
    /// requires better than 0.01° on both components — the project's stated bar.
    ///
    /// Every case is repeated at four phone rolls about the face normal, because a
    /// geologist holds the phone whichever way is comfortable against the rock.
    func testRoundTripFromSynthesizedAttitudeMeetsAccuracyRequirement() {
        let dips = [0.0, 5, 15, 30, 45, 60, 75, 89, 90]
        let dipDirections = [0.0, 45, 90, 135, 180, 225, 270, 315, 359]
        let spins = [0.0, 37, 155, 291]

        for dip in dips {
            for dipDirection in dipDirections {
                for spin in spins {
                    let attitude = deviceAttitude(forPlaneDip: dip, dipDirection: dipDirection, spin: spin)
                    guard let plane = DeviceAttitude.plane(from: attitude) else {
                        return XCTFail("conversion failed for \(dip)/\(dipDirection) spin \(spin)")
                    }
                    XCTAssertEqual(
                        plane.dip, dip, accuracy: requiredAccuracyDegrees,
                        "dip wrong for \(dip)/\(dipDirection) at spin \(spin)"
                    )
                    // A horizontal plane has no dip direction to recover.
                    if dip >= OrientationTolerance.nearHorizontalDip {
                        XCTAssertAzimuthEqual(
                            plane.dipDirection, dipDirection, accuracy: requiredAccuracyDegrees,
                            "at \(dip)/\(dipDirection) spin \(spin)"
                        )
                    }
                }
            }
        }
    }

    /// The conversion must not depend on how the phone is rolled about the normal.
    func testResultIsInvariantUnderPhoneRollAboutTheFaceNormal() {
        let reference = DeviceAttitude.plane(from: deviceAttitude(forPlaneDip: 52, dipDirection: 137, spin: 0))!
        for spin in stride(from: 0.0, to: 360.0, by: 11.0) {
            let plane = DeviceAttitude.plane(from: deviceAttitude(forPlaneDip: 52, dipDirection: 137, spin: spin))!
            XCTAssertEqual(plane.dip, reference.dip, accuracy: 1e-9)
            XCTAssertAzimuthEqual(plane.dipDirection, reference.dipDirection, accuracy: 1e-9)
        }
    }

    // MARK: - Physical ground truth

    /// The upward normal of a plane leans *toward* the dip direction, not away from
    /// it: an east-facing slope faces east. This test pins the sign that the whole
    /// module depends on.
    func testUpwardNormalLeansTowardTheDipDirection() {
        // Surface described independently of the conversion code: up = -tan(30°)·east,
        // i.e. ground that descends toward the east. Its normal is (tan30, 0, 1) in
        // (east, north, up).
        let t = tan(GeoAngle.radians(fromDegrees: 30))
        let normal = Vector3(north: 0, east: t, up: 1)

        let plane = PlaneOrientation(measuredNormal: normal)!
        XCTAssertEqual(plane.dip, 30, accuracy: 1e-9)
        XCTAssertAzimuthEqual(plane.dipDirection, 90, accuracy: 1e-9)
    }

    func testPhoneLyingFlatReadsAsHorizontal() {
        let plane = DeviceAttitude.plane(from: .identity)!
        XCTAssertEqual(plane.dip, 0, accuracy: 1e-12)
        XCTAssertFalse(plane.isDipDirectionWellDefined)
    }

    func testCardinalFacingDirections() {
        let cases: [(Vector3, Double, Double)] = [
            (Vector3(north: sin(GeoAngle.radians(fromDegrees: 20)), east: 0, up: cos(GeoAngle.radians(fromDegrees: 20))), 20, 0),
            (Vector3(north: 0, east: sin(GeoAngle.radians(fromDegrees: 30)), up: cos(GeoAngle.radians(fromDegrees: 30))), 30, 90),
            (Vector3(north: -sin(GeoAngle.radians(fromDegrees: 55)), east: 0, up: cos(GeoAngle.radians(fromDegrees: 55))), 55, 180),
            (Vector3(north: 0, east: -sin(GeoAngle.radians(fromDegrees: 70)), up: cos(GeoAngle.radians(fromDegrees: 70))), 70, 270)
        ]
        for (normal, dip, dipDirection) in cases {
            let plane = PlaneOrientation(measuredNormal: normal)!
            XCTAssertEqual(plane.dip, dip, accuracy: 1e-9)
            XCTAssertAzimuthEqual(plane.dipDirection, dipDirection, accuracy: 1e-9)
        }
    }

    // MARK: - Strike

    func testStrikeFollowsTheRightHandRule() {
        // Looking along strike, the plane dips to the right, so dip direction is
        // strike + 90.
        XCTAssertEqual(PlaneOrientation(dip: 30, dipDirection: 90).strike, 0, accuracy: 1e-12)
        XCTAssertEqual(PlaneOrientation(dip: 30, dipDirection: 0).strike, 270, accuracy: 1e-12)
        XCTAssertEqual(PlaneOrientation(dip: 45, dipDirection: 45).strike, 315, accuracy: 1e-12)

        for dipDirection in stride(from: 0.0, to: 360.0, by: 7.0) {
            let plane = PlaneOrientation(dip: 40, dipDirection: dipDirection)
            XCTAssertAzimuthEqual(plane.strike, dipDirection - 90, accuracy: 1e-12)
            XCTAssertLessThan(plane.strikeAxis, 180)
        }
    }

    func testStrikeAndDipInitializerRoundTrips() {
        for strike in stride(from: 0.0, to: 360.0, by: 13.0) {
            let plane = PlaneOrientation(rightHandRuleStrike: strike, dip: 62)
            XCTAssertEqual(plane.dip, 62, accuracy: 1e-12)
            XCTAssertAzimuthEqual(plane.strike, strike, accuracy: 1e-12)
        }
    }

    // MARK: - Which face was measured

    /// Measuring the underside of an overhanging face gives a downward normal. The
    /// plane is the same plane, so the reported attitude must be identical.
    func testMeasuringEitherFaceGivesTheSameAttitude() {
        for dip in [10.0, 35, 60, 80] {
            for dipDirection in [15.0, 120, 300] {
                let normal = PlaneOrientation(dip: dip, dipDirection: dipDirection).upwardNormal
                let fromAbove = PlaneOrientation(measuredNormal: normal)!
                let fromBelow = PlaneOrientation(measuredNormal: -normal)!
                XCTAssertEqual(fromAbove.dip, fromBelow.dip, accuracy: 1e-9)
                XCTAssertAzimuthEqual(fromAbove.dipDirection, fromBelow.dipDirection, accuracy: 1e-9)
            }
        }
    }

    // MARK: - Degenerate attitudes

    /// The dip direction of a horizontal plane is undefined and must be flagged, not
    /// reported as though the sensor knew it.
    func testHorizontalPlaneFlagsItsDipDirectionAsUndefined() {
        let plane = PlaneOrientation(measuredNormal: Vector3(0, 0, 1))!
        XCTAssertEqual(plane.dip, 0, accuracy: 1e-12)
        XCTAssertFalse(plane.isDipDirectionWellDefined)

        let slight = PlaneOrientation(dip: 3, dipDirection: 200)
        XCTAssertTrue(slight.isDipDirectionWellDefined)
    }

    /// On a vertical face the up/down sign of the normal is sensor noise. The
    /// reported dip direction must not flip 180° as that noise changes sign.
    func testVerticalPlaneDipDirectionIsStableAgainstNoiseOnTheVerticalComponent() {
        for dipDirection in [0.0, 90, 180, 270] {
            let normal = PlaneOrientation(dip: 90, dipDirection: dipDirection).upwardNormal
            for epsilon in [1e-9, -1e-9, 1e-6, -1e-6] {
                let noisy = Vector3(normal.x, normal.y, normal.z + epsilon)
                let plane = PlaneOrientation(measuredNormal: noisy)!
                XCTAssertEqual(plane.dip, 90, accuracy: 1e-3)
                XCTAssertAzimuthEqual(
                    plane.dipDirection, dipDirection, accuracy: 1e-3,
                    "vertical dip direction flipped under noise \(epsilon)"
                )
            }
        }
    }

    /// The two faces of a vertical plane legitimately report dip directions 180°
    /// apart. Both are correct; the ambiguity is flagged so the UI can offer a
    /// toggle instead of silently picking one.
    func testVerticalPlaneReportsTheFaceThatWasMeasuredAndFlagsTheAmbiguity() {
        let eastFacing = PlaneOrientation(dip: 90, dipDirection: 90)
        let westFacing = PlaneOrientation(measuredNormal: -eastFacing.upwardNormal)!

        XCTAssertAzimuthEqual(eastFacing.dipDirection, 90, accuracy: 1e-9)
        XCTAssertAzimuthEqual(westFacing.dipDirection, 270, accuracy: 1e-9)
        XCTAssertTrue(eastFacing.isDipDirectionAmbiguous)
        XCTAssertTrue(westFacing.isDipDirectionAmbiguous)
        XCTAssertAzimuthEqual(eastFacing.oppositeFaceDescription.dipDirection, 270, accuracy: 1e-9)
        XCTAssertEqual(eastFacing.angle(to: westFacing), 0, accuracy: 1e-9)
    }

    /// The dip direction stays continuous as a face steepens through vertical, so
    /// the number on screen does not jump while the geologist is holding the phone.
    func testDipDirectionIsContinuousApproachingVertical() {
        for dip in [88.0, 89, 89.4, 89.6, 90] {
            let plane = PlaneOrientation(dip: dip, dipDirection: 90)
            let recovered = PlaneOrientation(measuredNormal: plane.upwardNormal)!
            XCTAssertEqual(recovered.dip, dip, accuracy: 1e-9)
            XCTAssertAzimuthEqual(recovered.dipDirection, 90, accuracy: 1e-9)
        }
    }

    func testDipsPastVerticalAreFoldedOntoTheOppositeFace() {
        let folded = PlaneOrientation(dip: 100, dipDirection: 90)
        XCTAssertEqual(folded.dip, 80, accuracy: 1e-12)
        XCTAssertAzimuthEqual(folded.dipDirection, 270, accuracy: 1e-12)

        let negative = PlaneOrientation(dip: -30, dipDirection: 0)
        XCTAssertEqual(negative.dip, 30, accuracy: 1e-12)
        XCTAssertAzimuthEqual(negative.dipDirection, 180, accuracy: 1e-12)
    }

    func testDegenerateNormalIsRejected() {
        XCTAssertNil(PlaneOrientation(measuredNormal: .zero))
        XCTAssertNil(PlaneOrientation(measuredNormal: Vector3(.nan, 0, 0)))
    }

    // MARK: - Derived vectors

    func testNormalDipVectorAndStrikeVectorFormAnOrthonormalTriad() {
        for dip in [0.0, 15, 45, 75, 90] {
            for dipDirection in [0.0, 77, 200, 333] {
                let plane = PlaneOrientation(dip: dip, dipDirection: dipDirection)
                let n = plane.upwardNormal, d = plane.dipVector, s = plane.strikeVector
                XCTAssertEqual(n.length, 1, accuracy: 1e-12)
                XCTAssertEqual(d.length, 1, accuracy: 1e-12)
                XCTAssertEqual(s.length, 1, accuracy: 1e-12)
                XCTAssertEqual(n.dot(d), 0, accuracy: 1e-12)
                XCTAssertEqual(n.dot(s), 0, accuracy: 1e-12)
                XCTAssertEqual(d.dot(s), 0, accuracy: 1e-12)
            }
        }
    }

    func testDipVectorPointsDownslopeAndPoleIsTheDownwardNormal() {
        let plane = PlaneOrientation(dip: 40, dipDirection: 120)
        XCTAssertLessThan(plane.dipVector.up, 0)
        XCTAssertAzimuthEqual(plane.dipVector.azimuth!, 120, accuracy: 1e-9)
        XCTAssertVectorEqual(plane.pole, -plane.upwardNormal)
        XCTAssertLessThan(plane.pole.up, 0)
        // The lower-hemisphere pole plots opposite the dip direction on a stereonet.
        XCTAssertAzimuthEqual(plane.pole.azimuth!, 300, accuracy: 1e-9)
    }

    func testDipLineAndStrikeLine() {
        let plane = PlaneOrientation(dip: 35, dipDirection: 210)
        XCTAssertEqual(plane.dipLine.plunge, 35, accuracy: 1e-9)
        XCTAssertAzimuthEqual(plane.dipLine.trend, 210, accuracy: 1e-9)
        XCTAssertEqual(plane.strikeLine.plunge, 0, accuracy: 1e-9)
        XCTAssertAzimuthEqual(plane.strikeLine.trend, 120, accuracy: 1e-9)
    }

    // MARK: - Relations between planes

    func testApparentDip() {
        let plane = PlaneOrientation(dip: 45, dipDirection: 0)
        XCTAssertEqual(plane.apparentDip(inVerticalSectionAlong: 0), 45, accuracy: 1e-9)
        XCTAssertEqual(plane.apparentDip(inVerticalSectionAlong: 90), 0, accuracy: 1e-9)
        XCTAssertEqual(plane.apparentDip(inVerticalSectionAlong: 270), 0, accuracy: 1e-9)
        // tan(apparent) = tan(45°)·cos(60°) = 0.5
        XCTAssertEqual(plane.apparentDip(inVerticalSectionAlong: 60), 26.5650511771, accuracy: 1e-8)
        // Looking the other way, the same plane rises: the apparent dip is negative.
        XCTAssertEqual(plane.apparentDip(inVerticalSectionAlong: 240), -26.5650511771, accuracy: 1e-8)
        XCTAssertEqual(
            PlaneOrientation(dip: 60, dipDirection: 90).apparentDip(inVerticalSectionAlong: 135),
            50.7684795164, accuracy: 1e-8
        )
        // The apparent dip never exceeds the true dip.
        for trend in stride(from: 0.0, to: 360.0, by: 9.0) {
            XCTAssertLessThanOrEqual(abs(plane.apparentDip(inVerticalSectionAlong: trend)), 45 + 1e-9)
        }
    }

    func testDihedralAngleBetweenPlanes() {
        XCTAssertEqual(
            PlaneOrientation(dip: 45, dipDirection: 0).angle(to: PlaneOrientation(dip: 45, dipDirection: 180)),
            90, accuracy: 1e-9
        )
        XCTAssertEqual(
            PlaneOrientation(dip: 30, dipDirection: 90).angle(to: PlaneOrientation(dip: 60, dipDirection: 90)),
            30, accuracy: 1e-9
        )
        XCTAssertEqual(
            PlaneOrientation(dip: 0, dipDirection: 0).angle(to: PlaneOrientation(dip: 90, dipDirection: 0)),
            90, accuracy: 1e-9
        )
    }

    func testIntersectionOfTwoPlanes() {
        // Two vertical planes meet in a vertical line.
        let vertical = PlaneOrientation(dip: 90, dipDirection: 0)
            .intersection(with: PlaneOrientation(dip: 90, dipDirection: 90))!
        XCTAssertEqual(vertical.plunge, 90, accuracy: 1e-9)
        XCTAssertFalse(vertical.isTrendWellDefined)

        // Planes dipping north and south meet in a horizontal east-west line.
        let horizontal = PlaneOrientation(dip: 45, dipDirection: 0)
            .intersection(with: PlaneOrientation(dip: 45, dipDirection: 180))!
        XCTAssertEqual(horizontal.plunge, 0, accuracy: 1e-9)
        XCTAssertEqual(GeoAngle.axialAzimuthSeparation(horizontal.trend, 90), 0, accuracy: 1e-9)

        // Parallel planes have no intersection line.
        XCTAssertNil(
            PlaneOrientation(dip: 30, dipDirection: 45)
                .intersection(with: PlaneOrientation(dip: 30, dipDirection: 45))
        )
    }

    func testFieldShorthandDescription() {
        XCTAssertEqual(PlaneOrientation(dip: 45, dipDirection: 90).description, "45/090")
        XCTAssertEqual(PlaneOrientation(dip: 8, dipDirection: 5).description, "08/005")
        XCTAssertEqual(PlaneOrientation(dip: 45, dipDirection: 359.7).description, "45/000")
    }
}
