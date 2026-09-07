import XCTest
@testable import OrientationCore

final class GeoAngleTests: XCTestCase {

    func testAzimuthNormalization() {
        XCTAssertEqual(GeoAngle.normalizedAzimuth(0), 0, accuracy: 1e-12)
        XCTAssertEqual(GeoAngle.normalizedAzimuth(360), 0, accuracy: 1e-12)
        XCTAssertEqual(GeoAngle.normalizedAzimuth(-90), 270, accuracy: 1e-12)
        XCTAssertEqual(GeoAngle.normalizedAzimuth(725), 5, accuracy: 1e-12)
        XCTAssertEqual(GeoAngle.normalizedAzimuth(-725), 355, accuracy: 1e-12)
        XCTAssertEqual(GeoAngle.normalizedAzimuth(.nan), 0, accuracy: 1e-12)
    }

    /// Azimuths must never be compared by plain subtraction: 359 and 001 are 2°
    /// apart, not 358°.
    func testAzimuthDifferencesWrapCorrectly() {
        XCTAssertEqual(GeoAngle.signedAzimuthDifference(1, 359), 2, accuracy: 1e-12)
        XCTAssertEqual(GeoAngle.signedAzimuthDifference(359, 1), -2, accuracy: 1e-12)
        XCTAssertEqual(GeoAngle.azimuthSeparation(359, 1), 2, accuracy: 1e-12)
        XCTAssertEqual(GeoAngle.azimuthSeparation(0, 180), 180, accuracy: 1e-12)
        XCTAssertEqual(GeoAngle.azimuthSeparation(10, 200), 170, accuracy: 1e-12)
    }

    /// Strike lines and scanline trends are axial: 045 and 225 are the same line.
    func testAxialAzimuthSeparation() {
        XCTAssertEqual(GeoAngle.axialAzimuthSeparation(45, 225), 0, accuracy: 1e-12)
        XCTAssertEqual(GeoAngle.axialAzimuthSeparation(10, 170), 20, accuracy: 1e-12)
        XCTAssertEqual(GeoAngle.axialAzimuthSeparation(0, 90), 90, accuracy: 1e-12)
    }
}

final class Vector3Tests: XCTestCase {

    /// The world frame must be right-handed, or every cross product downstream —
    /// intersections, strike vectors, plane fits — silently reverses.
    func testWorldFrameIsRightHanded() {
        XCTAssertVectorEqual(Vector3.northAxis.cross(.westAxis), .upAxis)
        XCTAssertVectorEqual(Vector3.westAxis.cross(.upAxis), .northAxis)
        XCTAssertVectorEqual(Vector3.upAxis.cross(.northAxis), .westAxis)
    }

    func testEastIsNegativeWest() {
        XCTAssertVectorEqual(Vector3.eastAxis, -Vector3.westAxis)
        XCTAssertEqual(Vector3(north: 0, east: 3, up: 0).west, -3, accuracy: 1e-12)
        XCTAssertEqual(Vector3(north: 0, west: 3, up: 0).east, -3, accuracy: 1e-12)
    }

    func testAzimuthOfHorizontalDirections() {
        XCTAssertEqual(Vector3.northAxis.azimuth!, 0, accuracy: 1e-12)
        XCTAssertEqual(Vector3.eastAxis.azimuth!, 90, accuracy: 1e-12)
        XCTAssertEqual(Vector3.southAxis.azimuth!, 180, accuracy: 1e-12)
        XCTAssertEqual(Vector3.westAxis.azimuth!, 270, accuracy: 1e-12)
        XCTAssertNil(Vector3.upAxis.azimuth)
    }

    /// The distinction the whole set-analysis module rests on: poles are axes, so
    /// `u` and `-u` are 0° apart, not 180°.
    func testAxialAngleVersusDirectedAngle() {
        let a = Vector3(1, 0, 0)
        XCTAssertEqual(a.angle(to: -a), 180, accuracy: 1e-9)
        XCTAssertEqual(a.axialAngle(to: -a), 0, accuracy: 1e-9)
        XCTAssertEqual(a.angle(to: Vector3(0, 1, 0)), 90, accuracy: 1e-9)
        XCTAssertEqual(a.axialAngle(to: Vector3(0, 1, 0)), 90, accuracy: 1e-9)
    }

