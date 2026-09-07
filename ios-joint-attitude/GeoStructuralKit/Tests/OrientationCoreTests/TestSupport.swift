import Foundation
import XCTest
@testable import OrientationCore

/// Builds a device attitude quaternion that would be produced by holding the phone
/// against a plane of the given attitude.
///
/// The device `+z` axis is placed along the plane's upward normal, and the phone is
/// then spun about that normal by `spin` degrees. Spin is a free parameter in a
/// real measurement — the geologist can hold the phone any way up against the rock —
/// so every conversion test sweeps it to prove the result does not depend on it.
func deviceAttitude(forPlaneDip dip: Double, dipDirection: Double, spin: Double) -> Quaternion {
    let normal = PlaneOrientation(dip: dip, dipDirection: dipDirection).upwardNormal
    return deviceAttitude(placingZAxisAlong: normal, spin: spin)
}

func deviceAttitude(placingZAxisAlong axis: Vector3, spin: Double) -> Quaternion {
    let n = axis.normalized!
    let reference = abs(n.x) < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 1, 0)
    let ex = reference.cross(n).normalized!
    let ey = n.cross(ex)
    let s = GeoAngle.radians(fromDegrees: spin)
    let cx = ex * cos(s) + ey * sin(s)
    let cy = ex * -sin(s) + ey * cos(s)
    return Quaternion(deviceXInWorld: cx, deviceYInWorld: cy, deviceZInWorld: n)!
}

/// Builds a device attitude that lays the device `-y` axis along a lineation.
func deviceAttitude(forLineTrend trend: Double, plunge: Double, roll: Double) -> Quaternion {
    let down = LineOrientation(trend: trend, plunge: plunge).downPlungeVector
    let cy = -down                                  // device +y is the up-plunge end
    let reference = abs(cy.x) < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 0, 1)
    let a = cy.cross(reference).normalized!
    let b = cy.cross(a)
    let r = GeoAngle.radians(fromDegrees: roll)
    let cz = a * cos(r) + b * sin(r)
    let cx = cy.cross(cz)
    return Quaternion(deviceXInWorld: cx, deviceYInWorld: cy, deviceZInWorld: cz)!
}

/// Asserts two azimuths are equal, comparing across the 0/360 wrap.
func XCTAssertAzimuthEqual(
    _ a: Double,
    _ b: Double,
    accuracy: Double,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let separation = GeoAngle.azimuthSeparation(a, b)
    XCTAssertLessThanOrEqual(
        separation, accuracy,
        "azimuths \(a) and \(b) differ by \(separation)°. \(message())",
        file: file, line: line
    )
}

/// Asserts two vectors are equal to within a tolerance.
func XCTAssertVectorEqual(
    _ a: Vector3,
    _ b: Vector3,
    accuracy: Double = 1e-12,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertLessThanOrEqual((a - b).length, accuracy, "\(a) != \(b)", file: file, line: line)
}

/// The accuracy the project specification demands of the attitude conversion.
let requiredAccuracyDegrees = 0.01
