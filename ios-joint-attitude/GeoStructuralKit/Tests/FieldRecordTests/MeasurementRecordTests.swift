import XCTest
import OrientationCore
@testable import FieldRecord

final class MeasurementRecordTests: XCTestCase {

    private func fullRecord() -> MeasurementRecord {
        MeasurementRecord(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            mode: .contact,
            plane: PlaneOrientation(dip: 62, dipDirection: 148),
            angularStandardDeviation: 0.8,
            sampleCount: 97,
            measuredFaceAzimuth: 148,
            geometry: MeasurementGeometry(placement: .leftSideOnFace, edge: .leftEdge),
            magneticEnvironment: MagneticEnvironment(
                fieldStrength: 46.2, accuracy: .high, headingAccuracy: 6
            ),
            declination: MagneticDeclination(degreesEast: -4),
            surveyGeometry: .scanline(
                line: LineOrientation(trend: 30, plunge: 0), lengthMetres: 12
            ),
            location: MeasurementLocation(
                latitude: 24.95, longitude: 121.2, altitude: 310,
                horizontalAccuracy: 4.5, verticalAccuracy: 6
            ),
            discontinuityType: .joint,
            isrm: DiscontinuityDescription(
                roughness: RoughnessClass(profile: .rough, waviness: .undulating),
                jrc: JointRoughnessCoefficient(10),
                aperture: .measured(millimetres: 0.4),
                infilling: .clean,
                weathering: .slightlyWeathered,
                seepage: .unfilled(.damp),
                persistence: .measured(metres: 4.5),
                spacing: .measured(millimetres: 320),
                termination: .terminatesInRock
            ),
            observer: "KK",
            notes: "三組節理交會處",
            photos: [PhotoReference(fileName: "p1.heic", capturedAt: Date(timeIntervalSince1970: 1))]
        )
    }

    func testStrikeIsDerivedNotStored() {
        let record = fullRecord()
        XCTAssertEqual(record.strike!, 58, accuracy: 1e-9)
        // Changing the dip direction changes the strike with it — a stored copy is one
        // more thing that can fall out of step after an edit.
        var edited = record
        edited.plane = PlaneOrientation(dip: 62, dipDirection: 200)
        XCTAssertEqual(edited.strike!, 110, accuracy: 1e-9)
    }

    func testRecordIsStampedWithTheConventionVersion() {
        XCTAssertEqual(fullRecord().conventionVersion, AttitudeConvention.version)
    }

    func testMagneticNorthReadingIsReconstructable() {
        let record = fullRecord()
        // Declination −4°, so the magnetic dip direction reads 4° higher.
        XCTAssertEqual(record.planeInMagneticNorthFrame!.dipDirection, 152, accuracy: 1e-9)
        XCTAssertEqual(record.planeInMagneticNorthFrame!.dip, 62, accuracy: 1e-12)
    }

    func testMagneticAssessmentIsDerivedFromTheStoredReading() {
        var record = fullRecord()
        XCTAssertEqual(record.magneticAssessment?.verdict, .good)
        XCTAssertFalse(record.hasSuspectAzimuth)

        record.magneticEnvironment = MagneticEnvironment(
            fieldStrength: 140, accuracy: .low, headingAccuracy: 30
        )
        XCTAssertEqual(record.magneticAssessment?.verdict, .disturbed)
        XCTAssertTrue(record.hasSuspectAzimuth)
        // The dip is unaffected, which is the whole point of recording the environment.
        XCTAssertEqual(record.plane!.dip, 62, accuracy: 1e-12)
    }

    func testNoMagneticReadingMeansNoAssessmentRatherThanAGoodOne() {
        var record = fullRecord()
        record.magneticEnvironment = nil
        XCTAssertNil(record.magneticAssessment)
        XCTAssertFalse(record.hasSuspectAzimuth)
    }

