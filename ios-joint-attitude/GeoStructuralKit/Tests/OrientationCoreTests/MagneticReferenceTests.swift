import XCTest
@testable import OrientationCore

final class MagneticReferenceTests: XCTestCase {

    /// `true = magnetic + declination`, declination positive east. Taiwan is about
    /// −4°, so a feature at true 000 reads 004 on a magnetic compass.
    func testTaiwanDeclination() {
        let taiwan = MagneticDeclination(degreesEast: -4)
        let plane = PlaneOrientation(dip: 45, dipDirection: 0)
        let magnetic = plane.inMagneticNorthFrame(declination: taiwan)
        XCTAssertAzimuthEqual(magnetic.dipDirection, 4, accuracy: 1e-9)
        XCTAssertEqual(magnetic.dip, 45, accuracy: 1e-12, "declination must not touch the dip")
    }

    func testEastAndWestDeclinationGoOppositeWays() {
        let east = MagneticDeclination(degreesEast: 10)
        let west = MagneticDeclination(degreesEast: -10)
        let plane = PlaneOrientation(dip: 30, dipDirection: 90)
        XCTAssertAzimuthEqual(plane.inMagneticNorthFrame(declination: east).dipDirection, 80, accuracy: 1e-9)
        XCTAssertAzimuthEqual(plane.inMagneticNorthFrame(declination: west).dipDirection, 100, accuracy: 1e-9)
    }

    func testRoundTripAcrossTheNorthWrap() {
        let declination = MagneticDeclination(degreesEast: 10)
        for dipDirection in [0.0, 5, 90, 180, 355, 359] {
            let plane = PlaneOrientation(dip: 55, dipDirection: dipDirection)
            let there = plane.inMagneticNorthFrame(declination: declination)
            let back = there.inTrueNorthFrame(declination: declination)
            XCTAssertAzimuthEqual(back.dipDirection, dipDirection, accuracy: 1e-9)
            XCTAssertEqual(back.dip, 55, accuracy: 1e-12)
        }
    }

    func testLineationsConvertTheSameWay() {
        let declination = MagneticDeclination(degreesEast: -4)
        let line = LineOrientation(trend: 2, plunge: 30)
        let magnetic = line.inMagneticNorthFrame(declination: declination)
        XCTAssertAzimuthEqual(magnetic.trend, 6, accuracy: 1e-9)
        XCTAssertEqual(magnetic.plunge, 30, accuracy: 1e-12)
        XCTAssertAzimuthEqual(
            magnetic.inTrueNorthFrame(declination: declination).trend, 2, accuracy: 1e-9
        )
    }

    /// The declination the device itself implies, from one `CLHeading`'s pair of
    /// headings for the same direction.
    func testDeclinationDerivedFromAHeadingPair() {
        XCTAssertEqual(
            MagneticDeclination(trueHeading: 0, magneticHeading: 4).degreesEast,
            -4, accuracy: 1e-9
        )
        XCTAssertEqual(
            MagneticDeclination(trueHeading: 350, magneticHeading: 340).degreesEast,
            10, accuracy: 1e-9
        )
        // Across the north wrap, where a plain subtraction would give 350 instead of −10.
        XCTAssertEqual(
            MagneticDeclination(trueHeading: 355, magneticHeading: 5).degreesEast,
            -10, accuracy: 1e-9
        )
    }

    func testZeroDeclinationChangesNothing() {
        let plane = PlaneOrientation(dip: 37, dipDirection: 214)
        XCTAssertEqual(plane.inMagneticNorthFrame(declination: .zero), plane)
        XCTAssertEqual(plane.inTrueNorthFrame(declination: .zero), plane)
    }
}

final class AttitudeConventionTests: XCTestCase {

