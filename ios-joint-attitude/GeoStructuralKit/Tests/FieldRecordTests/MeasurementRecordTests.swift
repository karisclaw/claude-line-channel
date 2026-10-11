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
                seepage: .damp,
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

    func testScanlineSamplesAlongItsOwnDirection() {
        let line = LineOrientation(trend: 45, plunge: 10)
        let geometry = SurveyGeometry.scanline(line: line, lengthMetres: 20)
        XCTAssertTrue(geometry.supportsTerzaghiCorrection)
        XCTAssertEqual(geometry.samplingDirection, line.downPlungeVector)
    }

    func testWindowSamplesAlongItsFaceNormal() {
        let face = PlaneOrientation(dip: 80, dipDirection: 200)
        let geometry = SurveyGeometry.window(face: face, areaSquareMetres: 30)
        XCTAssertTrue(geometry.supportsTerzaghiCorrection)
        XCTAssertEqual(geometry.samplingDirection, face.upwardNormal)
    }

    /// Selective sampling cannot be bias-corrected: the bias is in the geologist's
    /// choice, and no geometry describes it. Saying so is better than offering a weight
    /// that looks like a correction.
    func testSelectiveSamplingCannotBeCorrected() {
        XCTAssertFalse(SurveyGeometry.selective.supportsTerzaghiCorrection)
        XCTAssertNil(SurveyGeometry.selective.samplingDirection)
    }

    func testSurveyGeometrySurvivesStorage() throws {
        let values: [SurveyGeometry] = [
            .scanline(line: LineOrientation(trend: 120, plunge: 5), lengthMetres: 15),
            .window(face: PlaneOrientation(dip: 75, dipDirection: 10), areaSquareMetres: 24),
            .selective
        ]
        for value in values {
            let data = try JSONEncoder().encode(value)
            XCTAssertEqual(try JSONDecoder().decode(SurveyGeometry.self, from: data), value)
        }
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
        XCTAssertTrue(station.defaultSurveyGeometry!.supportsTerzaghiCorrection)
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