    func testNormalizationRejectsDegenerateVectors() {
        XCTAssertNil(Vector3.zero.normalized)
        XCTAssertNil(Vector3(.nan, 1, 0).normalized)
        XCTAssertEqual(Vector3(3, 0, 4).normalized!.length, 1, accuracy: 1e-12)
    }
}

final class QuaternionTests: XCTestCase {

    func testIdentityLeavesTheDeviceAxesAlongTheWorldAxes() {
        XCTAssertVectorEqual(Quaternion.identity.deviceXAxisInWorld, Vector3(1, 0, 0))
        XCTAssertVectorEqual(Quaternion.identity.deviceYAxisInWorld, Vector3(0, 1, 0))
        XCTAssertVectorEqual(Quaternion.identity.deviceZAxisInWorld, Vector3(0, 0, 1))
    }

    func testCoreMotionComponentOrderIsBridgedCorrectly() {
        // CMQuaternion is (x, y, z, w); this type stores (w, x, y, z).
        let q = Quaternion(cmX: 0.1, cmY: 0.2, cmZ: 0.3, cmW: 0.9)
        XCTAssertEqual(q.w, 0.9)
        XCTAssertEqual(q.x, 0.1)
        XCTAssertEqual(q.y, 0.2)
        XCTAssertEqual(q.z, 0.3)
    }

    func testRotationAboutAnAxisIsRightHanded() {
        let q = Quaternion(axis: .upAxis, degrees: 90)!
        // A right-handed 90° rotation about up carries north to west.
        XCTAssertVectorEqual(q.rotate(.northAxis), .westAxis, accuracy: 1e-12)
    }

    func testRotationPreservesLengthAndAngles() {
        let q = Quaternion(axis: Vector3(1, 2, 3), degrees: 47)!
        let a = Vector3(0.3, -0.7, 0.2), b = Vector3(-0.1, 0.4, 0.9)
        XCTAssertEqual(q.rotate(a).length, a.length, accuracy: 1e-12)
        XCTAssertEqual(q.rotate(a).dot(q.rotate(b)), a.dot(b), accuracy: 1e-12)
    }

    func testInverseRotationUndoesRotation() {
        let q = Quaternion(axis: Vector3(-2, 1, 0.5), degrees: 123)!
        let v = Vector3(0.2, 0.9, -0.4)
        XCTAssertVectorEqual(q.inverseRotate(q.rotate(v)), v, accuracy: 1e-12)
    }

    func testCompositionMatchesSequentialRotation() {
        let a = Quaternion(axis: .upAxis, degrees: 30)!
        let b = Quaternion(axis: .northAxis, degrees: 50)!
        let v = Vector3(0.4, -0.2, 0.8)
        XCTAssertVectorEqual((a * b).rotate(v), a.rotate(b.rotate(v)), accuracy: 1e-12)
    }

