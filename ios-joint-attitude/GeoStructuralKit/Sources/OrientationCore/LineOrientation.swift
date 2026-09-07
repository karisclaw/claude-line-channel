import Foundation

/// The attitude of a linear structure — a slickenline, fold axis, lineation, the
/// intersection of two joint sets, or a scanline.
///
/// Stored as **trend / plunge**: the azimuth of the down-plunge direction, and how
/// far below horizontal it descends.
public struct LineOrientation: Equatable, Hashable, Sendable, Codable {

    /// Azimuth of the down-plunge direction, `0..<360` degrees clockwise from true
    /// north.
    public let trend: Double

    /// Inclination below horizontal, `0...90` degrees.
    public let plunge: Double

    /// Creates an orientation from trend and plunge, normalizing both.
    ///
    /// A negative plunge is folded to the other end of the line: `-30` toward 000
    /// is the same line as `30` toward 180.
    public init(trend: Double, plunge: Double) {
        var p = plunge.isFinite ? plunge : 0
        var t = trend

        p = p.truncatingRemainder(dividingBy: 360)
        if p > 180 { p -= 360 }
        if p < -180 { p += 360 }
        if p < 0 {
            p = -p
            t += 180
        }
        if p > 90 {
            p = 180 - p
            t += 180
        }

        self.plunge = GeoAngle.clamp(p, 0, 90)
        self.trend = GeoAngle.normalizedAzimuth(t)
    }

    /// Derives the orientation from a measured axis.
    ///
    /// A lineation is **axial**: the measured vector may point either way along the
    /// line, and the conversion flips it to the down-plunge end. Returns `nil` for
    /// a zero-length or non-finite axis.
    public init?(measuredAxis: Vector3) {
        guard let measured = measuredAxis.normalized else { return nil }
        let down = measured.up > 0 ? -measured : measured
        let plunge = GeoAngle.degrees(fromRadians: asin(GeoAngle.clamp(-down.up, -1, 1)))
        let trend = GeoAngle.degrees(fromRadians: atan2(down.east, down.north))
        self.init(trend: trend, plunge: plunge)
    }

    /// Unit vector pointing down-plunge.
    public var downPlungeVector: Vector3 {
        let t = GeoAngle.radians(fromDegrees: trend)
        let p = GeoAngle.radians(fromDegrees: plunge)
        return Vector3(north: cos(p) * cos(t), east: cos(p) * sin(t), up: -sin(p))
    }

    /// Unit vector pointing up-plunge — the other end of the same line.
    public var upPlungeVector: Vector3 { -downPlungeVector }

    /// `false` when the line is so close to vertical that its trend is determined
    /// by noise rather than by the rock.
    public var isTrendWellDefined: Bool {
        plunge <= OrientationTolerance.nearVerticalPlunge
    }

    /// `true` for a (near-)horizontal line, where the two ends are equally valid
    /// and the recorded trend could as well be `trend + 180`.
    public var isTrendAmbiguous: Bool {
        plunge < OrientationTolerance.nearHorizontalDip
    }

    /// Acute angle between two lines, `0...90` degrees. Axial, as lineations are.
    public func angle(to other: LineOrientation) -> Double {
        downPlungeVector.axialAngle(to: other.downPlungeVector)
    }

    /// Acute angle between this line and a plane, `0...90` degrees. Zero when the
    /// line lies in the plane, 90 when it is normal to it.
    public func angle(to plane: PlaneOrientation) -> Double {
        90 - downPlungeVector.axialAngle(to: plane.upwardNormal)
    }

    /// Rake (pitch) of this line measured within `plane`, in `0...180` degrees from
    /// the right-hand-rule strike direction.
    ///
    /// Returns `nil` if the line does not lie in the plane within `tolerance`.
    public func rake(in plane: PlaneOrientation, tolerance: Double = 1.0) -> Double? {
        guard plane.contains(self, tolerance: tolerance) else { return nil }
        // Project onto the plane and measure from the strike vector, choosing the
        // end of the line that points down-dip so the rake is reported in 0...180.
        let normal = plane.upwardNormal
        var v = downPlungeVector
        v = v - normal * v.dot(normal)
        guard let unit = v.normalized else { return nil }
        let strike = plane.strikeVector
        let cosine = GeoAngle.clamp(unit.dot(strike), -1, 1)
        return GeoAngle.degrees(fromRadians: acos(cosine))
    }
}

extension LineOrientation: CustomStringConvertible {
    /// Field shorthand, e.g. `30->145` (plunge -> trend).
    public var description: String {
        String(format: "%02.0f->%03.0f", plunge.rounded(), GeoAngle.normalizedAzimuth(trend.rounded()))
    }
}
