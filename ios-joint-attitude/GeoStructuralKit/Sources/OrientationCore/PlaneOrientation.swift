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
    /// the rock face. Either side of the plane may be measured: the normal is
    /// flipped into the upper hemisphere first, so both faces of a plane give the
    /// same attitude.
    ///
    /// Returns `nil` for a zero-length or non-finite normal, which is how a failed
    /// plane fit or a dropped sensor sample reaches the caller.
    ///
    /// Both components come from the **same** vector, the upward normal. Deriving
    /// the dip from one vector and the dip direction from another is exactly the
    /// error that puts a reading 180° out, so the two are never mixed — not even to
    /// tidy up the vertical case, where the sign of `n_U` is sensor noise and the
    /// reported dip direction can therefore jump by 180° between samples. That jump
    /// is a change of description, not of geometry: both descriptions denote the
    /// same vertical plane. ``isDipDirectionAmbiguous`` flags it, ``canonicalized``
    /// removes the jump for display, and ``alternativeVerticalDescription`` gives
    /// the UI its 180° toggle.
    public init?(measuredNormal: Vector3) {
        guard let upward = measuredNormal.upperHemisphereRepresentative else { return nil }
        self.init(
            dip: GeoAngle.degrees(fromRadians: acos(GeoAngle.clamp(upward.up, -1, 1))),
            dipDirection: GeoAngle.degrees(fromRadians: atan2(upward.east, upward.north))
        )
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

    /// `true` for a (near-)vertical plane, where the dip direction and the dip
    /// direction 180° away describe the same plane.
    ///
    /// Two consequences the UI has to handle: the reported dip direction is not
    /// stable against sensor noise, and neither of the two values is more correct
    /// than the other. Use ``canonicalized`` for a stable display and
    /// ``alternativeVerticalDescription`` for a 180° toggle.
    public var isDipDirectionAmbiguous: Bool {
        dip > 90 - OrientationTolerance.nearVerticalDip
    }

    /// The other description of a (near-)vertical plane: same dip, dip direction
    /// 180° away.
    ///
    /// `nil` for any plane that is not vertical, where flipping the dip direction
    /// would name a genuinely different plane rather than re-describe this one.
    public var alternativeVerticalDescription: PlaneOrientation? {
        guard isDipDirectionAmbiguous else { return nil }
        return PlaneOrientation(dip: dip, dipDirection: dipDirection + 180)
    }

    /// A description that does not change under sensor noise, for storage and
    /// display.
    ///
    /// Vertical planes are reported with a dip direction below 180°; every other
    /// plane is returned unchanged, since for those the dip direction is already
    /// determined by the rock. Canonicalizing discards which face of a vertical
    /// plane was measured — record ``Vector3/azimuth`` of the measured normal
    /// separately if that matters.
    public var canonicalized: PlaneOrientation {
        guard isDipDirectionAmbiguous, dipDirection >= 180 else { return self }
        return PlaneOrientation(dip: dip, dipDirection: dipDirection - 180)
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
    ///
    /// Sectioning a vertical plane along its own strike is degenerate — the section
    /// plane *is* the plane — and returns 0, the limit approached from every dip
    /// below 90.
    public func apparentDip(inVerticalSectionAlong trend: Double) -> Double {
        let beta = GeoAngle.radians(fromDegrees: trend - dipDirection)
        let c = cos(beta)
        if abs(c) < 1e-12 { return 0 }
        if dip > 90 - 1e-9 { return c > 0 ? 90 : -90 }
        return GeoAngle.degrees(fromRadians: atan(tan(GeoAngle.radians(fromDegrees: dip)) * c))
    }

    /// The line of intersection of two planes, or `nil` if they are parallel to
    /// within `minimumSeparation` degrees.
    ///
    /// The cross product of two unit normals has length `sin(separation)`, so for
    /// nearly parallel planes it is dominated by rounding error and its direction is
    /// meaningless. Rejecting those is the difference between "no intersection" and
    /// a confidently reported random trend.
    public func intersection(
        with other: PlaneOrientation,
        minimumSeparation: Double = 1e-4
    ) -> LineOrientation? {
        let product = upwardNormal.cross(other.upwardNormal)
        let threshold = sin(GeoAngle.radians(fromDegrees: max(minimumSeparation, 0)))
        guard product.length > threshold, let axis = product.normalized else { return nil }
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
