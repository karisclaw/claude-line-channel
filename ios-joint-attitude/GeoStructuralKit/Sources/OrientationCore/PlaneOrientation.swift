import Foundation

/// The attitude of a planar structure — a joint, bedding plane, fault, foliation,
/// cleavage or vein.
///
/// Stored in **dip / dip-direction** form, which is what LINE-of-sight field work
/// and Rocscience Dips both use. ``strike`` is derived using the **right-hand
/// rule**: looking along the strike direction, the plane dips to your right, so
/// `strike = dipDirection - 90`.
///
/// ## Sign conventions
///
/// The upward normal of a plane leans **toward** the dip direction — an east-facing
/// slope has an upward normal pointing up-and-east. (The *pole* plotted on a
/// lower-hemisphere stereonet is the downward normal, which points the opposite
/// way; see ``pole``. Conflating the two puts every dip direction 180° out.)
public struct PlaneOrientation: Equatable, Hashable, Sendable, Codable {

    /// Inclination below horizontal, `0...90` degrees.
    public let dip: Double

    /// Azimuth of the steepest downslope direction, `0..<360` degrees clockwise
    /// from true north.
    public let dipDirection: Double

    // MARK: - Initializers

    /// Creates an orientation from dip and dip direction, normalizing both into
    /// their canonical ranges.
    ///
    /// A dip outside `0...90` is folded rather than clamped: a dip of 100° toward
    /// 090 is the same plane as 80° toward 270, and folding keeps that true.
    public init(dip: Double, dipDirection: Double) {
        var d = dip.isFinite ? dip : 0
        var azimuth = dipDirection

        // Fold a dip given past vertical onto the other side of the plane.
        d = d.truncatingRemainder(dividingBy: 360)
        if d < 0 {
            d = -d
            azimuth += 180
        }
        if d > 180 {
            d = 360 - d
            azimuth += 180
        }
        if d > 90 {
            d = 180 - d
            azimuth += 180
        }

        self.dip = GeoAngle.clamp(d, 0, 90)
        self.dipDirection = GeoAngle.normalizedAzimuth(azimuth)
    }

    /// Creates an orientation from a right-hand-rule strike and dip.
    public init(rightHandRuleStrike strike: Double, dip: Double) {
        self.init(dip: dip, dipDirection: strike + 90)
    }

    /// Derives the orientation from a measured plane normal.
    ///
    /// `measuredNormal` is the outward normal as physically measured — for the
    /// contact method, the device `+z` axis while the back of the phone is flat on
    /// the rock face. Either side of the plane may be measured; the conversion
    /// handles both.
    ///
    /// Returns `nil` for a zero-length or non-finite normal, which is how a failed
    /// plane fit or a dropped sensor sample reaches the caller.
    ///
    /// Near-vertical planes: the up/down sign of the normal is pure sensor noise
    /// there, so flipping the normal upward would make the reported dip direction
    /// flicker 180° between samples. Within ``OrientationTolerance/nearVerticalDip``
    /// of vertical the **as-measured** normal sets the dip direction instead, which
    /// is stable and reports the direction the measured face actually looks toward.
    /// The two faces of a vertical plane therefore report dip directions 180° apart
    /// — both are correct descriptions of the same plane, and
    /// ``isDipDirectionAmbiguous`` is `true` to say so.
    public init?(measuredNormal: Vector3) {
        guard let measured = measuredNormal.normalized else { return nil }

        let upward = measured.up < 0 ? -measured : measured
        let dip = GeoAngle.degrees(fromRadians: acos(GeoAngle.clamp(upward.up, -1, 1)))

        let source = dip > 90 - OrientationTolerance.nearVerticalDip ? measured : upward
        let dipDirection = GeoAngle.degrees(fromRadians: atan2(source.east, source.north))

        self.init(dip: dip, dipDirection: dipDirection)
    }

    // MARK: - Derived attitude

    /// Right-hand-rule strike: with the strike direction ahead of you, the plane
    /// dips to your right.
    public var strike: Double { GeoAngle.normalizedAzimuth(dipDirection - 90) }

    /// The strike line stated as an axis in `0..<180`, for callers that record
    /// strike without the right-hand-rule sense.
    public var strikeAxis: Double {
        let s = strike
        return s >= 180 ? s - 180 : s
    }

    // MARK: - Vectors