    func testFullRecordSurvivesStorage() throws {
        let record = fullRecord()
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(MeasurementRecord.self, from: data)
        XCTAssertEqual(decoded, record, "a field was lost or changed in the round trip")
    }

    func testHasAttitude() {
        XCTAssertTrue(fullRecord().hasAttitude)
        var blank = fullRecord()
        blank.plane = nil
        XCTAssertFalse(blank.hasAttitude)
        blank.lineation = LineOrientation(trend: 100, plunge: 20)
        XCTAssertTrue(blank.hasAttitude)
    }

    /// A vertical joint's facing direction cannot be held by a dip/dip-direction pair,
    /// so it gets its own field.
    func testMeasuredFaceAzimuthRecordsWhichFaceOfAVerticalJointWasTouched() {
        var east = fullRecord()
        east.plane = PlaneOrientation(dip: 90, dipDirection: 90)
        east.measuredFaceAzimuth = 90

        var west = east
        west.plane = PlaneOrientation(dip: 90, dipDirection: 270)
        west.measuredFaceAzimuth = 270

        // One plane, two descriptions: canonicalizing brings them together.
        XCTAssertEqual(east.plane!.canonicalized, west.plane!.canonicalized)
        // Different faces, and only this field says so.
        XCTAssertNotEqual(east.measuredFaceAzimuth, west.measuredFaceAzimuth)
    }
}

final class MeasurementLocationTests: XCTestCase {

    /// `CLLocation` reports a negative accuracy when it has no fix. Sorted or filtered as
    /// though smaller were better, that puts the worst data first.
    func testNegativeAccuracyMeansNoFixNotAPerfectOne() {
        let noFix = MeasurementLocation(
            latitude: 0, longitude: 0, horizontalAccuracy: -1, verticalAccuracy: -1
        )
        XCTAssertFalse(noFix.hasValidHorizontalPosition)
        XCTAssertFalse(noFix.hasValidAltitude)
        XCTAssertNil(noFix.usableHorizontalAccuracy)

        let good = MeasurementLocation(
            latitude: 24.95, longitude: 121.2, altitude: 310,
            horizontalAccuracy: 4.5, verticalAccuracy: 6
        )
        XCTAssertTrue(good.hasValidHorizontalPosition)
        XCTAssertTrue(good.hasValidAltitude)
        XCTAssertEqual(good.usableHorizontalAccuracy, 4.5)
    }

    func testMissingAccuracyIsNotTreatedAsValid() {
        let location = MeasurementLocation(latitude: 1, longitude: 2)
        XCTAssertFalse(location.hasValidHorizontalPosition)
        XCTAssertNil(location.usableHorizontalAccuracy)
    }

    func testAltitudeNeedsBothAValueAndAnAccuracy() {
        XCTAssertFalse(
            MeasurementLocation(latitude: 0, longitude: 0, verticalAccuracy: 5).hasValidAltitude,
            "an accuracy without an altitude is not an altitude"
        )
        XCTAssertFalse(
            MeasurementLocation(latitude: 0, longitude: 0, altitude: 100).hasValidAltitude
        )
    }

    func testCoordinateRangeCheck() {
        XCTAssertTrue(MeasurementLocation(latitude: 24.95, longitude: 121.2).isCoordinateInRange)
        XCTAssertTrue(MeasurementLocation(latitude: -90, longitude: 180).isCoordinateInRange)
        XCTAssertFalse(MeasurementLocation(latitude: 91, longitude: 0).isCoordinateInRange)
        XCTAssertFalse(MeasurementLocation(latitude: 0, longitude: -181).isCoordinateInRange)
    }
}

final class SurveyGeometryTests: XCTestCase {

