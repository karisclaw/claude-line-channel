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
    public var seepage: SeepageObservation?
    public var persistence: PersistenceObservation?
    public var spacing: SpacingObservation?
    public var termination: TerminationType?

    /// Thickness of the zone, in metres, for a type that occupies a thickness rather
    /// than a single surface — a fault zone or a shear zone.
    ///
    /// Separate from ``Infilling/thicknessMillimetres``, which is the gouge or mineral
    /// filling a single surface. A shear zone is metres of distributed strain; a filling
    /// is millimetres inside one fracture, and adding them together would be nonsense.
    public var zoneThicknessMetres: Double?

    public init(
        roughness: RoughnessClass? = nil,
        jrc: JointRoughnessCoefficient? = nil,
        aperture: ApertureObservation? = nil,
        infilling: Infilling? = nil,
        weathering: WeatheringGrade? = nil,
        seepage: SeepageObservation? = nil,
        persistence: PersistenceObservation? = nil,
        spacing: SpacingObservation? = nil,
        termination: TerminationType? = nil,
        zoneThicknessMetres: Double? = nil
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
        self.zoneThicknessMetres = zoneThicknessMetres
    }

    public static let empty = DiscontinuityDescription()

    /// `true` when nothing has been recorded.
    public var isEmpty: Bool { self == DiscontinuityDescription.empty }

    /// How many of the nine ISRM fields have been filled in — for a progress hint in the
    /// UI, and for judging how complete a data set is before exporting it.
    ///
    /// ``zoneThicknessMetres`` is not one of the nine: it applies only to the zone
    /// types, so counting it would make every joint look incomplete.
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

    // MARK: - Consistency

    /// Which of ISRM's two seepage scales the recorded filling implies.
    ///
    /// `nil` when the filling has not been recorded, so no scale is implied and nothing
    /// can be said about the one that was used.
    public var impliedSeepageScaleUsesFilledTable: Bool? {
        guard let infilling else { return nil }
        return infilling.material != .clean
    }

    /// What disagrees between the seepage scale used and the recorded filling, or `nil`
    /// when they agree or when there is not enough to compare.
    ///
    /// Worth checking rather than trusting: the two scales share their rating numbers,
    /// so a reading taken off the wrong table looks perfectly valid and lands three
    /// cells away from the truth.
    public func seepageScaleMismatch() -> SeepageScaleMismatch? {
        guard let seepage, let impliesFilled = impliedSeepageScaleUsesFilledTable else {
            return nil
        }
        switch (seepage.usesFilledScale, impliesFilled) {
        case (true, false): return .filledScaleOnCleanDiscontinuity
        case (false, true): return .unfilledScaleOnFilledDiscontinuity
        default: return nil
        }
    }

    /// Whether the zone thickness agrees with the type of discontinuity.
    ///
    /// Both directions are reported. A fault zone with no thickness is an incomplete
    /// record of the quantity an engineer asks about first; a joint with a thickness is
    /// either a mis-typed type or a filling entered in the wrong field.
    public func zoneThicknessIssue(for type: DiscontinuityType) -> ZoneThicknessIssue? {
        switch (type.isZone, zoneThicknessMetres) {
        case (true, nil): .missingForZoneType
        case (false, .some): .presentForSurfaceType
        default: nil
        }
    }

    /// Everything inconsistent about this description, given the type it belongs to.
    ///
    /// These are warnings for the UI to show, never corrections: the geologist is at the
    /// outcrop and this code is not, so a disagreement is a prompt to look again.
    public func inconsistencies(for type: DiscontinuityType) -> [DescriptionInconsistency] {
        var found: [DescriptionInconsistency] = []
        if let mismatch = seepageScaleMismatch() { found.append(.seepageScale(mismatch)) }
        if let issue = zoneThicknessIssue(for: type) { found.append(.zoneThickness(issue)) }
        return found
    }
}

/// A disagreement between the seepage scale used and the recorded filling.
public enum SeepageScaleMismatch: String, Sendable, Codable {
    /// The filled scale was used on a discontinuity recorded as clean.
    case filledScaleOnCleanDiscontinuity
    /// The unfilled scale was used on a discontinuity that has filling.
    case unfilledScaleOnFilledDiscontinuity
}

/// A disagreement between the zone thickness and the type of discontinuity.
public enum ZoneThicknessIssue: String, Sendable, Codable {
    /// A fault zone or shear zone with no thickness recorded.
    case missingForZoneType
    /// A thickness recorded for a type that is a single surface.
    case presentForSurfaceType
}

/// Something inconsistent in a description. For warning, not for correcting.
public enum DescriptionInconsistency: Equatable, Sendable, Codable {
    case seepageScale(SeepageScaleMismatch)
    case zoneThickness(ZoneThicknessIssue)
}
