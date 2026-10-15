import Foundation
import OrientationCore
import FieldRecord

/// What the app knows about the surroundings at the moment of a measurement.
///
/// Pushed in as it changes rather than read on demand, so the recorder stays free of
/// CoreLocation and CoreMotion and a test can hand it any situation.
public struct MeasurementContext: Equatable, Sendable {

    public var location: MeasurementLocation?
    public var magneticEnvironment: MagneticEnvironment?
    public var declination: MagneticDeclination?

    public init(
        location: MeasurementLocation? = nil,
        magneticEnvironment: MagneticEnvironment? = nil,
        declination: MagneticDeclination? = nil
    ) {
        self.location = location
        self.magneticEnvironment = magneticEnvironment
        self.declination = declination
    }

    public static let unknown = MeasurementContext()
}

/// What the geologist is working on: which station, with what settings, and what was
/// measured last.
public struct FieldSessionState: Equatable, Sendable {

    public var projectID: UUID
    public var stationID: UUID

    /// The device setup, sticky between measurements.
    public var geometry: MeasurementGeometry

    public var target: MeasurementTarget
    public var carryForwardPolicy: CarryForwardPolicy

    /// The previous measurement at this station, which the next one inherits from.
    /// `nil` at the start of a station.
    public var lastRecord: MeasurementRecord?

    public init(
        projectID: UUID,
        stationID: UUID,
        geometry: MeasurementGeometry = .default,
        target: MeasurementTarget = .plane,
        carryForwardPolicy: CarryForwardPolicy = .standard,
        lastRecord: MeasurementRecord? = nil
    ) {
        self.projectID = projectID
        self.stationID = stationID
        self.geometry = geometry
        self.target = target
        self.carryForwardPolicy = carryForwardPolicy
        self.lastRecord = lastRecord
    }
}

/// Drives one measurement from the first press to a saved record.
///
/// Every decision lives here rather than in the view, because the view cannot be tested
/// on this machine and this can: the recorder is a value type fed discrete events, so a
/// test plays a whole gloved, one-handed, screen-never-looked-at workflow through it in
/// microseconds.
///
/// ## What a press means
///
/// There is one button, and it may be a Bluetooth key the geologist cannot see. So the
/// same press has to mean the obviously right thing in every state:
///
/// | State | A press means |
/// |---|---|
/// | idle, or just saved | start measuring |
/// | settling, collecting | **cancel** — not "start another" |
/// | review, nothing flagged | accept and save |
/// | review, something flagged | refuse, and say so another way |
///
/// Cancelling on a second press is the important one. With a key in a pocket there is no
/// way to tell a deliberate second press from a fumbled one, and starting a second burst
/// would leave the first discarded silently. Cancelling is recoverable; a lost
/// measurement is not.
public struct MeasurementRecorder: Sendable {

    /// A finished burst waiting for a decision.
    public struct PendingMeasurement: Equatable, Sendable {
        public let burst: BurstResult
        public let context: MeasurementContext
        public let warnings: [MeasurementWarning]
        /// `true` when at least one warning withdraws the blind confirmation path.
        public let requiresALook: Bool
    }

    public enum Stage: Equatable, Sendable {
        case idle
        case settling(StillnessAssessment)
        case collecting(progress: Double, samples: Int)
        case review(PendingMeasurement)
        case saved(MeasurementRecord)
    }

    public enum Event: Equatable, Sendable {
        /// The one button, wherever it came from: the screen, or an external key.
        case press(at: Date)
        case motion(MotionSample)
        case contextUpdate(MeasurementContext)
        /// An explicit, deliberate confirmation made while looking at the screen.
        case confirmOnScreen
        case discard
    }

    public enum Outcome: Equatable, Sendable {
        case unchanged
        case started
        case progressed
        case cancelled
        case readyForReview(PendingMeasurement)
        /// A blind press was refused because something is flagged. Give this its own
        /// haptic: it is the one outcome the geologist cannot see.
        case refusedBlindConfirmation([MeasurementWarning])
        case saved(MeasurementRecord)
        case discarded
        /// A press arrived too soon after the last one — key repeat, or a fumble.
        case ignoredRepeatPress
    }

    // MARK: Configuration

    public var session: FieldSessionState
    public var policy: ReviewPolicy
    public var burstCriteria: BurstCriteria
    public var stillnessCriteria: StillnessCriteria
    public var placementCriteria: PlacementCrossCheck.Criteria

    /// How long after an accepted press another is ignored.
    ///
    /// A Bluetooth key held down repeats, and a cold thumb double-taps. 0.35 s swallows
    /// both while still allowing the deliberate second press that accepts a measurement.
    /// Needs checking against the actual remote.
    public var repeatPressInterval: TimeInterval