    /// The error this API shape exists to prevent, asserted directly.
    ///
    /// For one outcrop face and one discontinuity, the plane formula and the line formula
    /// do not merely differ — they invert. A set lying parallel to the face shows no
    /// trace on it at all, so it needs the largest correction there is; feed the same
    /// face's normal to the line formula and it comes back needing none. The earlier
    /// version of this type handed out a bare `samplingDirection`, which invited exactly
    /// that substitution.
    func testThePlaneAndLineFormulasInvertEachOther() {
        let face = PlaneOrientation(dip: 90, dipDirection: 90)
        let parallelToFace = PlaneOrientation(dip: 90, dipDirection: 90)
        let perpendicularToFace = PlaneOrientation(dip: 0, dipDirection: 0)

        let correct = SamplingElement.plane(face)
        let misused = SamplingElement.line(LineOrientation(measuredAxis: face.upwardNormal)!)

        // Parallel to the face: invisible as a trace, but the line formula calls it perfect.
        XCTAssertEqual(correct.samplingEfficiency(for: parallelToFace), 0, accuracy: 1e-9)
        XCTAssertEqual(misused.samplingEfficiency(for: parallelToFace), 1, accuracy: 1e-9)

        // Perpendicular to the face: the best-sampled case, and the line formula calls it
        // invisible. The two are exactly the wrong way round.
        XCTAssertEqual(correct.samplingEfficiency(for: perpendicularToFace), 1, accuracy: 1e-9)
        XCTAssertEqual(misused.samplingEfficiency(for: perpendicularToFace), 0, accuracy: 1e-9)
    }

    /// A face shows the most traces of a set perpendicular to it, fewest of one parallel
    /// to it, and the trace spacing in between goes as `1 / sin` of the dihedral angle.
    func testWindowEfficiencyIsTheSineOfTheDihedralAngle() {
        let face = PlaneOrientation(dip: 90, dipDirection: 0)
        let element = SamplingElement.plane(face)
        for dihedral in [0.0, 30, 45, 60, 90] {
            // A set at `dihedral` to a vertical north-striking face.
            let set = PlaneOrientation(dip: 90, dipDirection: dihedral)
            XCTAssertEqual(
                element.samplingEfficiency(for: set),
                sin(GeoAngle.radians(fromDegrees: dihedral)),
                accuracy: 1e-9,
                "at a dihedral angle of \(dihedral)°"
            )
        }
    }

    /// Terzaghi's original relation: a borehole along the pole samples a set best, one
    /// lying in the plane never samples it.
    func testScanlineEfficiencyIsTheSineOfTheAngleToThePlane() {
        let set = PlaneOrientation(dip: 30, dipDirection: 0)
        let element = SamplingElement.line(LineOrientation(trend: 0, plunge: 0))
        // A horizontal north-south scanline against a plane dipping 30° north: the angle
        // between the pole and the scanline is 60°, so the efficiency is cos 60° = 0.5.
        XCTAssertEqual(element.samplingEfficiency(for: set), 0.5, accuracy: 1e-9)

        // Along the pole: perfect sampling.
        let alongPole = SamplingElement.line(LineOrientation(measuredAxis: set.upwardNormal)!)
        XCTAssertEqual(alongPole.samplingEfficiency(for: set), 1, accuracy: 1e-9)

        // In the plane: none at all.
        let inPlane = SamplingElement.line(set.strikeLine)
        XCTAssertEqual(inPlane.samplingEfficiency(for: set), 0, accuracy: 1e-9)
    }

    func testScanlineAndBoreholeShareTheirGeometry() {
        let line = LineOrientation(trend: 45, plunge: 10)
        for geometry in [
            SurveyGeometry.scanline(line: line, lengthMetres: 20),
            SurveyGeometry.borehole(axis: line, lengthMetres: 20)
        ] {
            XCTAssertEqual(geometry.biasCorrectionMethod, .terzaghi)
            XCTAssertEqual(geometry.samplingElement, .line(line))
            XCTAssertEqual(geometry.sampledLengthMetres, 20)
            XCTAssertNil(geometry.sampledAreaSquareMetres)
            XCTAssertNil(geometry.surfaceFacets)
        }
    }

