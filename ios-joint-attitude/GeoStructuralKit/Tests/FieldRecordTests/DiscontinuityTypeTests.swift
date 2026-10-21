import XCTest
@testable import FieldRecord

final class DiscontinuityTypeTests: XCTestCase {

    func testStandardCasesHaveDistinctStableKeys() {
        let keys = DiscontinuityType.standardCases.map(\.storageKey)
        XCTAssertEqual(Set(keys).count, keys.count, "two types share a storage key")
        XCTAssertEqual(DiscontinuityType.standardCases.count, 15)
        XCTAssertTrue(keys.allSatisfy { !$0.contains(":") }, "a standard key must not look like other:…")
    }

    func testStorageKeysRoundTrip() {
        for type in DiscontinuityType.standardCases {
            XCTAssertEqual(DiscontinuityType(storageKey: type.storageKey), type)
        }
    }

    /// A site that does not fit the taxonomy keeps its own words, and they survive the
    /// round trip rather than collapsing into one bucket.
    func testOtherKeepsItsLabel() {
        let gash = DiscontinuityType.other("擠壓帶")
        XCTAssertEqual(gash.storageKey, "other:擠壓帶")
        XCTAssertEqual(DiscontinuityType(storageKey: "other:擠壓帶"), gash)
        XCTAssertNotEqual(gash, DiscontinuityType.other("破碎帶"))
    }

    func testOtherWithAnEmptyLabelStillRoundTrips() {
        let blank = DiscontinuityType.other("")
        XCTAssertEqual(blank.storageKey, "other:")
        XCTAssertEqual(DiscontinuityType(storageKey: "other:"), blank)
    }

    /// A label containing a colon must not be truncated — only the first colon separates
    /// the prefix.
    func testOtherLabelMayContainAColon()  {
        let awkward = DiscontinuityType.other("zone: sheared")
        XCTAssertEqual(DiscontinuityType(storageKey: awkward.storageKey), awkward)
    }

    func testUnknownKeysAreRejected() {
        XCTAssertNil(DiscontinuityType(storageKey: "sandwich"))
        XCTAssertNil(DiscontinuityType(storageKey: ""))
        XCTAssertNil(DiscontinuityType(storageKey: "Joint"), "keys are case-sensitive")
    }

    func testCodableUsesThePlainKeyNotTheSynthesizedForm() throws {
        let data = try JSONEncoder().encode(DiscontinuityType.shearZone)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"shearZone\"")
        XCTAssertEqual(try JSONDecoder().decode(DiscontinuityType.self, from: data), .shearZone)

        for type in DiscontinuityType.standardCases + [.other("x")] {
            let encoded = try JSONEncoder().encode(type)
            XCTAssertEqual(try JSONDecoder().decode(DiscontinuityType.self, from: encoded), type)
        }
    }

    func testDecodingAnUnknownKeyThrowsRatherThanGuessing() {
        let data = "\"nonsense\"".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(DiscontinuityType.self, from: data))
    }

    /// Only the zone types occupy a thickness; everything else is a surface.
    func testZoneTypes() {
        XCTAssertTrue(DiscontinuityType.faultZone.isZone)
        XCTAssertTrue(DiscontinuityType.shearZone.isZone)
        XCTAssertFalse(DiscontinuityType.fault.isZone, "a discrete fault surface is not a zone")
        XCTAssertFalse(DiscontinuityType.joint.isZone)
        XCTAssertFalse(DiscontinuityType.other("whatever").isZone)
        XCTAssertEqual(DiscontinuityType.standardCases.filter(\.isZone).count, 2)
    }

    /// The field picker shows a short list first. Every entry on it must be a real type,
    /// and the default must be on it, or the first screen cannot complete a measurement.
    func testCommonCasesAreAShortSubsetOfTheStandardOnes() {
        XCTAssertLessThan(DiscontinuityType.commonCases.count, DiscontinuityType.standardCases.count)
        for type in DiscontinuityType.commonCases {
            XCTAssertTrue(DiscontinuityType.standardCases.contains(type), "\(type) is not standard")
        }
        XCTAssertTrue(DiscontinuityType.commonCases.contains(.joint))
    }
}

