import Foundation

/// How long to sample, and how fast.
public struct BurstCriteria: Equatable, Sendable {

    /// The rate the app asked CoreMotion for, in Hz. Used only to judge whether the
    /// delivered stream kept up — the burst ends on elapsed time, not on a count.
    public var requestedSampleRate: Double

    /// How long to collect for. The project specification says 1–2 s.
    public var duration: TimeInterval

    /// Fraction of the expected samples that must actually arrive for the burst to
    /// count as having met its rate.
    public var acceptableSampleRateFraction: Double

    /// Whether movement during collection discards the burst and starts again.
    ///
    /// On by default. A burst that includes the moment the phone slipped averages the
    /// slip into the attitude, and the resulting angular standard deviation may still
    /// look acceptable if the slip was short.
    public var requiresStillnessThroughout: Bool

    public init(
        requestedSampleRate: Double = 50,
        duration: TimeInterval = 1.5,
        acceptableSampleRateFraction: Double = 0.8,
        requiresStillnessThroughout: Bool = true
    ) {
        self.requestedSampleRate = max(requestedSampleRate, 1)
        self.duration = GeoAngle.clamp(duration, 0.1, 10)
        self.acceptableSampleRateFraction = GeoAngle.clamp(acceptableSampleRateFraction, 0, 1)
        self.requiresStillnessThroughout = requiresStillnessThroughout
    }
}

/// A finished burst: the averaged attitude and everything needed to judge it.
public struct BurstResult: Equatable, Sendable {

    public let target: MeasurementTarget
    public let geometry: MeasurementGeometry

    /// The axial average of the burst, with its dispersion. For a plane this averages
    /// the face's outward normal; for a lineation, the direction along the edge.
    public let summary: AxialSummary

    public let sampleCount: Int
    public let duration: TimeInterval

    /// Samples actually delivered per second.
    public let effectiveSampleRate: Double

    /// `false` when the stream fell short of the requested rate — the average is still
    /// valid, just built from fewer samples than intended.
    public let meetsRequestedSampleRate: Bool

    /// The averaged plane, for a planar measurement.
    public var plane: PlaneOrientation? {
        target == .plane ? summary.meanPlane : nil
    }

    /// The averaged lineation, for a linear measurement.
    public var line: LineOrientation? {
        target == .lineation ? summary.meanLine : nil
    }

    /// The measured direction, averaged over the burst — the rock face's outward
    /// normal, or the direction along the structure.
    ///
    /// Signed, unlike the attitude. For a vertical joint this is the only record of
    /// which face the phone was held against.
    public var measuredDirection: Vector3 { summary.meanAxis }

    /// Angular scatter of the burst, in degrees. The headline quality figure.
    public var angularStandardDeviation: Double { summary.angularStandardDeviation }
}

/// Collects one burst: waits for the phone to be still, samples for the requested
/// duration, and averages.
///
/// Driven entirely by samples handed to ``add(_:)``, with no timers and no
/// concurrency, so a test can play a whole measurement through it in microseconds.
public struct BurstCollector: Sendable {

    public enum Status: Equatable, Sendable {
        /// Waiting for the phone to settle.
        case settling(StillnessAssessment)
        /// Collecting. `progress` runs 0...1 over the requested duration.
        case collecting(progress: Double, samples: Int)
        /// The phone moved mid-burst; what had been collected was discarded.
        /// Collection restarts as soon as it is still again.
        case restarted(StillnessAssessment)
        /// Done.
        case finished(BurstResult)
    }

    public let target: MeasurementTarget
    public let geometry: MeasurementGeometry
    public let criteria: BurstCriteria

    public private(set) var status: Status

    private var detector: StillnessDetector
    private var collected: [MotionSample] = []
    private var startTimestamp: TimeInterval?

    public init(
        target: MeasurementTarget,
        geometry: MeasurementGeometry = .default,
        criteria: BurstCriteria = BurstCriteria(),
        stillness: StillnessCriteria = StillnessCriteria()
    ) {
        self.target = target
        self.geometry = geometry
        self.criteria = criteria
        self.detector = StillnessDetector(criteria: stillness)
        self.status = .settling(
            StillnessAssessment(
                isStill: false, sampleCount: 0, windowSpan: 0,
                accelerationStandardDeviation: nil, peakRotationRate: nil
            )
        )
    }

    /// The device axis being averaged, which depends on both the target and how the
    /// phone is being held.
    public var measuredAxis: DeviceAxis {
        switch target {
        case .plane: geometry.placement.outwardNormalAxis
        case .lineation: geometry.edge.axis
        }
    }

    /// Feeds one sample and returns the new status.
    ///
    /// Samples arriving after the burst has finished are ignored, so a caller that
    /// keeps the motion stream running does not have to race to stop it.
    @discardableResult
    public mutating func add(_ sample: MotionSample) -> Status {
        if case .finished = status { return status }

        detector.add(sample)
        let assessment = detector.assessment

        if startTimestamp == nil {
            guard assessment.isStill else {
                status = .settling(assessment)
                return status
            }
            startTimestamp = sample.timestamp
        }

        if criteria.requiresStillnessThroughout, assessment.hasVerdict, !assessment.isStill {
            collected.removeAll(keepingCapacity: true)
            startTimestamp = nil
            status = .restarted(assessment)
            return status
        }

        collected.append(sample)
        let elapsed = sample.timestamp - (startTimestamp ?? sample.timestamp)

        guard elapsed < criteria.duration else {
            if let result = finish(elapsed: elapsed) {
                status = .finished(result)
            } else {
                // Every attitude in the burst was degenerate. Discard and start over
                // rather than sitting in `collecting` forever.
                collected.removeAll(keepingCapacity: true)
                startTimestamp = nil
                status = .restarted(assessment)
            }
            return status
        }

        status = .collecting(
            progress: GeoAngle.clamp(elapsed / criteria.duration, 0, 1),
            samples: collected.count
        )
        return status
    }

    /// Throws the burst away and starts over.
    public mutating func reset() {
        detector.reset()
        collected.removeAll(keepingCapacity: true)
        startTimestamp = nil
        status = .settling(
            StillnessAssessment(
                isStill: false, sampleCount: 0, windowSpan: 0,
                accelerationStandardDeviation: nil, peakRotationRate: nil
            )
        )
    }

    private func finish(elapsed: TimeInterval) -> BurstResult? {
        let axis = measuredAxis
        let directions = collected.compactMap {
            DeviceAttitude.worldVector(of: axis, for: $0.attitude)
        }
        guard let summary = AxialStatistics.summarize(directions) else { return nil }

        let rate = elapsed > 0 ? Double(collected.count - 1) / elapsed : 0
        return BurstResult(
            target: target,
            geometry: geometry,
            summary: summary,
            sampleCount: collected.count,
            duration: elapsed,
            effectiveSampleRate: rate,
            meetsRequestedSampleRate:
                rate >= criteria.requestedSampleRate * criteria.acceptableSampleRateFraction
        )
    }
}