    /// A photogrammetric trace map on a planar face is corrected exactly like a
    /// hand-mapped window; the cases differ only in what the record says about how the
    /// traces were obtained.
    func testWindowAndTraceMapShareTheirGeometry() {
        let face = PlaneOrientation(dip: 80, dipDirection: 200)
        for geometry in [
            SurveyGeometry.window(face: face, areaSquareMetres: 30),
            SurveyGeometry.traceMap(face: face, areaSquareMetres: 30)
        ] {
            XCTAssertEqual(geometry.biasCorrectionMethod, .terzaghi)
            XCTAssertEqual(geometry.samplingElement, .plane(face))
            XCTAssertEqual(geometry.sampledAreaSquareMetres, 30)
            XCTAssertNil(geometry.sampledLengthMetres)
        }
    }

    /// The property that makes the area-weighted method the right recommendation: it is
    /// not a different theory, it is the planar formula summed. With one facet the two
    /// must agree exactly.
    func testOneFacetSurfaceModelMatchesTheWindowExactly() {
        let face = PlaneOrientation(dip: 85, dipDirection: 120)
        let window = SurveyGeometry.window(face: face, areaSquareMetres: 17)
        let model = SurveyGeometry.surfaceModel(
            facets: [SurfaceFacet(orientation: face, areaSquareMetres: 17)]
        )
        for dip in stride(from: 0.0, through: 90.0, by: 5.0) {
            for dipDirection in stride(from: 0.0, to: 360.0, by: 30.0) {
                let discontinuity = PlaneOrientation(dip: dip, dipDirection: dipDirection)
                XCTAssertEqual(
                    model.samplingEfficiency(for: discontinuity)!,
                    window.samplingEfficiency(for: discontinuity)!,
                    accuracy: 1e-12,
                    "at \(discontinuity)"
                )
            }
        }
        // The facet's area cancels, so it is the orientations that matter, not the scale.
        let bigger = SurveyGeometry.surfaceModel(
            facets: [SurfaceFacet(orientation: face, areaSquareMetres: 1700)]
        )
        let probe = PlaneOrientation(dip: 40, dipDirection: 10)
        XCTAssertEqual(
            bigger.samplingEfficiency(for: probe)!,
            model.samplingEfficiency(for: probe)!,
            accuracy: 1e-12
        )
    }

    /// An exposure facing one way is nearly blind to the joints parallel to it, and an
    /// exposure facing several ways is not. This is the number a cap would hide, which is
    /// why the efficiency is reported rather than only its reciprocal.
    func testSurfaceModelShowsTheBlindZoneOfASingleOrientationExposure() {
        let face = PlaneOrientation(dip: 85, dipDirection: 120)
        let single = SurveyGeometry.surfaceModel(
            facets: [SurfaceFacet(orientation: face, areaSquareMetres: 100)]
        )
        let mixed = SurveyGeometry.surfaceModel(facets: [
            SurfaceFacet(orientation: face, areaSquareMetres: 60),
            SurfaceFacet(orientation: PlaneOrientation(dip: 20, dipDirection: 300), areaSquareMetres: 25),
            SurfaceFacet(orientation: PlaneOrientation(dip: 70, dipDirection: 10), areaSquareMetres: 15)
        ])

        // A set parallel to the single face is invisible to it.
        XCTAssertEqual(single.samplingEfficiency(for: face)!, 0, accuracy: 1e-9)
        // The same set is perfectly visible on an exposure that also faces other ways.
        XCTAssertGreaterThan(mixed.samplingEfficiency(for: face)!, 0.3)

        // Everything stays a proper fraction.
        for dip in stride(from: 0.0, through: 90.0, by: 10.0) {
            for dipDirection in stride(from: 0.0, to: 360.0, by: 45.0) {
                let discontinuity = PlaneOrientation(dip: dip, dipDirection: dipDirection)
                for geometry in [single, mixed] {
                    let efficiency = geometry.samplingEfficiency(for: discontinuity)!
                    XCTAssertGreaterThanOrEqual(efficiency, 0)
                    XCTAssertLessThanOrEqual(efficiency, 1)
                }
            }
        }
    }