final class DescriptionConsistencyTests: XCTestCase {

    /// The check that earns its place: both scales run I–V, so a reading taken off the
    /// wrong table looks valid and lands three cells from the truth.
    func testSeepageScaleIsCheckedAgainstTheRecordedFilling() {
        var clean = DiscontinuityDescription(infilling: .clean, seepage: .unfilled(.damp))
        XCTAssertNil(clean.seepageScaleMismatch())

        clean.seepage = .filled(.fillingDamp)
        XCTAssertEqual(clean.seepageScaleMismatch(), .filledScaleOnCleanDiscontinuity)

        var filled = DiscontinuityDescription(
            infilling: Infilling(material: .clay, thicknessMillimetres: 3),
            seepage: .filled(.fillingDamp)
        )
        XCTAssertNil(filled.seepageScaleMismatch())

        filled.seepage = .unfilled(.damp)
        XCTAssertEqual(filled.seepageScaleMismatch(), .unfilledScaleOnFilledDiscontinuity)
    }

    /// With no filling recorded, no scale is implied, so nothing can be said — and
    /// saying nothing is better than warning about a field nobody filled in.
    func testNoMismatchIsReportedWhenThereIsNothingToCompare() {
        XCTAssertNil(DiscontinuityDescription(seepage: .filled(.fillingDamp)).seepageScaleMismatch())
        XCTAssertNil(DiscontinuityDescription(infilling: .clean).seepageScaleMismatch())
        XCTAssertNil(DiscontinuityDescription.empty.seepageScaleMismatch())

        // With no filling recorded there is no implied scale at all, which is different
        // from implying the unfilled one.
        XCTAssertNil(DiscontinuityDescription.empty.impliedSeepageScaleUsesFilledTable)
        XCTAssertEqual(DiscontinuityDescription(infilling: .clean).impliedSeepageScaleUsesFilledTable, false)
        XCTAssertEqual(
            DiscontinuityDescription(infilling: Infilling(material: .clay)).impliedSeepageScaleUsesFilledTable,
            true
        )
    }

    func testZoneThicknessIsCheckedBothWays() {
        let withThickness = DiscontinuityDescription(zoneThicknessMetres: 1.5)
        let withoutThickness = DiscontinuityDescription.empty

        XCTAssertNil(withThickness.zoneThicknessIssue(for: .shearZone))
        XCTAssertEqual(withoutThickness.zoneThicknessIssue(for: .shearZone), .missingForZoneType)
        XCTAssertEqual(withThickness.zoneThicknessIssue(for: .joint), .presentForSurfaceType)
        XCTAssertNil(withoutThickness.zoneThicknessIssue(for: .joint))
    }

    /// A zone thickness is metres of distributed strain; a filling thickness is
    /// millimetres inside one fracture. They are separate fields because adding them
    /// together would be nonsense.
    func testZoneThicknessIsSeparateFromFillingThickness() {
        let description = DiscontinuityDescription(
            infilling: Infilling(material: .gouge, thicknessMillimetres: 20),
            zoneThicknessMetres: 2.5
        )
        XCTAssertEqual(description.infilling?.thicknessMillimetres, 20)
        XCTAssertEqual(description.zoneThicknessMetres, 2.5)
        XCTAssertNil(description.zoneThicknessIssue(for: .faultZone))
    }

    func testInconsistenciesAreCollectedTogether() {
        let description = DiscontinuityDescription(
            infilling: .clean,
            seepage: .filled(.fillingDamp)
        )
        let issues = description.inconsistencies(for: .shearZone)
        XCTAssertEqual(issues.count, 2)
        XCTAssertTrue(issues.contains(.seepageScale(.filledScaleOnCleanDiscontinuity)))
        XCTAssertTrue(issues.contains(.zoneThickness(.missingForZoneType)))

        let clean = DiscontinuityDescription(infilling: .clean, seepage: .unfilled(.damp))
        XCTAssertTrue(clean.inconsistencies(for: .joint).isEmpty)
    }
}
