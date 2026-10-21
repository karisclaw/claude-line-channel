import Foundation

/// The result of averaging one burst of samples from a single measurement.
///
/// This is the A2 quality-control payload: an attitude plus how tightly the
/// samples agreed on it. A large ``angularStandardDeviation`` means the phone
/// moved, the rock face is rough, or the magnetometer is being disturbed — the
/// UI should say so rather than record a confident-looking number.
public struct AxialSummary: Equatable, Sendable {

    /// Mean axis as a unit vector, sign-aligned with the majority of the samples.
    ///
    /// The eigensolver's sign is arbitrary, so it is set from the samples to keep
    /// the mean pointing the same way they did — useful when the caller wants the
    /// measured outward direction. ``meanPlane`` and ``meanLine`` do not depend on
    /// it: both treat their input as an axis.
    public let meanAxis: Vector3

    public let sampleCount: Int

    /// Normalized orientation-tensor eigenvalues, descending, summing to 1.
    ///
    /// Carried through from the averaging step because the Woodcock fabric shape
    /// parameters in the set-analysis module are computed from exactly these.
    public let eigenvalues: [Double]

    /// Unit eigenvectors matching ``eigenvalues``.
    public let eigenvectors: [Vector3]

    /// RMS angular deviation of the samples about the mean axis, in degrees.
    ///
    /// `sqrt(Σθᵢ² / (n-1))`, where `θᵢ` is the **axial** angle between sample `i`
    /// and the mean. Zero for a single sample. This is a dispersion measure for one
    /// burst; it is deliberately *not* a Fisher concentration — Fisher `K` and `α95`
    /// belong to the set-level statistics, where the population is the joint set
    /// rather than one instrument reading.
    public let angularStandardDeviation: Double

    /// Mean axial angle between the samples and the mean axis, in degrees.
    public let meanAngularDeviation: Double

    /// Largest axial angle between any sample and the mean axis, in degrees.
    public let maxAngularDeviation: Double

    /// The mean axis read as a plane normal.
    public var meanPlane: PlaneOrientation? { PlaneOrientation(measuredNormal: meanAxis) }

    /// The mean axis read as a lineation.
    public var meanLine: LineOrientation? { LineOrientation(measuredAxis: meanAxis) }
}

/// Averaging for axial data — plane normals and lineations.
public enum AxialStatistics {

    /// Averages a burst of measured axes.
    ///
    /// Averaging goes through the orientation tensor rather than through the
    /// arithmetic mean of the vectors. For axial data the arithmetic mean is simply
    /// wrong: samples straddling vertical carry opposite signs and cancel, which
    /// would report a near-vertical joint as garbage. The principal eigenvector has
    /// no such failure mode and needs no pre-alignment.
    ///
    /// Returns `nil` if no sample has usable length.
    public static func summarize(_ axes: [Vector3]) -> AxialSummary? {
        let units = axes.compactMap(\.normalized)
        guard !units.isEmpty, let tensor = SymmetricMatrix3.orientationTensor(of: units) else {
            return nil
        }

        let eigen = tensor.eigen()
        var mean = eigen.principalVector

        // The eigensolver's sign is arbitrary. Point the mean the same way as the
        // samples did, so callers that care about the measured outward direction —
        // which face of the rock the phone was held against — can still recover it.
        let agreement = units.reduce(0.0) { $0 + $1.dot(mean) }
        if agreement < 0 { mean = -mean }

        let deviations = units.map { $0.axialAngle(to: mean) }
        let n = Double(units.count)
        let sumSquares = deviations.reduce(0.0) { $0 + $1 * $1 }
        let standardDeviation = units.count > 1 ? (sumSquares / (n - 1)).squareRoot() : 0

        return AxialSummary(
            meanAxis: mean,
            sampleCount: units.count,
            eigenvalues: eigen.values,
            eigenvectors: eigen.vectors,
            angularStandardDeviation: standardDeviation,
            meanAngularDeviation: deviations.reduce(0, +) / n,
            maxAngularDeviation: deviations.max() ?? 0
        )
    }

    /// Averages a burst of plane measurements via their normals.
    public static func summarize(planes: [PlaneOrientation]) -> AxialSummary? {
        summarize(planes.map(\.upwardNormal))
    }

    /// Averages a burst of lineation measurements via their down-plunge vectors.
    public static func summarize(lines: [LineOrientation]) -> AxialSummary? {
        summarize(lines.map(\.downPlungeVector))
    }
}
