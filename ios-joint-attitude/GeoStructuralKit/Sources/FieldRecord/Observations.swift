import Foundation

// A field observation is either measured with a tape or estimated by eye against the
// ISRM class descriptions. The two are kept distinct rather than flattened into one
// number or one class, because once flattened they cannot be told apart: a recorded
// "3 mm" that was really an eyeballed "moderately wide" would go into a DFN model as
// though someone had put a ruler on it.

/// An aperture, measured or estimated.
public enum ApertureObservation: Equatable, Sendable, Codable {
    case measured(millimetres: Double)
    case estimated(ApertureClass)

    /// The class, derived from a measurement or taken as given.
    public var apertureClass: ApertureClass? {
        switch self {
        case .measured(let millimetres): ApertureClass(millimetres: millimetres)
        case .estimated(let apertureClass): apertureClass
        }
    }

    /// The measured value, or `nil` when the observation was an estimate.
    public var millimetres: Double? {
        switch self {
        case .measured(let millimetres): millimetres
        case .estimated: nil
        }
    }

    public var wasMeasured: Bool {
        if case .measured = self { return true }
        return false
    }
}

/// A persistence (trace length), measured or estimated.
public enum PersistenceObservation: Equatable, Sendable, Codable {
    case measured(metres: Double)
    case estimated(PersistenceClass)

    public var persistenceClass: PersistenceClass? {
        switch self {
        case .measured(let metres): PersistenceClass(metres: metres)
        case .estimated(let persistenceClass): persistenceClass
        }
    }

    public var metres: Double? {
        switch self {
        case .measured(let metres): metres
        case .estimated: nil
        }
    }

    public var wasMeasured: Bool {
        if case .measured = self { return true }
        return false
    }
}

/// A spacing, measured or estimated.
public enum SpacingObservation: Equatable, Sendable, Codable {
    case measured(millimetres: Double)
    case estimated(SpacingClass)

    public var spacingClass: SpacingClass? {
        switch self {
        case .measured(let millimetres): SpacingClass(millimetres: millimetres)
        case .estimated(let spacingClass): spacingClass
        }
    }

    public var millimetres: Double? {
        switch self {
        case .measured(let millimetres): millimetres
        case .estimated: nil
        }
    }

    public var wasMeasured: Bool {
        if case .measured = self { return true }
        return false
    }
}

/// The ISRM descriptive block for one discontinuity.
///
/// Every field is optional on purpose. A geologist logging a scanline records what the
/// exposure shows and skips what it does not, and a model that demands a weathering
/// grade for every joint gets filled with guesses.
public struct DiscontinuityDescription: Equatable, Sendable, Codable {

    public var roughness: RoughnessClass?
    public var jrc: JointRoughnessCoefficient?
    public var aperture: ApertureObservation?
    public var infilling: Infilling?
    public var weathering: WeatheringGrade?
    public var seepage: SeepageRating?
    public var persistence: PersistenceObservation?
    public var spacing: SpacingObservation?
    public var termination: TerminationType?

    public init(
        roughness: RoughnessClass? = nil,
        jrc: JointRoughnessCoefficient? = nil,
        aperture: ApertureObservation? = nil,
        infilling: Infilling? = nil,
        weathering: WeatheringGrade? = nil,
        seepage: SeepageRating? = nil,
        persistence: PersistenceObservation? = nil,
        spacing: SpacingObservation? = nil,
        termination: TerminationType? = nil
    ) {
        self.roughness = roughness
        self.jrc = jrc
        self.aperture = aperture
        self.infilling = infilling
        self.weathering = weathering
        self.seepage = seepage
        self.persistence = persistence
        self.spacing = spacing
        self.termination = termination
    }

    public static let empty = DiscontinuityDescription()

    /// `true` when nothing has been recorded.
    public var isEmpty: Bool { self == DiscontinuityDescription.empty }

    /// How many of the nine ISRM fields have been filled in — for a progress hint in the
    /// UI, and for judging how complete a data set is before exporting it.
    public var completedFieldCount: Int {
        var count = 0
        if roughness != nil { count += 1 }
        if jrc != nil { count += 1 }
        if aperture != nil { count += 1 }
        if infilling != nil { count += 1 }
        if weathering != nil { count += 1 }
        if seepage != nil { count += 1 }
        if persistence != nil { count += 1 }
        if spacing != nil { count += 1 }
        if termination != nil { count += 1 }
        return count
    }

    public static let fieldCount = 9
}
