import Foundation

// ISRM (1978) "Suggested Methods for the Quantitative Description of Discontinuities in
// Rock Masses", as the descriptive fields the project specification asks for.
//
// Every class boundary is written out as a numeric range on the enum, with a test that
// pins it, so the whole convention is visible in one file and a correction lands in one
// place. Please check the boundaries against your copy of ISRM: they are reproduced
// from memory of the standard tables, and a wrong boundary would quietly misclassify
// every record.
//
// Boundaries are half-open, `[lower, upper)`, consistently: a spacing of exactly 60 mm
// is `close` (60–200), not `veryClose` (20–60). ISRM writes its tables as "20–60 mm"
// without saying which end owns the boundary, so this is a choice, and it is applied
// the same way to every scale here.

// MARK: - Roughness

/// Small-scale roughness of the discontinuity surface.
public enum RoughnessProfile: String, CaseIterable, Sendable, Codable {
    case rough
    case smooth
    case slickensided
}

/// Large-scale shape of the discontinuity surface.
public enum RoughnessWaviness: String, CaseIterable, Sendable, Codable {
    case stepped
    case undulating
    case planar
}

/// The ISRM roughness class: a small-scale profile crossed with a large-scale shape,
/// giving the nine classes I–IX.
public struct RoughnessClass: Equatable, Hashable, Sendable, Codable {

    public var profile: RoughnessProfile
    public var waviness: RoughnessWaviness

    public init(profile: RoughnessProfile, waviness: RoughnessWaviness) {
        self.profile = profile
        self.waviness = waviness
    }

    /// ISRM class number, `1...9`.
    ///
    /// I–III are stepped (rough, smooth, slickensided), IV–VI undulating, VII–IX planar.
    public var isrmClass: Int {
        let wavinessIndex: Int
        switch waviness {
        case .stepped: wavinessIndex = 0
        case .undulating: wavinessIndex = 1
        case .planar: wavinessIndex = 2
        }
        let profileIndex: Int
        switch profile {
        case .rough: profileIndex = 0
        case .smooth: profileIndex = 1
        case .slickensided: profileIndex = 2
        }
        return wavinessIndex * 3 + profileIndex + 1
    }

    public var romanNumeral: String {
        ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"][isrmClass - 1]
    }

    public static var allCases: [RoughnessClass] {
        RoughnessWaviness.allCases.flatMap { waviness in
            RoughnessProfile.allCases.map { RoughnessClass(profile: $0, waviness: waviness) }
        }
    }
}

/// Barton's joint roughness coefficient.
///
/// The project specification says 1–20; the published profile chart runs 0–20, where 0
/// is a perfectly smooth planar surface, so 0 is accepted. Say the word to make 1 the
/// floor.
public struct JointRoughnessCoefficient: Equatable, Hashable, Sendable, Codable {

    public static let validRange = 0...20

    public let value: Int

    /// `nil` for a value outside 0–20, rather than a clamped one: a JRC of 25 is a data
    /// entry error, and clamping it to 20 would hide that.
    public init?(_ value: Int) {
        guard JointRoughnessCoefficient.validRange.contains(value) else { return nil }
        self.value = value
    }
}

// MARK: - Aperture

/// ISRM aperture description.
///
/// The published table overlaps: it lists "wide, > 10 mm" at the end of the gapped group
/// and "very wide, 1–10 cm" at the start of the open group, so a 50 mm aperture has two
/// valid names there. Both are kept, but they are not treated alike:
///
/// - ``wide`` exists so a value copied from a notebook written against the published
///   table can be stored as it was written, without being quietly reinterpreted.
/// - It is **not** in ``derivable``, so ``init(millimetres:)`` never produces it. A
///   measurement of 50 mm becomes ``veryWide``, deterministically.
///
/// Without that split, classifying a measurement would depend on the order the cases
/// happen to be declared in.
public enum ApertureClass: String, CaseIterable, Sendable, Codable {
    case veryTight
    case tight
    case partlyOpen
    case open
    case moderatelyWide
    /// Published as "wide, > 10 mm". Storable, never derived — see the type's note.
    case wide
    case veryWide
    case extremelyWide
    case cavernous

    /// Half-open range in millimetres.
    public var millimetreRange: Range<Double> {
        switch self {
        case .veryTight: 0..<0.1
        case .tight: 0.1..<0.25
        case .partlyOpen: 0.25..<0.5
        case .open: 0.5..<2.5
        case .moderatelyWide: 2.5..<10
        case .wide: 10..<Double.infinity        // the published open-ended class
        case .veryWide: 10..<100
        case .extremelyWide: 100..<1000
        case .cavernous: 1000..<Double.infinity
        }
    }