    func testReinterpretingAPoleAzimuthFlipsTheDipDirectionOnly() {
        let asRecorded = PlaneOrientation(dip: 45, dipDirection: 90)
        let corrected = asRecorded.reinterpretingDipDirectionAsPoleAzimuth
        XCTAssertEqual(corrected.dip, 45, accuracy: 1e-12)
        XCTAssertAzimuthEqual(corrected.dipDirection, 270, accuracy: 1e-12)
        // It names a different plane, which is the point: the record was mislabelled.
        XCTAssertEqual(corrected.angle(to: asRecorded), 90, accuracy: 1e-9)
        // Applying it twice returns the original.
        XCTAssertEqual(corrected.reinterpretingDipDirectionAsPoleAzimuth, asRecorded)
    }

    func testConventionVersionIsStamped() {
        XCTAssertEqual(AttitudeConvention.version, 2)
    }
}

final class DevicePlacementTests: XCTestCase {

    /// Each placement reads the axis that points out of the rock for it.
    func testPlacementsMapToTheOutwardNormal() {
        XCTAssertEqual(DevicePlacement.backOnFace.outwardNormalAxis, .plusZ)
        XCTAssertEqual(DevicePlacement.screenOnFace.outwardNormalAxis, .minusZ)
        XCTAssertEqual(DevicePlacement.leftSideOnFace.outwardNormalAxis, .minusX)
        XCTAssertEqual(DevicePlacement.rightSideOnFace.outwardNormalAxis, .plusX)
        XCTAssertEqual(DevicePlacement.bottomEdgeOnFace.outwardNormalAxis, .minusY)
        XCTAssertEqual(DevicePlacement.topEdgeOnFace.outwardNormalAxis, .plusY)

        // Opposite placements read opposite faces of the same plane, so they must
        // give the same attitude.
        let attitude = deviceAttitude(placingZAxisAlong: Vector3(0.3, 0.2, 0.93), spin: 71)
        XCTAssertEqual(
            DeviceAttitude.plane(from: attitude, placement: .backOnFace)!,
            DeviceAttitude.plane(from: attitude, placement: .screenOnFace)!
        )
        XCTAssertEqual(
            DeviceAttitude.plane(from: attitude, placement: .leftSideOnFace)!,
            DeviceAttitude.plane(from: attitude, placement: .rightSideOnFace)!
        )
    }

    /// The long edges of the phone run bottom-to-top, so they lie along `y`; the
    /// short edges run across it, along `x`.
    func testEdgesMapToTheAxisAlongThem() {
        XCTAssertEqual(DeviceEdge.leftEdge.axis, .plusY)
        XCTAssertEqual(DeviceEdge.rightEdge.axis, .plusY)
        XCTAssertEqual(DeviceEdge.topEdge.axis, .plusX)
        XCTAssertEqual(DeviceEdge.bottomEdge.axis, .plusX)
    }

    /// Laying the left edge along a lineation and laying the right edge along it are
    /// the same measurement — the phone is just the other way up, and a lineation is
    /// axial.
    func testLeftAndRightEdgesGiveTheSameLineation() {
        for trend in [0.0, 47, 150, 280] {
            for plunge in [5.0, 35, 70] {
                let attitude = deviceAttitude(forLineTrend: trend, plunge: plunge, roll: 23)
                let left = DeviceAttitude.line(from: attitude, edge: .leftEdge)!
                let right = DeviceAttitude.line(from: attitude, edge: .rightEdge)!
                XCTAssertEqual(left, right)
                XCTAssertEqual(left.plunge, plunge, accuracy: requiredAccuracyDegrees)
                XCTAssertAzimuthEqual(left.trend, trend, accuracy: requiredAccuracyDegrees)
            }
        }
    }

    /// The short edges lie 90° from the long ones, so they read a different line.
    func testShortEdgeReadsADifferentLineFromTheLongEdge() {
        let attitude = deviceAttitude(forLineTrend: 120, plunge: 40, roll: 0)
        let long = DeviceAttitude.line(from: attitude, edge: .leftEdge)!
        let short = DeviceAttitude.line(from: attitude, edge: .bottomEdge)!
        XCTAssertEqual(long.angle(to: short), 90, accuracy: 1e-9)
    }
}
