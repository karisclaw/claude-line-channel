import Foundation
import OrientationCore

/// How a point contributes to the density at a node.
public enum ContourWeighting: String, CaseIterable, Sendable, Codable {

    /// Kamb's counting circle: every point inside it counts 1, everything outside 0.
    case kamb

    /// Kamb's criterion with a smooth weight that falls to zero at the edge of the
    /// circle, which removes the hard circle's step artefacts — a point crossing the
    /// boundary no longer changes the count by a whole unit.
    ///
    /// The weight used here is `(1 − (φ/ρ)²)²`. **The published "modified Kamb" weight
    /// may differ**; please check against your reference. What makes the σ scale
    /// meaningful is not the shape of the weight but the renormalization around it: the
    /// radius is re-solved so the expected count is still the same multiple of σ, and
    /// that is done for whatever weight is supplied. See ``KambParameters``.
    case modifiedKamb
}

/// The counting circle, and the statistics that make a σ scale mean something.
///
/// ## Where the circle's size comes from
///
/// Kamb's idea is to let the data decide the smoothing. For `N` axes and a counting
/// circle covering a fraction `a` of the hemisphere, a uniform distribution gives an
/// expected count `E = Na` with standard deviation `σ = √(Na(1−a))`. Choosing `a` so
/// that `E = kσ` ties the circle to the sample size: a large sample earns a small
/// circle. Kamb took `k = 3`, which gives
///
/// ```
/// Na = k²(1 − a)   ⟹   a = k² / (N + k²)   ⟹   a = 9 / (N + 9)
/// ```
///
/// and the angular radius follows from a spherical cap's area, `a = 1 − cos ρ`.
///
/// There is a second route to the same number, and it is worth stating because it is a
/// free check on the first: the equal-area projection preserves area, so the circle's
/// projected radius as a fraction of the primitive is `√a = 3/√(N + 9)` — the form
/// usually quoted. The two agree to machine precision, and a test asserts it.
///
/// ## Why a weighted version needs more than a weight
///
/// Change the weight and `E` and `σ` both change, so a σ scale computed for the hard
/// circle becomes meaningless. Here the moments are integrated for whatever weight is
/// in use, and the radius is re-solved so `E = kσ` still holds. The arithmetic rests on
/// one fact: for a **uniformly distributed axis**, the axial angle `φ` to any fixed
/// direction has density exactly `sin φ` on `0...90°`. So per sample,
/// `E/N = ∫w sin φ dφ` and `Var/N = ∫w² sin φ dφ − (∫w sin φ dφ)²`, which for the hard
/// circle reduce to `a` and `a(1−a)` — recovering the closed forms above, and tested
/// against them.
public struct KambParameters: Equatable, Sendable {

    public let sampleCount: Int
    public let weighting: ContourWeighting

    /// `E / σ`. Kamb's criterion is 3.
    public let sigmaCriterion: Double

    /// Angular radius of the counting circle, in degrees.
    public let countingCircleRadius: Double

    /// Expected weighted count under a uniform axial distribution.
    public let expectedCount: Double

    /// Standard deviation of that count under a uniform axial distribution.
    public let standardDeviation: Double

    /// Radius of the counting circle as a fraction of the primitive in the **equal-area**
    /// projection, for drawing it on the plot.
    ///
    /// Only meaningful for ``ContourWeighting/kamb``, where the circle has an edge: for
    /// the smooth weight it is where the weight reaches zero.
    public var projectedRadiusFraction: Double {
        let cap = 1 - cos(GeoAngle.radians(fromDegrees: countingCircleRadius))
        return cap.squareRoot()
    }

    /// Builds the parameters, solving for the radius that satisfies the criterion.
    ///
    /// Returns `nil` for fewer than two axes, where a density has nothing to say.
    public init?(
        sampleCount: Int,
        weighting: ContourWeighting = .kamb,
        sigmaCriterion: Double = 3
    ) {
        guard sampleCount >= 2, sigmaCriterion > 0 else { return nil }
        self.sampleCount = sampleCount
        self.weighting = weighting
        self.sigmaCriterion = sigmaCriterion

        let n = Double(sampleCount)
        switch weighting {
        case .kamb:
            // Closed form: a = k² / (N + k²).
            let area = sigmaCriterion * sigmaCriterion / (n + sigmaCriterion * sigmaCriterion)
            self.countingCircleRadius = GeoAngle.degrees(
                fromRadians: acos(GeoAngle.clamp(1 - area, -1, 1))
            )
            self.expectedCount = n * area
            self.standardDeviation = (n * area * (1 - area)).squareRoot()

        case .modifiedKamb:
            let radius = KambParameters.solveRadius(
                sampleCount: n, criterion: sigmaCriterion, weighting: weighting
            )
            let moments = KambParameters.moments(radius: radius, weighting: weighting)
            self.countingCircleRadius = GeoAngle.degrees(fromRadians: radius)
            self.expectedCount = n * moments.first
            self.standardDeviation = (n * max(moments.second - moments.first * moments.first, 0))
                .squareRoot()
        }
    }