    func testSurfaceModelAsksForTheAreaWeightedMethod() {
        let geometry = SurveyGeometry.surfaceModel(facets: [
            SurfaceFacet(orientation: PlaneOrientation(dip: 80, dipDirection: 10), areaSquareMetres: 12),
            SurfaceFacet(orientation: PlaneOrientation(dip: 20, dipDirection: 200), areaSquareMetres: 8)
        ])
        XCTAssertEqual(geometry.biasCorrectionMethod, .areaWeightedSurface)
        XCTAssertNil(geometry.samplingElement, "there is no one element to correct against")
        XCTAssertEqual(geometry.surfaceFacets?.count, 2)
        XCTAssertEqual(geometry.sampledAreaSquareMetres, 20)
    }

    func testSurfaceModelWithNoUsableAreaHasNoEfficiency() {
        let probe = PlaneOrientation(dip: 45, dipDirection: 90)
        XCTAssertNil(SurveyGeometry.surfaceModel(facets: []).samplingEfficiency(for: probe))
        XCTAssertNil(
            SurveyGeometry.surfaceModel(facets: [
                SurfaceFacet(orientation: probe, areaSquareMetres: 0)
            ]).samplingEfficiency(for: probe)
        )
    }

    /// Selective sampling cannot be bias-corrected: the bias is in the geologist's
    /// choice, and no geometry describes it. Saying so is better than offering a weight
    /// that looks like a correction.
    func testSelectiveSamplingCannotBeCorrected() {
        let probe = PlaneOrientation(dip: 45, dipDirection: 90)
        XCTAssertEqual(SurveyGeometry.selective.biasCorrectionMethod, .unavailable)
        XCTAssertNil(SurveyGeometry.selective.samplingElement)
        XCTAssertNil(SurveyGeometry.selective.samplingEfficiency(for: probe))
        XCTAssertNil(SurveyGeometry.selective.sampledLengthMetres)
        XCTAssertNil(SurveyGeometry.selective.sampledAreaSquareMetres)
    }

    func testSurveyGeometrySurvivesStorage() throws {
        let values: [SurveyGeometry] = [
            .scanline(line: LineOrientation(trend: 120, plunge: 5), lengthMetres: 15),
            .borehole(axis: LineOrientation(trend: 0, plunge: 90), lengthMetres: 40),
            .window(face: PlaneOrientation(dip: 75, dipDirection: 10), areaSquareMetres: 24),
            .traceMap(face: PlaneOrientation(dip: 75, dipDirection: 10), areaSquareMetres: 24),
            .surfaceModel(facets: [
                SurfaceFacet(orientation: PlaneOrientation(dip: 60, dipDirection: 90), areaSquareMetres: 5)
            ]),
            .selective
        ]
        for value in values {
            let data = try JSONEncoder().encode(value)
            XCTAssertEqual(try JSONDecoder().decode(SurveyGeometry.self, from: data), value)
        }
    }

    /// A vertical borehole is nearly blind to horizontal joints, which is the strongest
    /// sampling bias in the project and the reason the provenance is kept.
    func testVerticalBoreholeIsNearlyBlindToHorizontalJoints() {
        let geometry = SurveyGeometry.borehole(
            axis: LineOrientation(trend: 0, plunge: 90), lengthMetres: 40
        )
        // A horizontal set: the hole runs along its pole, so it is sampled perfectly.
        XCTAssertEqual(
            geometry.samplingEfficiency(for: PlaneOrientation(dip: 0, dipDirection: 0))!,
            1, accuracy: 1e-9
        )
        // A vertical set: the hole lies in it and never crosses it.
        XCTAssertEqual(
            geometry.samplingEfficiency(for: PlaneOrientation(dip: 90, dipDirection: 90))!,
            0, accuracy: 1e-9
        )
        // A set at 80°, the awkward case a cap exists for: an uncapped weight of 5.8.
        let steep = geometry.samplingEfficiency(for: PlaneOrientation(dip: 80, dipDirection: 90))!
        XCTAssertEqual(steep, 0.1736, accuracy: 1e-4)
        XCTAssertEqual(1 / steep, 5.76, accuracy: 0.01)
    }
}

