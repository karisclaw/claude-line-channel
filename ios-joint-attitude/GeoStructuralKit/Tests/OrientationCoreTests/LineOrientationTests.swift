import XCTest
@testable import OrientationCore

/// A1 — the linear-structure (trend / plunge) conversion.
final class LineOrientationTests: XCTestCase {

    /// The phone's bottom edge is laid along the lineation, so the device `-y` axis
    /// is the measured direction. Rolling the phone about that edge must not change
    /// the answer.
    func testRoundTripThroughTheDeviceMinusYAxis() {
        for trend in [0.0, 45, 90, 180, 270, 359] {
            for plunge in [0.0, 15, 45, 75, 90] {
                for roll in [0.0, 63, 200] {
                    let attitude = deviceAttitude(forLineTrend: trend, plunge: plunge, roll: roll)
                    guard let line = DeviceAttitude.line(from: attitude) else {
                        return XCTFail("conversion failed for \(plunge)->\(trend)")
                    }
                    XCTAssertEqual(
                        line.plunge, plunge, accuracy: requiredAccuracyDegrees,
                        "plunge wrong for \(plunge)->\(trend) roll \(roll)"
                    )
                    let truth = LineOrientation(trend: trend, plunge: plunge)
                    if plunge >= OrientationTolerance.nearHorizontalPlunge,
                       plunge <= 90 - OrientationTolerance.nearVerticalPlunge {
                        XCTAssertAzimuthEqual(
                            line.trend, trend, accuracy: requiredAccuracyDegrees,
                            "at \(plunge)->\(trend) roll \(roll)"
                        )
                    } else {
                        // A vertical line has no trend, and a horizontal one has two
                        // ends that are equally valid. The line itself must still come
                        // back. (1e-5: the floor of acos near an argument of 1.)
                        XCTAssertEqual(
                            line.angle(to: truth), 0, accuracy: 1e-5,
                            "recovered a different line at \(plunge)->\(trend) roll \(roll)"
                        )
                    }
                }
            }
        }
    }

    /// A lineation is axial: laying the phone along it "the other way round" is the
    /// same measurement.
    func testEitherEndOfTheLineGivesTheSameAttitude() {
        for trend in [10.0, 100, 250] {
            for plunge in [5.0, 40, 88] {
                let down = LineOrientation(trend: trend, plunge: plunge).downPlungeVector
                let a = LineOrientation(measuredAxis: down)!
                let b = LineOrientation(measuredAxis: -down)!
                XCTAssertEqual(a.plunge, b.plunge, accuracy: 1e-9)
                XCTAssertAzimuthEqual(a.trend, b.trend, accuracy: 1e-9)
            }
        }
    }

    func testNegativePlungeIsFoldedToTheOtherEnd() {
        let line = LineOrientation(trend: 0, plunge: -30)
        XCTAssertEqual(line.plunge, 30, accuracy: 1e-12)
        XCTAssertAzimuthEqual(line.trend, 180, accuracy: 1e-12)
    }

    func testVerticalLineFlagsItsTrendAsUndefined() {
        let vertical = LineOrientation(measuredAxis: Vector3(0, 0, -1))!
        XCTAssertEqual(vertical.plunge, 90, accuracy: 1e-12)
        XCTAssertFalse(vertical.isTrendWellDefined)
        XCTAssertTrue(LineOrientation(trend: 30, plunge: 20).isTrendWellDefined)
    }

    func testHorizontalLineFlagsItsTrendAsAmbiguous() {
        let horizontal = LineOrientation(trend: 45, plunge: 0)
        XCTAssertTrue(horizontal.isTrendAmbiguous)
        XCTAssertFalse(LineOrientation(trend: 45, plunge: 30).isTrendAmbiguous)
    }

    func testDownPlungeVectorPointsDownward() {
        let line = LineOrientation(trend: 145, plunge: 30)
        XCTAssertEqual(line.downPlungeVector.length, 1, accuracy: 1e-12)
        XCTAssertEqual(line.downPlungeVector.up, -0.5, accuracy: 1e-12)
        XCTAssertAzimuthEqual(line.downPlungeVector.azimuth!, 145, accuracy: 1e-9)
        XCTAssertVectorEqual(line.upPlungeVector, -line.downPlungeVector)
    }

    func testAngleBetweenLinesIsAxial() {
        let a = LineOrientation(trend: 0, plunge: 0)
        let b = LineOrientation(trend: 90, plunge: 0)
        XCTAssertEqual(a.angle(to: b), 90, accuracy: 1e-9)
        // 000 and 180 are the same horizontal line, not opposite lines.
        XCTAssertEqual(a.angle(to: LineOrientation(trend: 180, plunge: 0)), 0, accuracy: 1e-9)
    }

    func testAngleBetweenLineAndPlane() {
        let plane = PlaneOrientation(dip: 45, dipDirection: 90)
        XCTAssertEqual(plane.dipLine.angle(to: plane), 0, accuracy: 1e-9)
        XCTAssertEqual(plane.strikeLine.angle(to: plane), 0, accuracy: 1e-9)
        let normalLine = LineOrientation(measuredAxis: plane.upwardNormal)!
        XCTAssertEqual(normalLine.angle(to: plane), 90, accuracy: 1e-9)
    }

    func testPlaneContainsItsOwnDipAndStrikeLines() {
        let plane = PlaneOrientation(dip: 55, dipDirection: 305)
        XCTAssertTrue(plane.contains(plane.dipLine))
        XCTAssertTrue(plane.contains(plane.strikeLine))
        XCTAssertFalse(plane.contains(LineOrientation(measuredAxis: plane.upwardNormal)!))
    }

    /// Rake is measured in the plane, from the right-hand-rule strike direction.
    func testRakeInPlane() {
        let plane = PlaneOrientation(dip: 60, dipDirection: 90)
        XCTAssertEqual(plane.strikeLine.rake(in: plane)!, 0, accuracy: 1e-6)
        XCTAssertEqual(plane.dipLine.rake(in: plane)!, 90, accuracy: 1e-6)
        // A line normal to the plane does not lie in it.
        XCTAssertNil(LineOrientation(measuredAxis: plane.upwardNormal)!.rake(in: plane))
    }

    func testDegenerateAxisIsRejected() {
        XCTAssertNil(LineOrientation(measuredAxis: .zero))
        XCTAssertNil(LineOrientation(measuredAxis: Vector3(0, .infinity, 0)))
    }

    func testFieldShorthandDescription() {
        XCTAssertEqual(LineOrientation(trend: 145, plunge: 30).description, "30->145")
        XCTAssertEqual(LineOrientation(trend: 5, plunge: 8).description, "08->005")
    }
}