    /// Matrix-to-quaternion must stay accurate for every branch of Shepperd's
    /// method, including the 180° rotations where the naive trace formula fails.
    func testConstructionFromRotationColumnsCoversAllBranches() {
        let axes = [
            Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1),
            Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(-1, 2, -0.5)
        ]
        for axis in axes {
            for degrees in [0.0, 45, 90, 179.9, 180, 270, 359] {
                let original = Quaternion(axis: axis, degrees: degrees)!
                let rebuilt = Quaternion(
                    deviceXInWorld: original.deviceXAxisInWorld,
                    deviceYInWorld: original.deviceYAxisInWorld,
                    deviceZInWorld: original.deviceZAxisInWorld
                )
                XCTAssertNotNil(rebuilt, "rebuild failed for \(axis) at \(degrees)°")
                XCTAssertTrue(
                    rebuilt!.describesSameRotation(as: original, toleranceDegrees: 1e-6),
                    "rebuild inaccurate for \(axis) at \(degrees)°"
                )
            }
        }
    }

    func testConstructionRejectsNonRotationColumns() {
        // Not orthogonal.
        XCTAssertNil(Quaternion(
            deviceXInWorld: Vector3(1, 0, 0),
            deviceYInWorld: Vector3(1, 1, 0),
            deviceZInWorld: Vector3(0, 0, 1)
        ))
        // Orthogonal but left-handed (a mirror, not a rotation).
        XCTAssertNil(Quaternion(
            deviceXInWorld: Vector3(1, 0, 0),
            deviceYInWorld: Vector3(0, 1, 0),
            deviceZInWorld: Vector3(0, 0, -1)
        ))
        XCTAssertNil(Quaternion(
            deviceXInWorld: .zero,
            deviceYInWorld: Vector3(0, 1, 0),
            deviceZInWorld: Vector3(0, 0, 1)
        ))
    }

    func testNegatedQuaternionIsTheSameRotation() {
        let q = Quaternion(axis: Vector3(1, 1, 0), degrees: 77)!
        let negated = Quaternion(w: -q.w, x: -q.x, y: -q.y, z: -q.z)
        XCTAssertTrue(q.describesSameRotation(as: negated))
        XCTAssertVectorEqual(q.rotate(Vector3(1, 2, 3)), negated.rotate(Vector3(1, 2, 3)), accuracy: 1e-12)
    }
}

final class ReferenceFrameTests: XCTestCase {

    /// ARKit's `.gravityAndHeading` frame is +x east, +y up, -z north.
    func testARKitAxesMapOntoTheWorldFrame() {
        XCTAssertVectorEqual(ReferenceFrame.fromARKitGravityAndHeading(x: 1, y: 0, z: 0), .eastAxis)
        XCTAssertVectorEqual(ReferenceFrame.fromARKitGravityAndHeading(x: 0, y: 1, z: 0), .upAxis)
        XCTAssertVectorEqual(ReferenceFrame.fromARKitGravityAndHeading(x: 0, y: 0, z: -1), .northAxis)
    }

    /// The mapping must be a proper rotation (determinant +1). A determinant of −1
    /// would mirror the fabric and reverse every reported dip direction.
    func testARKitMappingPreservesHandedness() {
        let x = ReferenceFrame.fromARKitGravityAndHeading(x: 1, y: 0, z: 0)
        let y = ReferenceFrame.fromARKitGravityAndHeading(x: 0, y: 1, z: 0)
        let z = ReferenceFrame.fromARKitGravityAndHeading(x: 0, y: 0, z: 1)
        XCTAssertEqual(x.cross(y).dot(z), 1, accuracy: 1e-12)
    }

    func testARKitRoundTrip() {
        let v = Vector3(0.3, -0.5, 0.81)
        let ark = ReferenceFrame.toARKitGravityAndHeading(v)
        XCTAssertVectorEqual(
            ReferenceFrame.fromARKitGravityAndHeading(x: ark.x, y: ark.y, z: ark.z), v
        )
    }

    /// A LiDAR plane fit expressed in ARKit coordinates must reach the same attitude
    /// as the equivalent contact measurement.
    func testARKitPlaneFitProducesTheSameAttitudeAsAContactMeasurement() {
        let dip = GeoAngle.radians(fromDegrees: 30)
        // Fitted normal in ARKit coordinates, leaning east.
        let normal = ReferenceFrame.fromARKitGravityAndHeading(x: sin(dip), y: cos(dip), z: 0)
        let plane = PlaneOrientation(measuredNormal: normal)!
        XCTAssertEqual(plane.dip, 30, accuracy: 1e-9)
        XCTAssertAzimuthEqual(plane.dipDirection, 90, accuracy: 1e-9)
    }

    func testENUMapping() {
        XCTAssertVectorEqual(ReferenceFrame.fromENU(x: 1, y: 0, z: 0), .eastAxis)
        XCTAssertVectorEqual(ReferenceFrame.fromENU(x: 0, y: 1, z: 0), .northAxis)
        XCTAssertVectorEqual(ReferenceFrame.fromENU(x: 0, y: 0, z: 1), .upAxis)
    }
}