final class CarryForwardTests: XCTestCase {

    private func previous() -> MeasurementRecord {
        MeasurementRecord(
            timestamp: Date(timeIntervalSince1970: 1000),
            mode: .lidar,
            plane: PlaneOrientation(dip: 45, dipDirection: 90),
            angularStandardDeviation: 0.5,
            sampleCount: 97,
            measuredFaceAzimuth: 90,
            geometry: MeasurementGeometry(placement: .rightSideOnFace, edge: .bottomEdge),
            surveyGeometry: .scanline(
                line: LineOrientation(trend: 30, plunge: 0), lengthMetres: 12
            ),
            location: MeasurementLocation(latitude: 24.9, longitude: 121.1),
            discontinuityType: .bedding,
            isrm: DiscontinuityDescription(weathering: .highlyWeathered, spacing: .measured(millimetres: 200)),
            jointSetID: UUID(),
            setAssignedAt: Date(timeIntervalSince1970: 500),
            observer: "KK",
            notes: "第一筆",
            photos: [PhotoReference(fileName: "a.heic", capturedAt: Date(timeIntervalSince1970: 900))],
            voiceMemo: VoiceMemoReference(
                fileName: "a.m4a", recordedAt: Date(timeIntervalSince1970: 900), duration: 3
            )
        )
    }

    func testSettingsAreCarriedForward() {
        let next = MeasurementRecord.next(
            after: previous(), timestamp: Date(timeIntervalSince1970: 2000)
        )
        XCTAssertEqual(next.mode, .lidar)
        XCTAssertEqual(next.discontinuityType, .bedding)
        XCTAssertEqual(next.isrm.weathering, .highlyWeathered)
        XCTAssertEqual(next.isrm.spacing, .measured(millimetres: 200))
        XCTAssertEqual(next.observer, "KK")
        XCTAssertEqual(next.geometry.placement, .rightSideOnFace)
        XCTAssertEqual(next.geometry.edge, .bottomEdge)
        XCTAssertEqual(next.surveyGeometry, previous().surveyGeometry)
    }

    /// The rule that matters. A carried-over attitude is a duplicate measurement wearing
    /// a new timestamp, and nothing downstream could tell it from a real one.
    func testTheAttitudeIsNeverCarriedForward() {
        let source = previous()
        for policy in [CarryForwardPolicy.standard, .setupOnly, .fresh] {
            let next = MeasurementRecord.next(
                after: source, policy: policy, timestamp: Date(timeIntervalSince1970: 2000)
            )
            XCTAssertNil(next.plane, "policy \(policy)")
            XCTAssertNil(next.lineation)
            XCTAssertNil(next.angularStandardDeviation)
            XCTAssertNil(next.sampleCount)
            XCTAssertNil(next.measuredFaceAzimuth)
            XCTAssertFalse(next.hasAttitude)
        }
    }

    func testPerDiscontinuityContentIsNeverCarriedForward() {
        let source = previous()
        for policy in [CarryForwardPolicy.standard, .setupOnly, .fresh] {
            let next = MeasurementRecord.next(
                after: source, policy: policy, timestamp: Date(timeIntervalSince1970: 2000)
            )
            XCTAssertNil(next.location, "position moves along the exposure")
            XCTAssertNil(next.notes)
            XCTAssertTrue(next.photos.isEmpty)
            XCTAssertNil(next.voiceMemo)
            XCTAssertNil(next.jointSetID, "the clustering writes this back; it is not typed in")
            XCTAssertNil(next.setAssignedAt)
            XCTAssertNotEqual(next.id, source.id)
            XCTAssertEqual(next.timestamp, Date(timeIntervalSince1970: 2000))
        }
    }

