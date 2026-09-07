import Foundation

/// Angles in this package are **always degrees** unless a symbol says otherwise.
///
/// Geological convention throughout:
/// - azimuths are measured clockwise from true north, in `0..<360`
/// - `dip` and `plunge` are measured downward from horizontal, in `0...90`
public enum GeoAngle {

    @inlinable
    public static func degrees(fromRadians r: Double) -> Double { r * 180.0 / .pi }

    @inlinable
    public static func radians(fromDegrees d: Double) -> Double { d * .pi / 180.0 }

    /// Wraps any angle into the `0..<360` azimuth range.
    public static func normalizedAzimuth(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let r = degrees.truncatingRemainder(dividingBy: 360.0)
        let wrapped = r < 0 ? r + 360.0 : r
        // truncatingRemainder can return -0.0 or land exactly on 360 after the add
        return wrapped >= 360.0 || wrapped == 0 ? 0 : wrapped
    }

    /// Smallest signed difference `a - b`, in `-180..<180`.
    ///
    /// Use this for azimuth comparisons — never subtract azimuths directly, or
    /// 359° and 001° look 358° apart instead of 2°.
    public static func signedAzimuthDifference(_ a: Double, _ b: Double) -> Double {
        let d = normalizedAzimuth(a - b)
        return d > 180.0 ? d - 360.0 : d
    }

    /// Smallest unsigned separation between two azimuths, in `0...180`.
    public static func azimuthSeparation(_ a: Double, _ b: Double) -> Double {
        abs(signedAzimuthDifference(a, b))
    }

    /// Smallest unsigned separation between two *axial* azimuths, in `0...90`.
    ///
    /// Strike lines and scanline trends are axial: 045 and 225 are the same line.
    public static func axialAzimuthSeparation(_ a: Double, _ b: Double) -> Double {
        let s = azimuthSeparation(a, b)
        return s > 90.0 ? 180.0 - s : s
    }

    @inlinable
    public static func clamp(_ x: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(x, lower), upper)
    }
}

/// Thresholds at which an orientation becomes degenerate and some component of it
/// stops being meaningful.
///
/// These are *reporting* thresholds, not measurement accuracy. They exist because
/// the dip direction of a horizontal plane and the trend of a vertical lineation
/// are mathematically undefined, and the app must flag that rather than print a
/// confident number derived from sensor noise.
public enum OrientationTolerance {
    /// Below this dip, a plane is treated as horizontal and its dip direction is
    /// not meaningful (`PlaneOrientation.isDipDirectionWellDefined == false`).
    public static let nearHorizontalDip: Double = 0.5

    /// Above this dip, a plane is treated as vertical: the two faces of the plane
    /// give dip directions 180° apart and both are valid descriptions.
    public static let nearVerticalDip: Double = 0.5

    /// Above this plunge, a lineation is treated as vertical and its trend is not
    /// meaningful.
    public static let nearVerticalPlunge: Double = 89.5
}