    /// Unit normal pointing into the upper hemisphere. Leans toward the dip
    /// direction.
    public var upwardNormal: Vector3 {
        let d = GeoAngle.radians(fromDegrees: dip)
        let a = GeoAngle.radians(fromDegrees: dipDirection)
        return Vector3(north: sin(d) * cos(a), east: sin(d) * sin(a), up: cos(d))
    }

    /// Unit normal pointing into the lower hemisphere — the **pole** as plotted on
    /// a lower-hemisphere stereonet, and the vector to cluster on in joint-set
    /// analysis.
    public var pole: Vector3 { -upwardNormal }

    /// Unit vector along the steepest downslope direction, lying in the plane.
    public var dipVector: Vector3 {
        let d = GeoAngle.radians(fromDegrees: dip)
        let a = GeoAngle.radians(fromDegrees: dipDirection)
        return Vector3(north: cos(d) * cos(a), east: cos(d) * sin(a), up: -sin(d))
    }

    /// Unit horizontal vector along the right-hand-rule strike direction.
    public var strikeVector: Vector3 {
        let s = GeoAngle.radians(fromDegrees: strike)
        return Vector3(north: cos(s), east: sin(s), up: 0)
    }

    /// The strike line as a ``LineOrientation`` (plunge 0).
    public var strikeLine: LineOrientation {
        LineOrientation(trend: strike, plunge: 0)
    }

    /// The dip line as a ``LineOrientation``.
    public var dipLine: LineOrientation {
        LineOrientation(trend: dipDirection, plunge: dip)
    }

    // MARK: - Degeneracy flags

    /// `false` when the plane is so close to horizontal that its dip direction is
    /// determined by noise rather than by the rock. Show the dip alone in the UI
    /// and do not feed the dip direction into set analysis.
    public var isDipDirectionWellDefined: Bool {
        dip >= OrientationTolerance.nearHorizontalDip
    }

    /// `true` for a (near-)vertical plane, whose two faces yield dip directions
    /// 180° apart. Both describe the same plane; the UI should offer a 180° toggle
    /// rather than pretending one is wrong.
    public var isDipDirectionAmbiguous: Bool {
        dip > 90 - OrientationTolerance.nearVerticalDip
    }

    /// The same plane described from its other face. Identical geometry; differs
    /// only in the recorded dip direction, and only meaningfully when vertical.
    public var oppositeFaceDescription: PlaneOrientation {
        PlaneOrientation(dip: dip, dipDirection: dipDirection + 180)
    }

    // MARK: - Relations

    /// Acute dihedral angle to another plane, `0...90` degrees.
    public func angle(to other: PlaneOrientation) -> Double {
        upwardNormal.axialAngle(to: other.upwardNormal)
    }

    /// Apparent dip seen in a vertical section cut along `trend`.
    ///
    /// Positive means the plane descends toward `trend`; negative means it
    /// descends away from it. Along the strike the apparent dip is 0; along the
    /// dip direction it equals the true dip.
    public func apparentDip(inVerticalSectionAlong trend: Double) -> Double {
        let beta = GeoAngle.radians(fromDegrees: trend - dipDirection)
        let c = cos(beta)
        if abs(c) < 1e-12 { return 0 }
        if dip > 90 - 1e-9 { return c > 0 ? 90 : -90 }
        return GeoAngle.degrees(fromRadians: atan(tan(GeoAngle.radians(fromDegrees: dip)) * c))
    }

    /// The line of intersection of two planes, or `nil` if they are parallel.
    public func intersection(with other: PlaneOrientation) -> LineOrientation? {
        guard let axis = upwardNormal.cross(other.upwardNormal).normalized else { return nil }
        return LineOrientation(measuredAxis: axis)
    }

    /// Whether a lineation lies in this plane, within `tolerance` degrees.
    public func contains(_ line: LineOrientation, tolerance: Double = 1.0) -> Bool {
        abs(90 - upwardNormal.angle(to: line.downPlungeVector)) <= tolerance
    }
}

extension PlaneOrientation: CustomStringConvertible {
    /// Field shorthand, e.g. `45/090` (dip / dip direction), zero-padded as
    /// geologists write it.
    public var description: String {
        String(format: "%02.0f/%03.0f", dip.rounded(), GeoAngle.normalizedAzimuth(dipDirection.rounded()))
    }
}
