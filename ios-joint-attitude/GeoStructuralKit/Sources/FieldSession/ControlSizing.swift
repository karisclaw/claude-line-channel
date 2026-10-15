import Foundation

/// How big the controls are, and where the one that matters has to sit.
///
/// Numbers rather than opinions, in one place, so the screens read from here and a
/// change lands everywhere at once.
///
/// The gloved figures are a starting point and need a session in the field with the
/// gloves actually worn. Getting them wrong is not a correctness problem — it is a
/// "tapped the wrong thing with a cold hand" problem, which no test on this machine can
/// detect.
public struct ControlSizing: Equatable, Sendable, Codable {

    public enum Mode: String, CaseIterable, Sendable, Codable {
        case standard
        case gloved
    }

    public var mode: Mode

    /// Smallest tappable edge, in points.
    ///
    /// 44 is Apple's published minimum for a bare fingertip. A gloved finger has a much
    /// larger and less certain contact patch, so the gloved figure is well above it.
    public var minimumTouchTargetPoints: Double

    /// Height of the one control that takes the measurement.
    public var primaryActionHeightPoints: Double

    /// Clear space between adjacent controls.
    ///
    /// This matters as much as the target size: two large buttons with no gap between
    /// them are still one ambiguous region to a glove.
    public var spacingPoints: Double

    /// Multiplier on body text.
    public var textScale: Double

    /// Fraction of the screen height, measured from the bottom, within which a
    /// one-handed thumb can reach comfortably.
    ///
    /// The primary action belongs inside this band. Anything above it is a two-handed
    /// control, which on a slope with a hammer in the other hand means it will not be
    /// used.
    public var thumbReachFraction: Double

    public init(
        mode: Mode,
        minimumTouchTargetPoints: Double,
        primaryActionHeightPoints: Double,
        spacingPoints: Double,
        textScale: Double,
        thumbReachFraction: Double
    ) {
        self.mode = mode
        self.minimumTouchTargetPoints = minimumTouchTargetPoints
        self.primaryActionHeightPoints = primaryActionHeightPoints
        self.spacingPoints = spacingPoints
        self.textScale = textScale
        self.thumbReachFraction = min(max(thumbReachFraction, 0), 1)
    }

    public static let standard = ControlSizing(
        mode: .standard,
        minimumTouchTargetPoints: 44,
        primaryActionHeightPoints: 64,
        spacingPoints: 12,
        textScale: 1,
        thumbReachFraction: 0.5
    )

    public static let gloved = ControlSizing(
        mode: .gloved,
        minimumTouchTargetPoints: 68,
        primaryActionHeightPoints: 110,
        spacingPoints: 24,
        textScale: 1.25,
        thumbReachFraction: 0.45
    )

    public static func sizing(for mode: Mode) -> ControlSizing {
        switch mode {
        case .standard: .standard
        case .gloved: .gloved
        }
    }

    /// Whether a control of this height, with its top at `topPoints` from the top of a
    /// screen `screenHeightPoints` tall, falls inside the one-handed reach band.
    public func isWithinThumbReach(
        topPoints: Double,
        heightPoints: Double,
        screenHeightPoints: Double
    ) -> Bool {
        guard screenHeightPoints > 0 else { return false }
        let bandTop = screenHeightPoints * (1 - thumbReachFraction)
        return topPoints >= bandTop && topPoints + heightPoints <= screenHeightPoints
    }
}
