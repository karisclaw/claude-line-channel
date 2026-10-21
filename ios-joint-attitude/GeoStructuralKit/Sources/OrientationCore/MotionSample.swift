import Foundation

/// One frame of device motion, as `CMDeviceMotion` delivers it.
///
/// The package never talks to CoreMotion; the app layer builds these from
/// `CMDeviceMotion` and feeds them in. That keeps sampling, stillness detection and
/// averaging testable from synthetic streams, which is the only way to test them at
/// all — a unit test cannot shake a phone.
public struct MotionSample: Equatable, Sendable {

    /// `CMDeviceMotion.timestamp`: seconds since device boot.
    public let timestamp: TimeInterval

    /// Device-to-world rotation, world frame NWU referenced to true north.
    public let attitude: Quaternion

    /// `CMDeviceMotion.userAcceleration` in the **device** frame, in g.
    ///
    /// Gravity has already been removed, so this is ≈ zero when the phone is still —
    /// which is what makes it the right signal for stillness, and for the contact
    /// impulse.
    public let userAcceleration: Vector3

    /// `CMDeviceMotion.rotationRate` in the **device** frame, in rad/s.
    public let rotationRate: Vector3

    public init(
        timestamp: TimeInterval,
        attitude: Quaternion,
        userAcceleration: Vector3 = .zero,
        rotationRate: Vector3 = .zero
    ) {
        self.timestamp = timestamp
        self.attitude = attitude
        self.userAcceleration = userAcceleration
        self.rotationRate = rotationRate
    }
}

/// What a measurement is of.
public enum MeasurementTarget: String, CaseIterable, Sendable, Codable {
    case plane
    case lineation
}
