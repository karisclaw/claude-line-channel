import Foundation

/// A 3-component vector in the **NWU world frame**.
///
/// ```
///   x = north  (true north, declination-corrected)
///   y = west
///   z = up     (zenith)
/// ```
///
/// This is a right-handed frame (`north × west = up`) and matches CoreMotion's
/// `CMAttitudeReferenceFrame.xTrueNorthZVertical`, so a device attitude quaternion
/// obtained with that reference frame can be fed straight into this package.
///
/// East is available as `-y`; see ``east``.
public struct Vector3: Equatable, Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// Preferred initializer at call sites that think geographically.
    public init(north: Double, west: Double, up: Double) {
        self.init(north, west, up)
    }

    /// Convenience for callers that carry east-based components.
    public init(north: Double, east: Double, up: Double) {
        self.init(north, -east, up)
    }

    public var north: Double { x }
    public var west: Double { y }
    public var up: Double { z }
    /// East component. The stored frame is NWU, so east is `-y`.
    public var east: Double { -y }

    // Named with an `Axis` suffix so they do not collide with the instance
    // components `north` / `west` / `up` / `east` above.
    public static let zero = Vector3(0, 0, 0)
    public static let northAxis = Vector3(1, 0, 0)
    public static let southAxis = Vector3(-1, 0, 0)
    public static let westAxis = Vector3(0, 1, 0)
    public static let eastAxis = Vector3(0, -1, 0)
    public static let upAxis = Vector3(0, 0, 1)
    public static let downAxis = Vector3(0, 0, -1)

    // MARK: - Arithmetic

    public static func + (a: Vector3, b: Vector3) -> Vector3 {
        Vector3(a.x + b.x, a.y + b.y, a.z + b.z)
    }

    public static func - (a: Vector3, b: Vector3) -> Vector3 {
        Vector3(a.x - b.x, a.y - b.y, a.z - b.z)
    }

    public static prefix func - (v: Vector3) -> Vector3 {
        Vector3(-v.x, -v.y, -v.z)
    }

    public static func * (v: Vector3, s: Double) -> Vector3 {
        Vector3(v.x * s, v.y * s, v.z * s)
    }

    public static func * (s: Double, v: Vector3) -> Vector3 { v * s }

    public static func / (v: Vector3, s: Double) -> Vector3 {
        Vector3(v.x / s, v.y / s, v.z / s)
    }

    public func dot(_ other: Vector3) -> Double {
        x * other.x + y * other.y + z * other.z
    }

    public func cross(_ other: Vector3) -> Vector3 {
        Vector3(
            y * other.z - z * other.y,
            z * other.x - x * other.z,
            x * other.y - y * other.x
        )
    }

    public var lengthSquared: Double { dot(self) }
    public var length: Double { lengthSquared.squareRoot() }

    /// Unit vector, or `nil` for a zero-length (or non-finite) vector.
    ///
    /// Failable on purpose: a degenerate plane fit or a dropped sensor sample must
    /// surface as a measurement failure, never as a silently wrong attitude.
    public var normalized: Vector3? {
        let l = length
        guard l.isFinite, l > 0 else { return nil }
        return self / l
    }

    /// The horizontal part of the vector, or `nil` if the vector is vertical.
    public var horizontalComponent: Vector3? {
        Vector3(x, y, 0).normalized
    }

    // MARK: - Angles

    /// Angle to another vector, `0...180` degrees. Direction-sensitive.
    public func angle(to other: Vector3) -> Double {
        guard let a = normalized, let b = other.normalized else { return .nan }
        return GeoAngle.degrees(fromRadians: acos(GeoAngle.clamp(a.dot(b), -1, 1)))
    }

    /// Angle between the two *axes*, `0...90` degrees.
    ///
    /// Use this — not ``angle(to:)`` — for poles, lineations and any other axial
    /// datum, where `u` and `-u` mean the same thing. Comparing poles with a
    /// direction-sensitive angle is the single most common way to get joint-set
    /// analysis wrong.
    public func axialAngle(to other: Vector3) -> Double {
        guard let a = normalized, let b = other.normalized else { return .nan }
        return GeoAngle.degrees(fromRadians: acos(GeoAngle.clamp(abs(a.dot(b)), 0, 1)))
    }

    /// Azimuth of the horizontal projection, clockwise from true north.
    /// Returns `nil` when the vector is (numerically) vertical.
    public var azimuth: Double? {
        guard x != 0 || y != 0 else { return nil }
        return GeoAngle.normalizedAzimuth(GeoAngle.degrees(fromRadians: atan2(east, north)))
    }

    public func isApproximatelyEqual(to other: Vector3, tolerance: Double = 1e-12) -> Bool {
        (self - other).length <= tolerance
    }
}
