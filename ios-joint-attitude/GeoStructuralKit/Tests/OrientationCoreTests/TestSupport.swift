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

// MARK: - Synthetic motion streams

/// A deterministic pseudo-random source, so a failing motion test reproduces exactly.
struct TestNoise {
    private var state: UInt64

    init(seed: UInt64 = 0x2545F4914F6CDD1D) { state = seed }

    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53) * 2 - 1      // -1...1
    }

    mutating func vector(scale: Double) -> Vector3 {
        Vector3(next() * scale, next() * scale, next() * scale)
    }
}

/// A stream of motion samples at a fixed rate, all holding one attitude.
///
/// `rate` defaults to 64 Hz rather than 50 because 1/64 is exactly representable in
/// binary: timestamps then add without rounding, so sample counts in the assertions are
/// deterministic rather than off-by-one depending on the last bit.
func motionStream(
    attitude: Quaternion,
    count: Int,
    rate: Double = 64,
    startingAt start: TimeInterval = 0,
    userAcceleration: (Int) -> Vector3 = { _ in .zero },
    rotationRate: (Int) -> Vector3 = { _ in .zero }
) -> [MotionSample] {
    (0..<count).map { index in
        MotionSample(
            timestamp: start + Double(index) / rate,
            attitude: attitude,
            userAcceleration: userAcceleration(index),
            rotationRate: rotationRate(index)
        )
    }
}
