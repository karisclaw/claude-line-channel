import Foundation
import OrientationCore

/// Which stereographic projection to draw on.
///
/// Both put the centre of the plot at the vertical and the primitive circle at the
/// horizontal, and both plot the **lower hemisphere**, as structural geology does.
/// They differ in what they preserve:
///
/// - ``equalArea`` (Schmidt, Lambert azimuthal equal-area) preserves area, so equal
///   areas on the sphere cover equal areas on the plot. This is the one to count density
///   on: a uniform grid over the plot is then a uniform sample of the hemisphere.
/// - ``equalAngle`` (Wulff, stereographic) preserves angles, so circles stay circles.
///   Easier to construct by hand, and the usual choice for geometric work.
///
/// Density is always computed on the equal-area grid whatever is displayed — see
/// ``KambDensity``.
public enum StereonetProjection: String, CaseIterable, Sendable, Codable {

    case equalArea
    case equalAngle

    /// Radial distance on a unit primitive for an axis `theta` degrees from the centre.
    ///
    /// `theta` is measured from the downward vertical, so 0° is the centre of the plot
    /// and 90° the primitive, where both projections return exactly 1.
    public func radius(forAngleFromCentre theta: Double) -> Double {
        let half = GeoAngle.radians(fromDegrees: GeoAngle.clamp(theta, 0, 90)) / 2
        switch self {
        case .equalArea: return 2.0.squareRoot() * sin(half)
        case .equalAngle: return tan(half)
        }
    }

    /// The inverse: the angle from the centre for a point at radius `radius`.
    public func angleFromCentre(forRadius radius: Double) -> Double {
        let r = max(radius, 0)
        switch self {
        case .equalArea:
            return GeoAngle.degrees(fromRadians: 2 * asin(GeoAngle.clamp(r / 2.0.squareRoot(), 0, 1)))
        case .equalAngle:
            return GeoAngle.degrees(fromRadians: 2 * atan(r))
        }
    }
}

/// A point on a stereonet of unit radius.
///
/// `east` is to the right and `north` is up, as a map is drawn, so the azimuth of a
/// point is `atan2(east, north)` — clockwise from the top.
public struct StereonetPoint: Equatable, Sendable, Codable {

    public var east: Double
    public var north: Double

    public init(east: Double, north: Double) {
        self.east = east
        self.north = north
    }

    public var radius: Double { (east * east + north * north).squareRoot() }

    /// `true` for a point on or inside the primitive, with a little slack for the points
    /// that land exactly on it.
    public var isInsidePrimitive: Bool { radius <= 1 + 1e-9 }

    /// Azimuth of the point, clockwise from north. `nil` at the centre.
    public var azimuth: Double? {
        guard east != 0 || north != 0 else { return nil }
        return GeoAngle.normalizedAzimuth(GeoAngle.degrees(fromRadians: atan2(east, north)))
    }
}

/// Lower-hemisphere projection, and its inverse.
public enum Stereonet {

    /// Plots an **axis**.
    ///
    /// Folded to the lower hemisphere first, because a pole and its opposite are the same
    /// datum and must land on the same point — the ± symmetry the whole module depends
    /// on. Returns `nil` only for a degenerate vector.
    public static func project(
        axis: Vector3,
        using projection: StereonetProjection = .equalArea
    ) -> StereonetPoint? {
        guard let down = axis.lowerHemisphereRepresentative else { return nil }
        let theta = GeoAngle.degrees(fromRadians: acos(GeoAngle.clamp(-down.up, -1, 1)))
        let radius = projection.radius(forAngleFromCentre: theta)
        let azimuth = atan2(down.east, down.north)
        return StereonetPoint(east: radius * sin(azimuth), north: radius * cos(azimuth))
    }

    /// Plots the pole of a plane — the conventional way to show a discontinuity for set
    /// analysis.
    public static func projectPole(
        of plane: PlaneOrientation,
        using projection: StereonetProjection = .equalArea
    ) -> StereonetPoint {
        project(axis: plane.pole, using: projection)!
    }

    /// Plots a **recorded** lineation, at the trend it was recorded at.
    ///
    /// For any plunging line this is the same as the axial fold: the down-plunge end is
    /// already in the lower hemisphere and nothing moves. The two differ only for a
    /// horizontal line, where both ends are equally valid and the axial tie-break would
    /// put the point at `trend + 180`. A geologist who wrote down 000 must not be shown
    /// a point at 180, so here the record wins.
    ///
    /// ``project(axis:using:)`` keeps the tie-break instead, because a pole has no
    /// recorded sense and the two normals of a vertical joint have to land on one point.
    /// ``LineOrientation/isTrendAmbiguous`` is what says the two ends were interchangeable
    /// in the first place.
    public static func project(
        line: LineOrientation,
        using projection: StereonetProjection = .equalArea
    ) -> StereonetPoint {
        projectCurvePoint(line.downPlungeVector, using: projection)!
    }