    /// ISRM's grouping of the classes.
    public enum Group: String, Sendable, Codable {
        case closed
        case gapped
        case open
    }

    public var group: Group {
        switch self {
        case .veryTight, .tight, .partlyOpen: .closed
        case .open, .moderatelyWide, .wide: .gapped
        case .veryWide, .extremelyWide, .cavernous: .open
        }
    }

    /// The non-overlapping classes a measurement may be turned into. Excludes ``wide``,
    /// whose published range covers three of the others.
    public static let derivable: [ApertureClass] = allCases.filter { $0 != .wide }

    /// `true` for a class that can only have come from a notebook, not from a
    /// measurement taken by this app.
    public var isLegacyPublishedClass: Bool { self == .wide }

    public init?(millimetres value: Double) {
        guard let match = ApertureClass.derivable.first(where: { $0.millimetreRange.contains(value) })
        else { return nil }
        self = match
    }
}

// MARK: - Infilling

/// What the discontinuity is filled with.
public enum InfillingMaterial: String, CaseIterable, Sendable, Codable {
    /// Named `clean` rather than `none`: a case called `none` is shadowed by
    /// `Optional.none`, so `let m: InfillingMaterial? = .none` would silently mean nil
    /// rather than an unfilled discontinuity.
    case clean
    case clay
    case silt
    case sand
    case calcite
    case quartz
    case gypsum
    case chlorite
    case breccia
    case gouge
    case ironOxide
    case other
}

/// The filling, with its thickness and anything worth saying in words.
public struct Infilling: Equatable, Sendable, Codable {

    public var material: InfillingMaterial
    /// Thickness in millimetres.
    public var thicknessMillimetres: Double?
    /// Free text — mineralogy, strength, whether it is swelling.
    public var notes: String?

    public init(
        material: InfillingMaterial,
        thicknessMillimetres: Double? = nil,
        notes: String? = nil
    ) {
        self.material = material
        self.thicknessMillimetres = thicknessMillimetres
        self.notes = notes
    }

    public static let clean = Infilling(material: .clean)
}

// MARK: - Weathering

/// ISRM weathering grades W1–W6.
public enum WeatheringGrade: String, CaseIterable, Sendable, Codable {
    case fresh                  // W1
    case slightlyWeathered      // W2
    case moderatelyWeathered    // W3
    case highlyWeathered        // W4
    case completelyWeathered    // W5
    case residualSoil           // W6

    /// Grade number, `1...6`.
    public var grade: Int {
        switch self {
        case .fresh: 1
        case .slightlyWeathered: 2
        case .moderatelyWeathered: 3
        case .highlyWeathered: 4
        case .completelyWeathered: 5
        case .residualSoil: 6
        }
    }

    /// `W1` … `W6`.
    public var code: String { "W\(grade)" }

    public init?(grade: Int) {
        guard let match = WeatheringGrade.allCases.first(where: { $0.grade == grade })
        else { return nil }
        self = match
    }
}

// MARK: - Water

/// ISRM seepage ratings I–V for a discontinuity **without** filling.
public enum UnfilledSeepageRating: String, CaseIterable, Sendable, Codable {
    /// I — the discontinuity is tight and dry; water flow is not possible.
    case tightAndDry
    /// II — dry, but with evidence of past flow such as staining.
    case dryWithEvidenceOfFlow
    /// III — damp, with no free water.
    case damp
    /// IV — seepage, occasional drops.
    case seepage
    /// V — continuous flow; record the rate.
    case continuousFlow

    /// Rating number, `1...5`.
    public var rating: Int {
        switch self {
        case .tightAndDry: 1
        case .dryWithEvidenceOfFlow: 2
        case .damp: 3
        case .seepage: 4
        case .continuousFlow: 5
        }
    }

    public init?(rating: Int) {
        guard let match = UnfilledSeepageRating.allCases.first(where: { $0.rating == rating })
        else { return nil }
        self = match
    }
}