    /// Wall clock, injected so a test can place a record at a known time.
    public var now: @Sendable () -> Date

    // MARK: State

    public private(set) var stage: Stage = .idle
    public private(set) var context: MeasurementContext = .unknown

    private var collector: BurstCollector?
    private var impulseWindow: [MotionSample] = []
    private var lastAcceptedPress: Date?

    public init(
        session: FieldSessionState,
        policy: ReviewPolicy = .standard,
        burstCriteria: BurstCriteria = BurstCriteria(),
        stillnessCriteria: StillnessCriteria = StillnessCriteria(),
        placementCriteria: PlacementCrossCheck.Criteria = PlacementCrossCheck.Criteria(),
        repeatPressInterval: TimeInterval = 0.35,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.session = session
        self.policy = policy
        self.burstCriteria = burstCriteria
        self.stillnessCriteria = stillnessCriteria
        self.placementCriteria = placementCriteria
        self.repeatPressInterval = max(repeatPressInterval, 0)
        self.now = now
    }

    // MARK: Events

    @discardableResult
    public mutating func handle(_ event: Event) -> Outcome {
        switch event {
        case .contextUpdate(let update):
            context = update
            return .unchanged
        case .press(let date):
            return press(at: date)
        case .motion(let sample):
            return motion(sample)
        case .confirmOnScreen:
            return confirm(blind: false)
        case .discard:
            guard case .review = stage else { return .unchanged }
            impulseWindow.removeAll(keepingCapacity: true)
            reset()
            return .discarded
        }
    }

    /// Throws away anything in progress and returns to idle. The settings and the
    /// previous record are kept, so the next measurement still inherits them.
    public mutating func reset() {
        collector = nil
        impulseWindow.removeAll(keepingCapacity: true)
        stage = .idle
    }

    // MARK: - Press

    private mutating func press(at date: Date) -> Outcome {
        if let last = lastAcceptedPress, date.timeIntervalSince(last) < repeatPressInterval {
            return .ignoredRepeatPress
        }
        lastAcceptedPress = date

        switch stage {
        case .idle, .saved:
            start()
            return .started

        case .settling, .collecting:
            // Not "start another". See the note on this type.
            reset()
            return .cancelled

        case .review(let pending):
            guard !pending.requiresALook else {
                return .refusedBlindConfirmation(pending.warnings)
            }
            return confirm(blind: true)
        }
    }

    private mutating func start() {
        let fresh = BurstCollector(
            target: session.target,
            geometry: session.geometry,
            criteria: burstCriteria,
            stillness: stillnessCriteria
        )
        collector = fresh
        // The impulse window is deliberately *not* cleared here. See `motion(_:)`.
        stage = MeasurementRecorder.stage(for: fresh.status) ?? .idle
    }

    /// Maps a collector status onto a stage. `nil` for `.finished`, which the caller
    /// turns into a review instead.
    ///
    /// Reading the stillness assessment back out of the collector rather than building
    /// one: `StillnessAssessment` is constructed inside OrientationCore, which is where
    /// it should stay — a module that could fabricate one could fabricate a verdict.
    private static func stage(for status: BurstCollector.Status) -> Stage? {
        switch status {
        case .settling(let assessment), .restarted(let assessment): .settling(assessment)
        case .collecting(let progress, let samples): .collecting(progress: progress, samples: samples)
        case .finished: nil
        }
    }

    // MARK: - Motion

    private mutating func motion(_ sample: MotionSample) -> Outcome {
        // The rolling window is kept **while idle too**, which is the whole point of it.
        // The phone is placed against the rock and *then* the button is pressed — that is
        // the natural order with a key in the other hand — so the contact impulse has
        // already happened by the time a burst begins. A window that only started
        // filling at the press would be empty of the one thing it exists to hold, and
        // the placement cross-check would never have an opinion about anything.
        switch stage {
        case .idle, .saved, .settling:
            appendToImpulseWindow(sample)
        case .collecting, .review:
            break
        }

        guard var active = collector else { return .unchanged }
        let status = active.add(sample)
        collector = active

        guard case .finished(let result) = status else {
            stage = MeasurementRecorder.stage(for: status) ?? stage
            return .progressed
        }

        collector = nil
        let pending = makePending(from: result)
        stage = .review(pending)

        if policy.autoConfirmWhenClean, !pending.requiresALook {
            return confirm(blind: true)
        }
        return .readyForReview(pending)
    }