    /// The weight a point at axial angle `phi` degrees from a node contributes.
    public func weight(atAxialAngle phi: Double) -> Double {
        KambParameters.weight(
            phi: GeoAngle.radians(fromDegrees: phi),
            radius: GeoAngle.radians(fromDegrees: countingCircleRadius),
            weighting: weighting
        )
    }

    // MARK: - The weight, and its moments

    static func weight(phi: Double, radius: Double, weighting: ContourWeighting) -> Double {
        guard phi < radius else { return 0 }
        switch weighting {
        case .kamb:
            return 1
        case .modifiedKamb:
            let t = phi / radius
            let shoulder = 1 - t * t
            return shoulder * shoulder
        }
    }

    /// `∫w sin φ dφ` and `∫w² sin φ dφ` over the weight's support, by midpoint quadrature.
    ///
    /// `sin φ` is the exact density of the axial angle under a uniform distribution, so
    /// these are the per-sample mean and second moment of the weight.
    ///
    /// The domain ends at `radius` rather than at `π / 2`. Beyond the radius the weight is
    /// identically zero, so those cells contribute nothing — but a cell that *straddles*
    /// the radius contributes the wrong thing: the hard circle's weight steps from 1 to 0
    /// there, and midpoint quadrature across a step is accurate only to `O(h)`, which cost
    /// about four decimal places and showed up as the closed forms `m₁ = m₂ = a` missing
    /// by ~1e-5. Ending the domain at the step leaves a smooth integrand and the usual
    /// `O(h²)`.
    static func moments(
        radius: Double,
        weighting: ContourWeighting,
        steps: Int = 20_000
    ) -> (first: Double, second: Double) {
        let support = min(radius, Double.pi / 2)
        guard support > 0, steps > 0 else { return (0, 0) }
        let h = support / Double(steps)
        var first = 0.0
        var second = 0.0
        for index in 0..<steps {
            let phi = (Double(index) + 0.5) * h
            let w = weight(phi: phi, radius: radius, weighting: weighting)
            guard w != 0 else { continue }
            let measure = sin(phi) * h
            first += w * measure
            second += w * w * measure
        }
        return (first, second)
    }

    /// The radius at which `E/σ` equals the criterion.
    ///
    /// `E/σ = √N · m₁ / √(m₂ − m₁²)` rises monotonically with the radius — a wider circle
    /// collects more of the sample relative to its own noise — so a bisection is enough
    /// and cannot land on the wrong root.
    static func solveRadius(
        sampleCount: Double,
        criterion: Double,
        weighting: ContourWeighting,
        iterations: Int = 60
    ) -> Double {
        var low = 1e-4
        var high = Double.pi / 2
        for _ in 0..<iterations {
            let middle = (low + high) / 2
            let moments = moments(radius: middle, weighting: weighting, steps: 4_000)
            let variance = max(moments.second - moments.first * moments.first, .leastNormalMagnitude)
            let ratio = sampleCount.squareRoot() * moments.first / variance.squareRoot()
            if ratio < criterion { low = middle } else { high = middle }
        }
        return (low + high) / 2
    }
}

/// A density field over the lower hemisphere, in units of σ.
public struct DensityGrid: Equatable, Sendable {

    /// Nodes across the full width of the primitive. Nodes outside it hold `nil`.
    public let resolution: Int

    /// Row-major, `resolution × resolution`. `nil` outside the primitive.
    public let values: [Double?]

    public let parameters: KambParameters

    /// Spacing between contour levels, in σ.
    public let contourInterval: Double

    public init(
        resolution: Int,
        values: [Double?],
        parameters: KambParameters,
        contourInterval: Double
    ) {
        self.resolution = resolution
        self.values = values
        self.parameters = parameters
        self.contourInterval = contourInterval
    }

    /// Density at a node, in σ. `nil` outside the primitive.
    public func value(column: Int, row: Int) -> Double? {
        guard column >= 0, column < resolution, row >= 0, row < resolution else { return nil }
        return values[row * resolution + column]
    }

    /// Where a node sits on a unit stereonet, in **equal-area** coordinates.
    ///
    /// Re-project these for display on a Wulff net; do not re-grid. The grid is uniform
    /// in equal-area space precisely so that it samples the hemisphere uniformly by
    /// area, which is what makes the σ scale hold — a uniform grid in equal-angle space
    /// would crowd the centre and bias every statistic computed from it.
    public func point(column: Int, row: Int) -> StereonetPoint {
        StereonetPoint(
            east: -1 + 2 * (Double(column) + 0.5) / Double(resolution),
            north: -1 + 2 * (Double(row) + 0.5) / Double(resolution)
        )
    }

    public var maximum: Double { values.compactMap { $0 }.max() ?? 0 }
    public var minimum: Double { values.compactMap { $0 }.min() ?? 0 }

