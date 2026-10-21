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

/// The geometric element that does the sampling.
///
/// A line and a plane bias the data **in opposite directions**, and keeping them as
/// distinct cases is what stops one being given the other's formula. A joint running
/// parallel to the outcrop face is the easiest thing in the world for a scanline lying in
/// that face to cross, and the hardest thing for the face itself to show as a trace. Hand
/// a face normal to the scanline formula and that joint comes out needing no correction
/// at all, when in truth it is almost invisible.
public enum SamplingElement: Equatable, Sendable, Codable {

    /// A line — a scanline laid across the outcrop, or a borehole axis.
    case line(LineOrientation)

    /// A plane — a mapped face, or one facet of a surface model.
    case plane(PlaneOrientation)

    /// Sine of the angle between `discontinuity` and this element, `0...1`.
    ///
    /// This single quantity is what sampling bias runs on: the apparent frequency of a
    /// set is proportional to it, so the bias weight is its reciprocal. It is written
    /// once, here, because the two cases reduce to different expressions of the same
    /// geometry:
    ///
    /// - against a **line** `s`, the angle between a plane and a line gives
    ///   `|pole · s|` — this is Terzaghi's original relation, where a borehole along the
    ///   pole samples best and one lying in the plane never samples at all;
    /// - against a **plane** with normal `m`, the angle between two planes gives
    ///   `|pole × m|` — a face shows the most traces of a set perpendicular to it and
    ///   none at all of a set parallel to it.
    public func samplingEfficiency(for discontinuity: PlaneOrientation) -> Double {
        let pole = discontinuity.upwardNormal
        switch self {
        case .line(let line):
            return GeoAngle.clamp(abs(pole.dot(line.downPlungeVector)), 0, 1)
        case .plane(let face):
            return GeoAngle.clamp(pole.cross(face.upwardNormal).length, 0, 1)
        }
    }
}

/// How sampling bias can be corrected for a given survey geometry.
public enum BiasCorrectionMethod: String, Sendable, Codable {

    /// Classical Terzaghi: one sampling direction, weight `1 / cos(angle)` between the
    /// pole and that direction, capped.
    case terzaghi

    /// Area-weighted over the exposed facets, for a surface facing many directions.
    ///
    /// Not a different theory — the same relation as ``terzaghi``, summed. Each facet is
    /// a tiny mapped face, so the share of the exposure that can see a given attitude is
    /// the area-weighted mean of the per-facet sines. It reduces exactly to the planar
    /// case when there is one facet, which is the property worth testing.
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

    /// The element that does the sampling, for the geometries that have just one.
    ///
    /// `nil` for a surface model, which has many, and for selective sampling, which has
    /// none that describes its bias.
    public var samplingElement: SamplingElement? {
        switch self {
        case .scanline(let line, _), .borehole(let line, _): .line(line)
        case .window(let face, _), .traceMap(let face, _): .plane(face)
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

    /// The share of this exposure that can see a discontinuity of the given attitude,
    /// `0...1`.
    ///
    /// The apparent frequency of a set is proportional to this, so the bias weight is
    /// its reciprocal. One function covers all three correctable geometries: a line, a
    /// plane, and an area-weighted mean over many planes.
    ///
    /// What is deliberately **not** here is the weight itself. Taking the reciprocal
    /// needs a cap — the project specification suggests 5 to 10 — and a cap silently
    /// under-reports any set whose efficiency falls below its reciprocal. Deciding the
    /// cap, and deciding when an efficiency is so low that the set should be reported as
    /// unsampled rather than corrected, is a statistical judgement that belongs with the
    /// set analysis. This returns the raw geometry so that judgement has something
    /// honest to work from.
    ///
    /// `nil` for selective sampling, and for a surface model with no usable facet area.
    public func samplingEfficiency(for discontinuity: PlaneOrientation) -> Double? {
        if let element = samplingElement {
            return element.samplingEfficiency(for: discontinuity)
        }
        guard case .surfaceModel(let facets) = self else { return nil }
        let totalArea = facets.reduce(0.0) { $0 + max($1.areaSquareMetres, 0) }
        guard totalArea > 0 else { return nil }
        let weighted = facets.reduce(0.0) { sum, facet in
            let area = max(facet.areaSquareMetres, 0)
            return sum + area * SamplingElement.plane(facet.orientation)
                .samplingEfficiency(for: discontinuity)
        }
        return GeoAngle.clamp(weighted / totalArea, 0, 1)
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
