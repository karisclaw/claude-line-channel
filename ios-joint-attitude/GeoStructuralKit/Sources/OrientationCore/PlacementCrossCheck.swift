import Foundation

/// Cross-checks the selected placement against the impulse recorded when the phone was
/// pressed against the rock.
///
/// **It never changes the selection.** Pressing the phone onto a face produces a
/// deceleration along that face's normal, so the axis carrying most of the impulse
/// energy is usually the contact axis — but "usually" is the problem. Placing the phone
/// gently produces no impulse at all, sliding it into position tangentially produces one
/// along the wrong axis, and hand tremor produces one in no particular direction. A
/// wrong choice of contact axis yields an attitude 90° out that looks entirely
/// plausible, and nothing on screen would reveal it.
///
/// So the arrangement is: the geologist selects, the selection sticks between
/// measurements, and this raises a warning when the impulse disagrees. A mechanism that
/// fails in ordinary use must not be the one that silently decides.
///
/// Only the axis *pair* is ever judged. Which way round the phone is cannot be
/// recovered from an impulse, and does not need to be: both placements on one axis are
/// the two faces of a single plane and give the same attitude.
public enum PlacementCrossCheck {

    public struct Criteria: Equatable, Sendable {

        /// Below this peak user acceleration, in g, the phone was placed too gently for
        /// the impulse to mean anything and no opinion is offered.
        public var minimumPeakAcceleration: Double

        /// Share of the impulse energy the leading axis must hold before the check will
        /// name it. Below this the impulse was not directional enough.
        public var minimumConfidence: Double

        public init(minimumPeakAcceleration: Double = 0.15, minimumConfidence: Double = 0.6) {
            self.minimumPeakAcceleration = max(minimumPeakAcceleration, 0)
            self.minimumConfidence = GeoAngle.clamp(minimumConfidence, 1.0 / 3.0, 1)
        }
    }

    public struct Verdict: Equatable, Sendable {

        /// The axis implied by what the geologist selected.
        public let selectedAxis: DeviceAxisPair

        /// The axis the impulse points to, or `nil` when the check has no opinion.
        public let impliedAxis: DeviceAxisPair?

        /// Share of the impulse energy on the leading axis, `1/3...1`.
        public let confidence: Double

        /// Largest user-acceleration magnitude in the window, in g.
        public let peakAcceleration: Double

        /// `true` only when the check has a confident opinion and it differs from the
        /// selection. This is a prompt to the geologist, never a correction.
        public var disagrees: Bool {
            guard let implied = impliedAxis else { return false }
            return implied != selectedAxis
        }

        public var hasOpinion: Bool { impliedAxis != nil }
    }

    /// Assesses the window of samples spanning the moment of contact.
    public static func assess(
        contactImpulse samples: [MotionSample],
        selected: DevicePlacement,
        criteria: Criteria = Criteria()
    ) -> Verdict {
        let selectedAxis = selected.contactAxisPair

        var energy = (x: 0.0, y: 0.0, z: 0.0)
        var peak = 0.0
        for sample in samples {
            let a = sample.userAcceleration
            energy.x += a.x * a.x
            energy.y += a.y * a.y
            energy.z += a.z * a.z
            peak = max(peak, a.length)
        }

        let total = energy.x + energy.y + energy.z
        guard total > 0, peak >= criteria.minimumPeakAcceleration else {
            return Verdict(
                selectedAxis: selectedAxis,
                impliedAxis: nil,
                confidence: 0,
                peakAcceleration: peak
            )
        }

        let ranked: [(DeviceAxisPair, Double)] = [(.x, energy.x), (.y, energy.y), (.z, energy.z)]
        let leading = ranked.max { $0.1 < $1.1 }!
        let confidence = leading.1 / total

        return Verdict(
            selectedAxis: selectedAxis,
            impliedAxis: confidence >= criteria.minimumConfidence ? leading.0 : nil,
            confidence: confidence,
            peakAcceleration: peak
        )
    }
}