    private mutating func appendToImpulseWindow(_ sample: MotionSample) {
        impulseWindow.append(sample)
        if impulseWindow.count > MeasurementRecorder.impulseWindowLimit {
            impulseWindow.removeFirst(impulseWindow.count - MeasurementRecorder.impulseWindowLimit)
        }
    }

    /// How many samples of motion to keep for the placement cross-check.
    ///
    /// About a second at 64 Hz: long enough to span placing the phone and reaching for
    /// the button, short enough that the walk up to the outcrop does not drown the
    /// impulse in ordinary arm movement.
    static let impulseWindowLimit = 64

    // MARK: - Review

    private func makePending(from burst: BurstResult) -> PendingMeasurement {
        // The surroundings are snapshotted now, when the attitude was determined, not at
        // confirmation: the geologist may walk on before deciding, and a position
        // recorded thirty metres along the exposure belongs to a different joint.
        let snapshot = context
        var warnings: [MeasurementWarning] = []

        if let assessment = snapshot.magneticEnvironment.map({ MagneticAssessment.assess($0) }),
           assessment.isDisturbed {
            warnings.append(.magneticDisturbance(assessment))
        }

        if burst.target == .plane {
            let verdict = PlacementCrossCheck.assess(
                contactImpulse: impulseWindow,
                selected: session.geometry.placement,
                criteria: placementCriteria
            )
            if verdict.disagrees, let implied = verdict.impliedAxis {
                warnings.append(
                    .placementDisagreement(selected: verdict.selectedAxis, implied: implied)
                )
            }
        }

        if burst.angularStandardDeviation > policy.maximumAngularStandardDeviation {
            warnings.append(
                .excessiveScatter(
                    degrees: burst.angularStandardDeviation,
                    limit: policy.maximumAngularStandardDeviation
                )
            )
        }

        if !burst.meetsRequestedSampleRate {
            warnings.append(
                .sampleRateShortfall(
                    effective: burst.effectiveSampleRate,
                    requested: burstCriteria.requestedSampleRate
                )
            )
        }

        if snapshot.location?.hasValidHorizontalPosition != true {
            warnings.append(.positionUnavailable)
        }

        // The description this record will inherit, checked against the type it will
        // inherit — not against the previous record's type, which may not be carried.
        if session.carryForwardPolicy.isrm, let previous = session.lastRecord {
            let inheritedType = session.carryForwardPolicy.discontinuityType
                ? previous.discontinuityType
                : MeasurementRecord.defaultDiscontinuityType
            for issue in previous.isrm.inconsistencies(for: inheritedType) {
                warnings.append(.descriptionInconsistency(issue))
            }
        }

        return PendingMeasurement(
            burst: burst,
            context: snapshot,
            warnings: warnings,
            requiresALook: warnings.contains { policy.requiresALook(at: $0) }
        )
    }

    private mutating func confirm(blind: Bool) -> Outcome {
        guard case .review(let pending) = stage else { return .unchanged }
        if blind, pending.requiresALook {
            return .refusedBlindConfirmation(pending.warnings)
        }

        let record = makeRecord(from: pending)
        session.lastRecord = record
        stage = .saved(record)
        // A fresh measurement needs fresh evidence. Carrying the impulse over would let
        // a stale one be attributed to the next measurement, and a wrong opinion is far
        // worse than no opinion — which is what an empty window produces.
        impulseWindow.removeAll(keepingCapacity: true)
        return .saved(record)
    }

    private func makeRecord(from pending: PendingMeasurement) -> MeasurementRecord {
        let timestamp = now()
        var record: MeasurementRecord

        if let previous = session.lastRecord {
            record = MeasurementRecord.next(
                after: previous,
                policy: session.carryForwardPolicy,
                timestamp: timestamp
            )
        } else {
            record = MeasurementRecord(timestamp: timestamp, mode: .contact)
        }

        // Always `.contact`: this recorder is the contact path, driven by a motion
        // burst. A LiDAR measurement arrives through the non-contact path and sets its
        // own mode, so the carried-forward value is overridden here on purpose.
        record.mode = .contact
        record.geometry = session.geometry
        record.plane = pending.burst.plane
        record.lineation = pending.burst.line
        record.angularStandardDeviation = pending.burst.angularStandardDeviation
        record.sampleCount = pending.burst.sampleCount
        record.measuredFaceAzimuth = pending.burst.target == .plane
            ? pending.burst.measuredDirection.azimuth
            : nil
        record.location = pending.context.location
        record.magneticEnvironment = pending.context.magneticEnvironment
        record.declination = pending.context.declination
        return record
    }
}
