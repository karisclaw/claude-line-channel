import Foundation

/// A unit quaternion representing a rotation from the **device frame** to the
/// **NWU world frame**.
///
/// Components are stored in `w, x, y, z` order. CoreMotion's `CMQuaternion`
/// stores `x, y, z, w`; use ``init(cmX:cmY:cmZ:cmW:)`` to bridge without
/// getting the order wrong.
///
/// The device frame is Apple's standard one, with the phone held upright facing
/// the user:
/// ```
///   +x = out of the right edge
///   +y = out of the top edge
///   +z = out of the screen, toward the user
/// ```
public struct Quaternion: Equatable, Hashable, Sendable, Codable {
    public var w: Double
    public var x: Double
    public var y: Double
    public var z: Double

    public init(w: Double, x: Double, y: Double, z: Double) {
        self.w = w
        self.x = x
        self.y = y
        self.z = z
    }

    /// Bridges `CMQuaternion`, whose component order is `x, y, z, w`.
    public init(cmX: Double, cmY: Double, cmZ: Double, cmW: Double) {
        self.init(w: cmW, x: cmX, y: cmY, z: cmZ)
    }

    public static let identity = Quaternion(w: 1, x: 0, y: 0, z: 0)

    /// Rotation of `degrees` about `axis`, right-handed.
    public init?(axis: Vector3, degrees: Double) {
        guard let a = axis.normalized else { return nil }
        let half = GeoAngle.radians(fromDegrees: degrees) / 2
        let s = sin(half)
        self.init(w: cos(half), x: a.x * s, y: a.y * s, z: a.z * s)
    }

    public var lengthSquared: Double { w * w + x * x + y * y + z * z }
    public var length: Double { lengthSquared.squareRoot() }

    public var normalized: Quaternion? {
        let l = length
        guard l.isFinite, l > 0 else { return nil }
        return Quaternion(w: w / l, x: x / l, y: y / l, z: z / l)
    }

    public var conjugate: Quaternion {
        Quaternion(w: w, x: -x, y: -y, z: -z)
    }

    public static func * (a: Quaternion, b: Quaternion) -> Quaternion {
        Quaternion(
            w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
            x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w
        )
    }

    /// Rotates a device-frame vector into the world frame.
    ///
    /// Uses the cross-product form rather than building a matrix — same result,
    /// fewer operations, and no chance of a transposed matrix creeping in.
    public func rotate(_ v: Vector3) -> Vector3 {
        let q = normalized ?? .identity
        let u = Vector3(q.x, q.y, q.z)
        let t = u.cross(v) * 2.0
        return v + t * q.w + u.cross(t)
    }

    /// Rotates a world-frame vector back into the device frame.
    public func inverseRotate(_ v: Vector3) -> Vector3 {
        (normalized ?? .identity).conjugate.rotate(v)
    }

    /// The device `+x` axis expressed in world coordinates.
    public var deviceXAxisInWorld: Vector3 { rotate(Vector3(1, 0, 0)) }
    /// The device `+y` axis expressed in world coordinates.
    public var deviceYAxisInWorld: Vector3 { rotate(Vector3(0, 1, 0)) }
    /// The device `+z` axis expressed in world coordinates.
    public var deviceZAxisInWorld: Vector3 { rotate(Vector3(0, 0, 1)) }

    /// Builds a quaternion from the three columns of a rotation matrix, i.e. from
    /// the world-frame images of the device `+x`, `+y` and `+z` axes.
    ///
    /// Shepperd's method: pick the largest of the four possible divisors so the
    /// square root never loses precision near a 180° rotation. Returns `nil` if
    /// the columns are not a right-handed orthonormal triad.
    public init?(deviceXInWorld cx: Vector3, deviceYInWorld cy: Vector3, deviceZInWorld cz: Vector3) {
        guard let cx = cx.normalized, let cy = cy.normalized, let cz = cz.normalized else { return nil }
        let orthogonal = abs(cx.dot(cy)) < 1e-6 && abs(cx.dot(cz)) < 1e-6 && abs(cy.dot(cz)) < 1e-6
        let rightHanded = cx.cross(cy).dot(cz) > 0
        guard orthogonal, rightHanded else { return nil }

        // m[row][column]; column j is the world image of device basis vector j.
        let m00 = cx.x, m10 = cx.y, m20 = cx.z
        let m01 = cy.x, m11 = cy.y, m21 = cy.z
        let m02 = cz.x, m12 = cz.y, m22 = cz.z

        let trace = m00 + m11 + m22
        var q: Quaternion
        if trace > 0 {
            let s = (trace + 1.0).squareRoot() * 2
            q = Quaternion(w: 0.25 * s, x: (m21 - m12) / s, y: (m02 - m20) / s, z: (m10 - m01) / s)
        } else if m00 > m11, m00 > m22 {
            let s = (1.0 + m00 - m11 - m22).squareRoot() * 2
            q = Quaternion(w: (m21 - m12) / s, x: 0.25 * s, y: (m01 + m10) / s, z: (m02 + m20) / s)
        } else if m11 > m22 {
            let s = (1.0 + m11 - m00 - m22).squareRoot() * 2
            q = Quaternion(w: (m02 - m20) / s, x: (m01 + m10) / s, y: 0.25 * s, z: (m12 + m21) / s)
        } else {
            let s = (1.0 + m22 - m00 - m11).squareRoot() * 2
            q = Quaternion(w: (m10 - m01) / s, x: (m02 + m20) / s, y: (m12 + m21) / s, z: 0.25 * s)
        }
        guard let n = q.normalized else { return nil }
        self = n
    }

    /// True if the two quaternions describe the same rotation (`q` and `-q` do).
    public func describesSameRotation(as other: Quaternion, toleranceDegrees: Double = 1e-6) -> Bool {
        guard let a = normalized, let b = other.normalized else { return false }
        let d = abs(a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z)
        let angle = 2 * GeoAngle.degrees(fromRadians: acos(GeoAngle.clamp(d, 0, 1)))
        return angle <= toleranceDegrees
    }
}