    /// Projects a point on a **curve**, folding only what is strictly above the horizon.
    ///
    /// Not the same as ``project(axis:using:)``, and the difference matters. For a datum,
    /// an axis exactly on the horizon is folded by a fixed tie-break so that it and its
    /// opposite land on one point — determinism is what is wanted there. For a curve,
    /// that same tie-break is a discontinuity: a great circle ends at the strike line,
    /// which lies exactly on the horizon, so both of its endpoints would be folded onto
    /// the *same* point and the trace would come back with its ends tied together. A
    /// horizontal plane, whose whole trace sits on the horizon, would collapse onto half
    /// the primitive drawn twice.
    ///
    /// So here nothing on the horizon is moved, and the parameterization survives.
    static func projectCurvePoint(
        _ v: Vector3,
        using projection: StereonetProjection
    ) -> StereonetPoint? {
        guard let unit = v.normalized else { return nil }
        let down = unit.up > 0 ? -unit : unit
        let theta = GeoAngle.degrees(fromRadians: acos(GeoAngle.clamp(-down.up, -1, 1)))
        let radius = projection.radius(forAngleFromCentre: theta)
        let azimuth = atan2(down.east, down.north)
        return StereonetPoint(east: radius * sin(azimuth), north: radius * cos(azimuth))
    }

    /// The inverse: the downward unit axis a point on the net stands for.
    ///
    /// `nil` for a point outside the primitive, which is how a lasso drawn past the edge
    /// of the net reports that it went outside rather than wrapping silently.
    public static func axis(
        at point: StereonetPoint,
        using projection: StereonetProjection = .equalArea
    ) -> Vector3? {
        guard point.isInsidePrimitive else { return nil }
        let theta = GeoAngle.radians(
            fromDegrees: projection.angleFromCentre(forRadius: min(point.radius, 1))
        )
        let azimuth = atan2(point.east, point.north)
        return Vector3(
            north: sin(theta) * cos(azimuth),
            east: sin(theta) * sin(azimuth),
            up: -cos(theta)
        )
    }

    /// The plane itself, as its great-circle trace.
    ///
    /// Returned as one polyline running from one end of the strike line, through the dip
    /// direction, to the other end. Half the great circle is all that is needed: the
    /// plane's circle crosses the primitive exactly at the strike line, and the half
    /// swept here is entirely in the lower hemisphere, so nothing has to be clipped.
    ///
    /// A horizontal plane is the exception — its trace *is* the primitive — and it comes
    /// back as the full circle, because half of it would look like a mistake.
    public static func greatCircle(
        of plane: PlaneOrientation,
        using projection: StereonetProjection = .equalArea,
        segments: Int = 180
    ) -> [StereonetPoint] {
        let count = max(segments, 8)
        let strike = plane.strikeVector
        let dip = plane.dipVector
        let sweep = plane.dip < OrientationTolerance.nearHorizontalDip ? 2 * Double.pi : Double.pi

        return (0...count).compactMap { step in
            let phi = sweep * Double(step) / Double(count)
            let v = strike * cos(phi) + dip * sin(phi)
            // `sin φ ≥ 0` over the sweep and the dip vector points down, so the arc is
            // already in the lower hemisphere and only needs the curve projection.
            return projectCurvePoint(v, using: projection)
        }
    }

    /// A small circle — the cone of directions at `angle` degrees from an axis.
    ///
    /// This is how an `α95` confidence cone is drawn, and how a "within N degrees of this
    /// set" boundary is drawn.
    ///
    /// Returned as **one or more** polylines. A cone that stays in the lower hemisphere
    /// gives one closed loop; a cone that crosses the horizontal gives two arcs, because
    /// the part that would sit in the upper hemisphere is folded to its antipode and
    /// appears on the opposite side of the net. That split is the geometry, not a defect
    /// — joining the arcs would draw a line across the plot that means nothing.
    public static func smallCircle(
        about axis: Vector3,
        angle: Double,
        using projection: StereonetProjection = .equalArea,
        segments: Int = 180
    ) -> [[StereonetPoint]] {
        guard let m = axis.normalized, angle > 0, angle < 180 else { return [] }
        let count = max(segments, 8)
        let alpha = GeoAngle.radians(fromDegrees: angle)

        // An orthonormal frame about the axis.
        let reference = abs(m.x) < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 1, 0)
        guard let a = reference.cross(m).normalized else { return [] }
        let b = m.cross(a)

        var polylines: [[StereonetPoint]] = []
        var current: [StereonetPoint] = []
        var firstState: Bool?
        var lastState: Bool?

        for step in 0...count {
            let phi = 2 * Double.pi * Double(step) / Double(count)
            let v = m * cos(alpha) + (a * cos(phi) + b * sin(phi)) * sin(alpha)
            let aboveHorizon = v.up > 0
            guard let point = projectCurvePoint(v, using: projection) else { continue }

            if let previous = lastState, previous != aboveHorizon {
                if current.count > 1 { polylines.append(current) }
                current = []
            }
            if firstState == nil { firstState = aboveHorizon }
            current.append(point)
            lastState = aboveHorizon
        }
        if current.count > 1 { polylines.append(current) }

        // The sweep is a closed loop, so a cone that crosses the horizon twice comes out
        // as three runs rather than two: the arc containing φ = 0 is cut in half by where
        // the sweep happens to start. The two halves are one arc and are rejoined, minus
        // the point they share. Two circles on a sphere meet at most twice, so there are
        // never more than three runs to begin with.
        if polylines.count > 1, let first = firstState, let last = lastState, first == last {
            let tail = polylines.removeLast()
            polylines[0] = Array(tail.dropLast()) + polylines[0]
        }
        return polylines
    }

    /// The primitive circle, for drawing the edge of the net.
    public static func primitive(segments: Int = 180) -> [StereonetPoint] {
        let count = max(segments, 8)
        return (0...count).map { step in
            let phi = 2 * Double.pi * Double(step) / Double(count)
            return StereonetPoint(east: sin(phi), north: cos(phi))
        }
    }
}
