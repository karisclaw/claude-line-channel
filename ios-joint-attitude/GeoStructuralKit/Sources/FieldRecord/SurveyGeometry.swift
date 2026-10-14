import Foundation
import OrientationCore

/// One patch of exposed rock surface, for a survey whose sampling surface is not a
/// single plane or line.
public struct SurfaceFacet: Equatable, Sendable, Codable {

    public var orientation: PlaneOrientation
    public var areaSquareMetres: Double

    public init(orientation: PlaneOrientation, areaSquareMetres: Double) {
        self.orientation = orientation
        self.areaSquareMetres = areaSquareMetres
    }
}

/// How sampling bias can be corrected for a given survey geometry.
public enum BiasCorrectionMethod: String, Sendable, Codable {

    /// Classical Terzaghi: one sampling direction, weight `1 / cos(angle)` between the
    /// pole and that direction, capped.
    case terzaghi

    /// Area-weighted over a set of exposed facets, for a surface with many
    /// orientations.
    ///
    /// A single Terzaghi weight does not apply: there is no one sampling direction, and
    /// the correction has to work from the area-weighted probability that a
    /// discontinuity of a given attitude intersects the exposure at all. **Which
    /// formulation to use is a decision for the set-analysis module**, not something to
    /// settle here — so the geometry says that this is the method required, and asking
    /// for the weight before it exists fails loudly rather than returning a Terzaghi
    /// number that would be wrong.
    case areaWeightedSurface

    /// No correction is possible.
    case unavailable
}

/// How the discontinuities at a station were sampled.
///
/// Recorded because sampling bias depends on it: a scanline finds the joints that cross
/// it and misses those running parallel, and a window finds those that intersect its
/// face. The correction in the set-analysis module needs this geometry, so a station
/// logged without it can be described but not corrected.
public enum SurveyGeometry: Equatable, Sendable, Codable {

    /// A scanline: a tape stretched across the outcrop, with every discontinuity that
    /// crosses it logged.
    case scanline(line: LineOrientation, lengthMetres: Double)

    /// A borehole or core run, logged along its axis.
    ///
    /// Geometrically a scanline, kept as its own case because the provenance matters
    /// when the data is read later: a borehole samples rock a scanline on a face cannot
    /// reach, and its orientation bias is usually much stronger — a vertical hole is
    /// nearly blind to horizontal joints.
    case borehole(axis: LineOrientation, lengthMetres: Double)

    /// A window: a mapped area of the outcrop face.
    case window(face: PlaneOrientation, areaSquareMetres: Double)

    /// A trace map digitized from photogrammetry on a face that is effectively planar.
    ///
    /// Same geometry as a window, and corrected the same way; separate so that the
    /// record says how the traces were obtained, since a photogrammetric trace map and
    /// a hand-mapped window differ in what they can resolve.
    case traceMap(face: PlaneOrientation, areaSquareMetres: Double)

    /// A three-dimensional surface model — a point cloud or a mesh of the whole outcrop,
    /// whose exposed surface faces many directions.
    ///
    /// Carries the exposed surface as area-weighted facets, because that distribution is
    /// what any correction has to work from. See
    /// ``BiasCorrectionMethod/areaWeightedSurface``.
    case surfaceModel(facets: [SurfaceFacet])

    /// Discontinuities picked out individually, with no systematic sampling.
    ///
    /// Honest about what it is: selective sampling cannot be bias-corrected, because the
    /// bias is in the geologist's choice and no geometry describes it. Frequency and
    /// spacing statistics from such a station are not comparable with a scanline's.
    case selective

    /// Which correction applies to this geometry.
    public var biasCorrectionMethod: BiasCorrectionMethod {
        switch self {
        case .scanline, .borehole, .window, .traceMap: .terzaghi
        case .surfaceModel: .areaWeightedSurface
        case .selective: .unavailable
        }
    }

    /// The single sampling direction the Terzaghi correction works against: the
    /// scanline's or borehole's own direction, or the normal of the mapped face.
    ///
    /// `nil` where no single direction exists — a surface model — or where no correction
    /// is possible at all.
    public var samplingDirection: Vector3? {
        switch self {
        case .scanline(let line, _), .borehole(let line, _): line.downPlungeVector
        case .window(let face, _), .traceMap(let face, _): face.upwardNormal
        case .surfaceModel, .selective: nil
        }
    }

    /// The exposed surface as facets, for a geometry corrected by area weighting.
    public var surfaceFacets: [SurfaceFacet]? {
        switch self {
        case .surfaceModel(let facets): facets
        default: nil
        }
    }

    /// Length sampled, in metres, for the one-dimensional geometries.
    public var sampledLengthMetres: Double? {
        switch self {
        case .scanline(_, let length), .borehole(_, let length): length
        default: nil
        }
    }

    /// Area sampled, in square metres, for the two-dimensional geometries. A surface
    /// model reports the total area of its facets.
    public var sampledAreaSquareMetres: Double? {
        switch self {
        case .window(_, let area), .traceMap(_, let area): area
        case .surfaceModel(let facets): facets.reduce(0) { $0 + $1.areaSquareMetres }
        default: nil
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