    /// Mean density over the nodes inside the primitive, in σ.
    ///
    /// For a uniform sample this lands on ``KambParameters/sigmaCriterion`` — 3σ with
    /// Kamb's choice — because the grid samples the hemisphere by equal area. It is the
    /// cheapest check that the whole normalization is right, and a test asserts it.
    public var mean: Double {
        let inside = values.compactMap { $0 }
        guard !inside.isEmpty else { return 0 }
        return inside.reduce(0, +) / Double(inside.count)
    }

    /// Contour levels to draw, in σ: multiples of ``contourInterval`` up to the maximum.
    ///
    /// The uniform expectation sits at ``KambParameters/sigmaCriterion``, so with the
    /// default 2σ interval the levels straddle it and a contour above 4σ means something
    /// the rock did rather than something the sampling did.
    public var contourLevels: [Double] {
        guard contourInterval > 0, maximum > contourInterval else { return [] }
        let count = Int((maximum / contourInterval).rounded(.down))
        return (1...max(count, 1)).map { Double($0) * contourInterval }
    }
}

/// Kamb density estimation over the lower hemisphere.
public enum KambDensity {

    /// The density field of a set of axes.
    ///
    /// Axial throughout: a point is counted by its **axial** angle to a node, so a pole
    /// and its opposite contribute identically and the field is symmetric by
    /// construction rather than by convention. A test flips half the input and requires
    /// the field to be bit-identical.
    ///
    /// Returns `nil` for fewer than two usable axes.
    public static func grid(
        of axes: [Vector3],
        resolution: Int = 31,
        weighting: ContourWeighting = .kamb,
        sigmaCriterion: Double = 3,
        contourInterval: Double = 2
    ) -> DensityGrid? {
        let units = axes.compactMap(\.lowerHemisphereRepresentative)
        guard units.count >= 2,
              let parameters = KambParameters(
                  sampleCount: units.count, weighting: weighting, sigmaCriterion: sigmaCriterion
              ),
              parameters.standardDeviation > 0
        else { return nil }

        let size = max(resolution, 3)
        let radius = GeoAngle.radians(fromDegrees: parameters.countingCircleRadius)
        var values = [Double?](repeating: nil, count: size * size)

        for row in 0..<size {
            for column in 0..<size {
                let point = StereonetPoint(
                    east: -1 + 2 * (Double(column) + 0.5) / Double(size),
                    north: -1 + 2 * (Double(row) + 0.5) / Double(size)
                )
                guard point.isInsidePrimitive,
                      let node = Stereonet.axis(at: point, using: .equalArea)
                else { continue }

                var total = 0.0
                for unit in units {
                    let phi = acos(GeoAngle.clamp(abs(unit.dot(node)), 0, 1))
                    total += KambParameters.weight(phi: phi, radius: radius, weighting: weighting)
                }
                values[row * size + column] = total / parameters.standardDeviation
            }
        }

        return DensityGrid(
            resolution: size,
            values: values,
            parameters: parameters,
            contourInterval: contourInterval
        )
    }

    /// The density at one direction, without building a grid — for reading off the value
    /// at a set's mean, or under the geologist's finger.
    public static func density(
        at direction: Vector3,
        of axes: [Vector3],
        weighting: ContourWeighting = .kamb,
        sigmaCriterion: Double = 3
    ) -> Double? {
        let units = axes.compactMap(\.lowerHemisphereRepresentative)
        guard let node = direction.normalized,
              units.count >= 2,
              let parameters = KambParameters(
                  sampleCount: units.count, weighting: weighting, sigmaCriterion: sigmaCriterion
              ),
              parameters.standardDeviation > 0
        else { return nil }

        let radius = GeoAngle.radians(fromDegrees: parameters.countingCircleRadius)
        let total = units.reduce(0.0) { sum, unit in
            sum + KambParameters.weight(
                phi: acos(GeoAngle.clamp(abs(unit.dot(node)), 0, 1)),
                radius: radius,
                weighting: weighting
            )
        }
        return total / parameters.standardDeviation
    }
}

/// A deterministic, exactly area-uniform set of axes on the hemisphere.
///
/// Used to check that a density field normalizes correctly: the mean over the grid has
/// to come back to the σ criterion. A pseudo-random sample would do the same job with
/// sampling noise on top, so this is the stricter instrument — and having it in the
/// library rather than the tests means the app can show the geologist what "no
/// preferred orientation" actually looks like on their own net.
public enum UniformAxialSample {

    /// `count` axes spread by the golden-angle spiral, uniform in `cos θ` and therefore
    /// uniform by area.
    public static func axes(count: Int) -> [Vector3] {
        guard count > 0 else { return [] }
        let golden = Double.pi * (3 - 5.0.squareRoot())
        return (0..<count).compactMap { index in
            let up = (Double(index) + 0.5) / Double(count)      // cos θ from the pole
            let ring = (1 - up * up).squareRoot()
            let phi = Double(index) * golden
            return Vector3(ring * cos(phi), ring * sin(phi), up).lowerHemisphereRepresentative
        }
    }
}