/// ISRM seepage ratings I–V for a **filled** discontinuity.
///
/// A separate scale, not a relabelling: these ratings describe the state of the filling
/// rather than of an open gap, so rating III means "filling wet, occasional drops" here
/// and "damp, no free water" on the unfilled scale. Keeping them as one enum with a
/// flag, or as a bare number, would make a stored `III` ambiguous — which table it came
/// from could no longer be recovered.
public enum FilledSeepageRating: String, CaseIterable, Sendable, Codable {
    /// I — filling heavily consolidated and dry; flow unlikely, permeability very low.
    case fillingConsolidatedAndDry
    /// II — filling damp, but no free water.
    case fillingDamp
    /// III — filling wet, occasional drops of water.
    case fillingWetWithOccasionalDrops
    /// IV — filling shows signs of outwash, with continuous flow; record the rate.
    case fillingShowsOutwashWithContinuousFlow
    /// V — filling locally washed out, with considerable flow along the channels;
    /// record the rate and describe the pressure.
    case fillingWashedOutWithHeavyFlow

    /// Rating number, `1...5`.
    public var rating: Int {
        switch self {
        case .fillingConsolidatedAndDry: 1
        case .fillingDamp: 2
        case .fillingWetWithOccasionalDrops: 3
        case .fillingShowsOutwashWithContinuousFlow: 4
        case .fillingWashedOutWithHeavyFlow: 5
        }
    }

    public init?(rating: Int) {
        guard let match = FilledSeepageRating.allCases.first(where: { $0.rating == rating })
        else { return nil }
        self = match
    }
}

/// A seepage observation, carrying which of ISRM's two tables it was read from.
///
/// Self-describing on purpose: the rating number alone does not say which scale applied,
/// and the two scales mean different things at the same number.
public enum SeepageObservation: Equatable, Hashable, Sendable, Codable {
    case unfilled(UnfilledSeepageRating)
    case filled(FilledSeepageRating)

    /// Rating number, `1...5`, on whichever scale applies.
    public var rating: Int {
        switch self {
        case .unfilled(let value): value.rating
        case .filled(let value): value.rating
        }
    }

    public var romanNumeral: String { ["I", "II", "III", "IV", "V"][rating - 1] }

    /// `true` when the filled-discontinuity scale was used.
    public var usesFilledScale: Bool {
        if case .filled = self { return true }
        return false
    }

    /// Rating with its scale, e.g. `III (filled)` — the form to put in a report, since
    /// a bare `III` is ambiguous.
    public var qualifiedDescription: String {
        "\(romanNumeral) (\(usesFilledScale ? "filled" : "unfilled"))"
    }
}

// MARK: - Persistence

/// ISRM persistence, by trace length.
public enum PersistenceClass: String, CaseIterable, Sendable, Codable {
    case veryLow
    case low
    case medium
    case high
    case veryHigh

    /// Half-open range in metres.
    public var metreRange: Range<Double> {
        switch self {
        case .veryLow: 0..<1
        case .low: 1..<3
        case .medium: 3..<10
        case .high: 10..<20
        case .veryHigh: 20..<Double.infinity
        }
    }

    public init?(metres value: Double) {
        guard let match = PersistenceClass.allCases.first(where: { $0.metreRange.contains(value) })
        else { return nil }
        self = match
    }
}

// MARK: - Spacing

/// ISRM spacing classes.
public enum SpacingClass: String, CaseIterable, Sendable, Codable {
    case extremelyClose
    case veryClose
    case close
    case moderate
    case wide
    case veryWide
    case extremelyWide

    /// Half-open range in millimetres.
    public var millimetreRange: Range<Double> {
        switch self {
        case .extremelyClose: 0..<20
        case .veryClose: 20..<60
        case .close: 60..<200
        case .moderate: 200..<600
        case .wide: 600..<2000
        case .veryWide: 2000..<6000
        case .extremelyWide: 6000..<Double.infinity
        }
    }

    public init?(millimetres value: Double) {
        guard let match = SpacingClass.allCases.first(where: { $0.millimetreRange.contains(value) })
        else { return nil }
        self = match
    }
}

// MARK: - Termination

/// ISRM termination notation: how the trace ends.
public enum TerminationType: String, CaseIterable, Sendable, Codable {
    /// `x` — extends beyond the exposure, so its real length is unknown.
    case extendsBeyondExposure
    /// `r` — terminates in intact rock.
    case terminatesInRock
    /// `d` — terminates against another discontinuity.
    case terminatesAgainstDiscontinuity

    /// ISRM's single-letter code.
    public var code: String {
        switch self {
        case .extendsBeyondExposure: "x"
        case .terminatesInRock: "r"
        case .terminatesAgainstDiscontinuity: "d"
        }
    }

    public init?(code: String) {
        guard let match = TerminationType.allCases.first(where: { $0.code == code.lowercased() })
        else { return nil }
        self = match
    }
}
