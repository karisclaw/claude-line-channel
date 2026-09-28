import Foundation
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

    /// The outward normal points from the rock into the air, so it is the opposite of
    /// the axis the contacting face looks along.
    func testPlacementsMapToTheOutwardNormal() {
        XCTAssertEqual(DevicePlacement.backOnFace.outwardNormalAxis, .plusZ)
        XCTAssertEqual(DevicePlacement.screenOnFace.outwardNormalAxis, .minusZ)
        XCTAssertEqual(DevicePlacement.leftSideOnFace.outwardNormalAxis, .plusX)
        XCTAssertEqual(DevicePlacement.rightSideOnFace.outwardNormalAxis, .minusX)
        XCTAssertEqual(DevicePlacement.bottomEdgeOnFace.outwardNormalAxis, .plusY)
        XCTAssertEqual(DevicePlacement.topEdgeOnFace.outwardNormalAxis, .minusY)
    }

    /// The physical check the signs above have to survive: stand the phone on its
    /// left side on a horizontal surface. The rock is below, the air is above, so the
    /// outward normal of the face must point **up**.
    ///
    /// The attitude alone cannot catch a flipped sign here, because a plane's attitude
    /// is axial — which is exactly why this asserts the vector.
    func testOutwardNormalPointsAwayFromTheRockNotIntoIt() {
        // Phone standing on its left edge: device +x (right side) points to the zenith,
        // +y (top) points north, +z (screen) looks west.
        let standingOnLeftSide = Quaternion(
            deviceXInWorld: .upAxis, deviceYInWorld: .northAxis, deviceZInWorld: .westAxis
        )!
        let geometry = MeasurementGeometry(placement: .leftSideOnFace, edge: .leftEdge)
        let normal = geometry.outwardNormal(from: standingOnLeftSide)!
        XCTAssertGreaterThan(normal.up, 0.999, "the outward normal points into the rock")
        XCTAssertEqual(geometry.plane(from: standingOnLeftSide)!.dip, 0, accuracy: 1e-9)

        // Lying flat on its back on the same surface, the normal is up as well.
        let lyingOnBack = Quaternion.identity
        let onBack = MeasurementGeometry(placement: .backOnFace, edge: .leftEdge)
        XCTAssertGreaterThan(onBack.outwardNormal(from: lyingOnBack)!.up, 0.999)

        // Resting on its bottom edge on the same surface: device -y points down, so
        // the outward normal is +y, pointing up.
        let standingOnBottomEdge = Quaternion(
            deviceXInWorld: .northAxis, deviceYInWorld: .upAxis, deviceZInWorld: .eastAxis
        )!
        let onBottomEdge = MeasurementGeometry(placement: .bottomEdgeOnFace, edge: .leftEdge)
        XCTAssertGreaterThan(onBottomEdge.outwardNormal(from: standingOnBottomEdge)!.up, 0.999)
    }

    /// Opposite placements read opposite faces of the same plane, so the attitude is
    /// identical while the measured outward direction is reversed.
    func testOppositePlacementsAgreeOnTheAttitudeAndDisagreeOnTheDirection() {
        let attitude = deviceAttitude(placingZAxisAlong: Vector3(0.3, 0.2, 0.93), spin: 71)
        for (a, b) in [(DevicePlacement.backOnFace, DevicePlacement.screenOnFace),
                       (.leftSideOnFace, .rightSideOnFace),
                       (.bottomEdgeOnFace, .topEdgeOnFace)] {
            XCTAssertEqual(
                DeviceAttitude.plane(from: attitude, placement: a)!,
                DeviceAttitude.plane(from: attitude, placement: b)!
            )
            XCTAssertVectorEqual(
                MeasurementGeometry(placement: a, edge: .leftEdge).outwardNormal(from: attitude)!,
                -MeasurementGeometry(placement: b, edge: .leftEdge).outwardNormal(from: attitude)!,
                accuracy: 1e-15
            )
        }
    }

    /// Only three choices change an attitude, because the two placements on one axis
    /// are the two faces of a single plane.
    func testOnlyThreeContactAxesCanChangeAnAttitude() {
        XCTAssertEqual(DevicePlacement.backOnFace.contactAxisPair, .z)
        XCTAssertEqual(DevicePlacement.screenOnFace.contactAxisPair, .z)
        XCTAssertEqual(DevicePlacement.leftSideOnFace.contactAxisPair, .x)
        XCTAssertEqual(DevicePlacement.rightSideOnFace.contactAxisPair, .x)
        XCTAssertEqual(DevicePlacement.bottomEdgeOnFace.contactAxisPair, .y)
        XCTAssertEqual(DevicePlacement.topEdgeOnFace.contactAxisPair, .y)

        let attitude = deviceAttitude(placingZAxisAlong: Vector3(-0.4, 0.5, 0.77), spin: 12)
        let distinct = Set(DevicePlacement.allCases.map {
            DeviceAttitude.plane(from: attitude, placement: $0)!
        })
        XCTAssertEqual(distinct.count, 3, "six placements must collapse onto three attitudes")
    }

    /// The field picker offers every placement a geologist would actually use, and
    /// leaves out the one that means working blind.
    func testFieldPickerContents() {
        XCTAssertEqual(
            DevicePlacement.fieldSelectable,
            [.backOnFace, .leftSideOnFace, .rightSideOnFace, .bottomEdgeOnFace, .topEdgeOnFace]
        )
        XCTAssertFalse(DevicePlacement.fieldSelectable.contains(.screenOnFace))
        XCTAssertEqual(DeviceEdge.fieldSelectable, [.leftEdge, .rightEdge, .bottomEdge, .topEdge])
        XCTAssertTrue(DevicePlacement.fieldSelectable.contains(DeviceAttitude.defaultPlacement))
        XCTAssertTrue(DeviceEdge.fieldSelectable.contains(DeviceAttitude.defaultLineationEdge))
    }

    /// The setup survives a round trip, so it can be stored with the measurement.
    func testMeasurementGeometryIsCodable() throws {
        let geometry = MeasurementGeometry(placement: .rightSideOnFace, edge: .bottomEdge)
        let data = try JSONEncoder().encode(geometry)
        XCTAssertEqual(try JSONDecoder().decode(MeasurementGeometry.self, from: data), geometry)
        XCTAssertEqual(MeasurementGeometry.default.placement, .backOnFace)
        XCTAssertEqual(MeasurementGeometry.default.edge, .leftEdge)
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
