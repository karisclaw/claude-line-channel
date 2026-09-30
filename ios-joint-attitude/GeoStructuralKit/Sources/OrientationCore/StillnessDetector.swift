import Foundation

/// When the phone counts as steady enough to start sampling.
///
/// The numbers are starting points, not measured constants: they need a session with
/// a real phone against real rock to settle, and the app should expose them.
/// Getting them slightly wrong costs a little waiting, not accuracy — the burst's own
/// ``AxialSummary/angularStandardDeviation`` is what judges whether a measurement was
/// steady enough to keep.
public struct StillnessCriteria: Equatable, Sendable {

    /// How far back to look.
    public var window: TimeInterval

    /// Largest acceptable standard deviation of the user-acceleration vector, in g.
    public var maximumAccelerationStandardDeviation: Double

    /// Largest acceptable rotation rate anywhere in the window, in rad/s.
    ///
    /// The default, 0.03 rad/s, is about 1.7°/s — over a 1.5 s burst that is at most
    /// a couple of degrees of drift, which the burst's angular standard deviation will
    /// report rather than hide.
    public var maximumRotationRate: Double

    /// How many samples the window must hold before any verdict is given.
    public var minimumSamples: Int

    public init(
        window: TimeInterval = 0.3,
        maximumAccelerationStandardDeviation: Double = 0.02,
        maximumRotationRate: Double = 0.03,
        minimumSamples: Int = 10
    ) {
        self.window = max(window, 0)
        self.maximumAccelerationStandardDeviation = max(maximumAccelerationStandardDeviation, 0)
        self.maximumRotationRate = max(maximumRotationRate, 0)
        self.minimumSamples = max(minimumSamples, 2)
    }
}

/// What the detector currently thinks.
public struct StillnessAssessment: Equatable, Sendable {

    public let isStill: Bool
    public let sampleCount: Int

    /// Time from the oldest to the newest sample in the window.
    public let windowSpan: TimeInterval

    /// Standard deviation of the user-acceleration **vector** about its mean, in g.
    /// `nil` until the window holds enough samples to have an opinion.
    public let accelerationStandardDeviation: Double?

    /// Largest rotation-rate magnitude in the window, in rad/s. `nil` as above.
    public let peakRotationRate: Double?

    /// `true` once there are enough samples for the verdict to mean anything.
    public var hasVerdict: Bool { accelerationStandardDeviation != nil }
}

/// Detects that the phone has been held still, over a sliding time window.
public struct StillnessDetector: Sendable {

    public let criteria: StillnessCriteria
    private var samples: [MotionSample] = []

    public init(criteria: StillnessCriteria = StillnessCriteria()) {
        self.criteria = criteria
    }

    /// Adds a sample and drops anything that has fallen out of the window.
    public mutating func add(_ sample: MotionSample) {
        samples.append(sample)
        let cutoff = sample.timestamp - criteria.window
        if let firstInside = samples.firstIndex(where: { $0.timestamp >= cutoff }), firstInside > 0 {
            samples.removeFirst(firstInside)
        }
    }

    public mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    public var assessment: StillnessAssessment {
        let span = (samples.last?.timestamp ?? 0) - (samples.first?.timestamp ?? 0)
        guard samples.count >= criteria.minimumSamples else {
            return StillnessAssessment(
                isStill: false,
                sampleCount: samples.count,
                windowSpan: span,
                accelerationStandardDeviation: nil,
                peakRotationRate: nil
            )
        }

        // Deviation of the acceleration *vector* about its mean, not of its magnitude:
        // a phone being rocked steadily can hold its magnitude nearly constant while
        // the direction swings, and a magnitude-only test would call that still.
        let n = Double(samples.count)
        let mean = samples.reduce(Vector3.zero) { $0 + $1.userAcceleration } / n
        let sumSquares = samples.reduce(0.0) { $0 + ($1.userAcceleration - mean).lengthSquared }
        let standardDeviation = (sumSquares / (n - 1)).squareRoot()
        let peakRotation = samples.map { $0.rotationRate.length }.max() ?? 0

        return StillnessAssessment(
            isStill: standardDeviation <= criteria.maximumAccelerationStandardDeviation
                && peakRotation <= criteria.maximumRotationRate,
            sampleCount: samples.count,
            windowSpan: span,
            accelerationStandardDeviation: standardDeviation,
            peakRotationRate: peakRotation
        )
    }
}
