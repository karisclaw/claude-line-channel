import Foundation
import OrientationCore

/// How the discontinuities at a station were sampled.
///
/// Recorded because sampling bias depends on it: a scanline finds the joints that cross
/// it and misses those running parallel, and a window finds those that intersect its
/// face. The Terzaghi correction in the set-analysis module needs this geometry to
/// compute a weight, so a station logged without it can be described but not corrected.
public enum SurveyGeometry: Equatable, Sendable, Codable {

    /// A scanline: a tape stretched across the outcrop, with every discontinuity that
    /// crosses it logged.
    ///
    /// - Parameters:
    ///   - line: trend and plunge of the tape.
    ///   - lengthMetres: how much of it was logged.
    case scanline(line: LineOrientation, lengthMetres: Double)

    /// A window: a mapped area of the outcrop face.
    ///
    /// - Parameters:
    ///   - face: the attitude of the outcrop face the window lies in.
    ///   - areaSquareMetres: the mapped area.
    case window(face: PlaneOrientation, areaSquareMetres: Double)

    /// Discontinuities picked out individually, with no systematic sampling.
    ///
    /// Honest about what it is: selective sampling cannot be bias-corrected, because
    /// the bias is in the geologist's choice and no geometry describes it. Frequency and
    /// spacing statistics from such a station are not comparable with a scanline's.
    case selective

    /// `true` when a Terzaghi weight can be computed for this geometry.
    public var supportsTerzaghiCorrection: Bool {
        switch self {
        case .scanline, .window: true
        case .selective: false
        }
    }

    /// The sampling direction the Terzaghi correction works against: the scanline's own
    /// direction, or the normal of the window's face.
    ///
    /// The weight is `1 / cos(angle between the discontinuity's pole and this
    /// direction)`, capped — the cap matters, and lives with the correction itself in
    /// the set-analysis module rather than here.
    public var samplingDirection: Vector3? {
        switch self {
        case .scanline(let line, _): line.downPlungeVector
        case .window(let face, _): face.upwardNormal
        case .selective: nil
        }
    }
}

/// A photograph taken at a measurement, with the attitude of the camera when it was
/// taken.
///
/// The attitude is the point. A photograph of a joint face without knowing which way the
/// camera looked cannot be used to check an attitude afterwards, and checking afterwards
/// is the only defence against a measurement taken with the wrong placement selected.
public struct PhotoReference: Identifiable, Equatable, Sendable, Codable {

    public var id: UUID
    /// Name of the file inside the project's own storage. Not an absolute path: the
    /// project has to survive being zipped up and opened on another device.
    public var fileName: String
    public var capturedAt: Date
    /// Where the camera pointed — trend and plunge of the optical axis.
    public var cameraDirection: LineOrientation?
    /// The device attitude at capture, kept in full so a direction can be recomputed if
    /// the convention for `cameraDirection` ever changes.
    public var cameraAttitude: Quaternion?
    public var caption: String?

    public init(
        id: UUID = UUID(),
        fileName: String,
        capturedAt: Date,
        cameraDirection: LineOrientation? = nil,
        cameraAttitude: Quaternion? = nil,
        caption: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.capturedAt = capturedAt
        self.cameraDirection = cameraDirection
        self.cameraAttitude = cameraAttitude
        self.caption = caption
    }
}

/// A spoken note recorded at a measurement — faster than typing with cold hands or
/// gloves on, which is half the reason it is in the specification.
public struct VoiceMemoReference: Identifiable, Equatable, Sendable, Codable {

    public var id: UUID
    public var fileName: String
    public var recordedAt: Date
    public var duration: TimeInterval
    /// Filled in later if the note is transcribed; never required.
    public var transcript: String?

    public init(
        id: UUID = UUID(),
        fileName: String,
        recordedAt: Date,
        duration: TimeInterval,
        transcript: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.recordedAt = recordedAt
        self.duration = duration
        self.transcript = transcript
    }
}