    func testFreshPolicyCarriesNothing() {
        let next = MeasurementRecord.next(
            after: previous(), policy: .fresh, timestamp: Date(timeIntervalSince1970: 2000)
        )
        XCTAssertEqual(next.mode, .contact)
        XCTAssertEqual(next.discontinuityType, .joint)
        XCTAssertTrue(next.isrm.isEmpty)
        XCTAssertNil(next.observer)
        XCTAssertNil(next.surveyGeometry)
        XCTAssertEqual(next.geometry, .default)
    }

    /// For a station where every joint is described individually: the setup is kept so
    /// the geologist is not re-picking a placement, but the description starts blank so
    /// the previous joint's weathering grade is not inherited by accident.
    func testSetupOnlyPolicyKeepsTheSetupAndClearsTheDescription() {
        let next = MeasurementRecord.next(
            after: previous(), policy: .setupOnly, timestamp: Date(timeIntervalSince1970: 2000)
        )
        XCTAssertEqual(next.geometry.placement, .rightSideOnFace)
        XCTAssertEqual(next.surveyGeometry, previous().surveyGeometry)
        XCTAssertEqual(next.observer, "KK")
        XCTAssertTrue(next.isrm.isEmpty)
        XCTAssertEqual(next.discontinuityType, .bedding)
    }

    func testCarriedRecordIsStampedWithTheCurrentConvention() {
        var source = previous()
        source.conventionVersion = 1          // as if read from an older store
        let next = MeasurementRecord.next(
            after: source, timestamp: Date(timeIntervalSince1970: 2000)
        )
        XCTAssertEqual(
            next.conventionVersion, AttitudeConvention.version,
            "a new record is written under the current convention, not the old one"
        )
    }

    func testPolicySurvivesStorage() throws {
        for policy in [CarryForwardPolicy.standard, .setupOnly, .fresh] {
            let data = try JSONEncoder().encode(policy)
            XCTAssertEqual(try JSONDecoder().decode(CarryForwardPolicy.self, from: data), policy)
        }
    }
}

final class ProjectAndStationTests: XCTestCase {

    func testProjectCarriesItsOwnDefaults() {
        let project = ProjectRecord(
            name: "北橫公路邊坡",
            createdAt: Date(timeIntervalSince1970: 0),
            fallbackDeclination: MagneticDeclination(degreesEast: -4),
            carryForwardPolicy: .setupOnly
        )
        XCTAssertEqual(project.fallbackDeclination?.degreesEast, -4)
        XCTAssertFalse(project.carryForwardPolicy.isrm)
        XCTAssertEqual(project.conventionVersion, AttitudeConvention.version)
    }

    func testStationHoldsTheSamplingSetupForItsMeasurements() {
        let station = StationRecord(
            name: "ST-03",
            createdAt: Date(timeIntervalSince1970: 0),
            lithology: "砂岩",
            defaultSurveyGeometry: .window(
                face: PlaneOrientation(dip: 85, dipDirection: 120), areaSquareMetres: 18
            ),
            outcropFace: PlaneOrientation(dip: 85, dipDirection: 120)
        )
        XCTAssertEqual(station.name, "ST-03")
        XCTAssertEqual(station.defaultSurveyGeometry!.biasCorrectionMethod, .terzaghi)
    }

    func testRecordsSurviveStorage() throws {
        let project = ProjectRecord(name: "P", createdAt: Date(timeIntervalSince1970: 0))
        let station = StationRecord(name: "S", createdAt: Date(timeIntervalSince1970: 0))
        let projectData = try JSONEncoder().encode(project)
        let stationData = try JSONEncoder().encode(station)
        XCTAssertEqual(try JSONDecoder().decode(ProjectRecord.self, from: projectData), project)
        XCTAssertEqual(try JSONDecoder().decode(StationRecord.self, from: stationData), station)
    }
}
