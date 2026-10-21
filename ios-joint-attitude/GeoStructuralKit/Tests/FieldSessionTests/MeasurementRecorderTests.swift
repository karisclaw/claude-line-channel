import Foundation
import XCTest
import OrientationCore
import FieldRecord
@testable import FieldSession

/// Builds a device attitude for a known plane, as the test helper in OrientationCoreTests
/// does — repeated here because test targets do not share code.
///
/// The placement has to be passed in, and has to match the one the recorder is set to.
/// A phone laid on its left side reads the face through its `+X` axis, not through its
/// back, so building the attitude around `+Z` and then telling the recorder the left side
/// was used describes two different physical acts and yields a plane that is neither.
private func attitude(
    dip: Double,
    dipDirection: Double,
    placement: DevicePlacement = DeviceAttitude.defaultPlacement
) -> Quaternion {
    let normal = PlaneOrientation(dip: dip, dipDirection: dipDirection).upwardNormal
    let reference = abs(normal.x) < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 1, 0)
    let u = reference.cross(normal).normalized!
    let v = normal.cross(u)

    // The contacting axis points along the outward normal; the other two go anywhere
    // orthogonal, because how far the phone is rolled against the rock cannot change the
    // attitude it reads. Each triple is right-handed, as a rotation must be.
    switch placement.outwardNormalAxis {
    case .plusZ:
        return Quaternion(deviceXInWorld: u, deviceYInWorld: v, deviceZInWorld: normal)!
    case .minusZ:
        return Quaternion(deviceXInWorld: u, deviceYInWorld: -v, deviceZInWorld: -normal)!
    case .plusX:
        return Quaternion(deviceXInWorld: normal, deviceYInWorld: u, deviceZInWorld: v)!
    case .minusX:
        return Quaternion(deviceXInWorld: -normal, deviceYInWorld: u, deviceZInWorld: -v)!
    case .plusY:
        return Quaternion(deviceXInWorld: v, deviceYInWorld: normal, deviceZInWorld: u)!
    case .minusY:
        return Quaternion(deviceXInWorld: -v, deviceYInWorld: -normal, deviceZInWorld: u)!
    }
}

private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

private func makeRecorder(
    policy: ReviewPolicy = .standard,
    context: MeasurementContext = MeasurementContext(
        location: MeasurementLocation(latitude: 24.9, longitude: 121.1, horizontalAccuracy: 5),
        magneticEnvironment: MagneticEnvironment(
            fieldStrength: 46, accuracy: .high, headingAccuracy: 5
        ),
        declination: MagneticDeclination(degreesEast: -4)
    )
) -> MeasurementRecorder {
    var recorder = MeasurementRecorder(
        session: FieldSessionState(projectID: UUID(), stationID: UUID()),
        policy: policy,
        now: { epoch }
    )
    recorder.handle(.contextUpdate(context))
    return recorder
}

/// Feeds motion until the recorder leaves the given stages, or gives up.
private func feedMotion(
    _ recorder: inout MeasurementRecorder,
    dip: Double = 42,
    dipDirection: Double = 137,
    placement: DevicePlacement? = nil,
    startingAt start: TimeInterval = 0,
    count: Int = 200,
    userAcceleration: Vector3 = .zero
) -> [MeasurementRecorder.Outcome] {
    var outcomes: [MeasurementRecorder.Outcome] = []
    // Default to whatever the recorder is actually set to, so a test that changes the
    // placement cannot forget to change the attitude with it.
    let device = attitude(
        dip: dip,
        dipDirection: dipDirection,
        placement: placement ?? recorder.session.geometry.placement
    )
    for index in 0..<count {
        let sample = MotionSample(
            timestamp: start + Double(index) / 64,
            attitude: device,
            userAcceleration: userAcceleration
        )
        let outcome = recorder.handle(.motion(sample))
        outcomes.append(outcome)
        if case .saved = outcome { break }
        if case .readyForReview = outcome { break }
    }
    return outcomes
}

final class MeasurementRecorderTests: XCTestCase {

    // MARK: What a press means in each state

    func testPressFromIdleStartsMeasuring() {
        var recorder = makeRecorder()
        XCTAssertEqual(recorder.stage, .idle)
        XCTAssertEqual(recorder.handle(.press(at: epoch)), .started)
        guard case .settling = recorder.stage else { return XCTFail("should be settling") }
    }

    /// The rule that matters most with a key the geologist cannot see: a second press
    /// **cancels**. Starting a second burst would discard the first one silently, and a
    /// cancellation is recoverable where a lost measurement is not.
    func testSecondPressWhileMeasuringCancelsRatherThanRestarting() {
        var recorder = makeRecorder()
        recorder.handle(.press(at: epoch))
        _ = feedMotion(&recorder, count: 20)
        guard case .collecting = recorder.stage else { return XCTFail("should be collecting") }

        XCTAssertEqual(recorder.handle(.press(at: epoch.addingTimeInterval(1))), .cancelled)
        XCTAssertEqual(recorder.stage, .idle)
    }

    func testPressDuringSettlingAlsoCancels() {
        var recorder = makeRecorder()
        recorder.handle(.press(at: epoch))
        // Shaking, so it never settles.
        _ = feedMotion(&recorder, count: 5, userAcceleration: Vector3(0.6, -0.4, 0.3))
        guard case .settling = recorder.stage else { return XCTFail("should still be settling") }
        XCTAssertEqual(recorder.handle(.press(at: epoch.addingTimeInterval(1))), .cancelled)
    }

    func testPressInReviewAcceptsACleanMeasurement() {
        var recorder = makeRecorder()
        recorder.handle(.press(at: epoch))
        _ = feedMotion(&recorder)
        guard case .review = recorder.stage else { return XCTFail("should be in review") }

        guard case .saved(let record) = recorder.handle(.press(at: epoch.addingTimeInterval(5)))
        else { return XCTFail("a clean measurement should accept on a press") }
        XCTAssertEqual(record.plane!.dip, 42, accuracy: 0.01)
        XCTAssertEqual(record.timestamp, epoch)
    }

    /// A warning withdraws the blind path and nothing else. The measurement is still
    /// there, and an on-screen confirmation still saves it.
    func testAFlaggedMeasurementRefusesABlindPressButStillSaves() {
        var recorder = makeRecorder(
            context: MeasurementContext(
                location: MeasurementLocation(latitude: 24.9, longitude: 121.1, horizontalAccuracy: 5),
                magneticEnvironment: MagneticEnvironment(
                    fieldStrength: 140, accuracy: .low, headingAccuracy: 30
                )
            )
        )
        recorder.handle(.press(at: epoch))
        _ = feedMotion(&recorder)

        guard case .refusedBlindConfirmation(let warnings) =
                recorder.handle(.press(at: epoch.addingTimeInterval(5)))
        else { return XCTFail("a disturbed measurement must not accept blind") }
        XCTAssertTrue(warnings.contains { if case .magneticDisturbance = $0 { true } else { false } })

        // Still in review, nothing lost.
        guard case .review = recorder.stage else { return XCTFail("should still be in review") }

        // And the geologist, having looked, may keep it.
        guard case .saved(let record) = recorder.handle(.confirmOnScreen)
        else { return XCTFail("an on-screen confirmation must always be allowed") }
        XCTAssertTrue(record.hasSuspectAzimuth)
        XCTAssertEqual(record.plane!.dip, 42, accuracy: 0.01, "the dip is unaffected by the magnetometer")
    }

    func testDiscardThrowsTheMeasurementAway() {
        var recorder = makeRecorder()
        recorder.handle(.press(at: epoch))
        _ = feedMotion(&recorder)
        XCTAssertEqual(recorder.handle(.discard), .discarded)
        XCTAssertEqual(recorder.stage, .idle)
        XCTAssertNil(recorder.session.lastRecord)
    }

    func testDiscardOutsideReviewDoesNothing() {
        var recorder = makeRecorder()
        XCTAssertEqual(recorder.handle(.discard), .unchanged)
        XCTAssertEqual(recorder.stage, .idle)
    }

    // MARK: Repeat presses

    /// A Bluetooth key held down repeats, and a cold thumb double-taps. Neither may
    /// cancel a measurement that was just started.
    func testRepeatPressesWithinTheIntervalAreIgnored() {
        var recorder = makeRecorder()
        XCTAssertEqual(recorder.handle(.press(at: epoch)), .started)
        XCTAssertEqual(recorder.handle(.press(at: epoch.addingTimeInterval(0.05))), .ignoredRepeatPress)
        XCTAssertEqual(recorder.handle(.press(at: epoch.addingTimeInterval(0.2))), .ignoredRepeatPress)
        guard case .settling = recorder.stage else {
            return XCTFail("a repeat press must not have cancelled the burst")
        }
        // Past the interval, a press is deliberate again.
        XCTAssertEqual(recorder.handle(.press(at: epoch.addingTimeInterval(0.4))), .cancelled)
    }

    /// The interval has to be short enough that the deliberate second press — the one
    /// that accepts a measurement — still lands.
    func testTheAcceptingPressIsNotSwallowedByTheDebounce() {
        var recorder = makeRecorder()
        recorder.handle(.press(at: epoch))
        _ = feedMotion(&recorder)
        // A burst takes over a second, so the accepting press is always well clear.
        guard case .saved = recorder.handle(.press(at: epoch.addingTimeInterval(2)))
        else { return XCTFail("the accepting press was swallowed") }
    }

    // MARK: Consecutive measurements

    func testSettingsCarryForwardAndTheAttitudeDoesNot() {
        var recorder = makeRecorder()
        recorder.session.geometry = MeasurementGeometry(placement: .leftSideOnFace, edge: .leftEdge)

        recorder.handle(.press(at: epoch))
        _ = feedMotion(&recorder, dip: 42, dipDirection: 137)
        guard case .saved(let first) = recorder.handle(.press(at: epoch.addingTimeInterval(2)))
        else { return XCTFail("first measurement not saved") }

        // Give it a description, as the geologist would after saving.
        var described = first
        described.isrm.weathering = .moderatelyWeathered
        described.discontinuityType = .bedding
        recorder.session.lastRecord = described

        recorder.handle(.press(at: epoch.addingTimeInterval(10)))
        _ = feedMotion(&recorder, dip: 61, dipDirection: 20, startingAt: 100)
        guard case .saved(let second) = recorder.handle(.press(at: epoch.addingTimeInterval(13)))
        else { return XCTFail("second measurement not saved") }

        // Carried: the setup and the description.
        XCTAssertEqual(second.isrm.weathering, .moderatelyWeathered)
        XCTAssertEqual(second.discontinuityType, .bedding)
        XCTAssertEqual(second.geometry.placement, .leftSideOnFace)
        // Not carried: the attitude, which is the measurement itself.
        XCTAssertEqual(second.plane!.dip, 61, accuracy: 0.01)
        XCTAssertNotEqual(second.id, first.id)
    }

    func testPressAfterSavingStartsTheNextMeasurement() {
        var recorder = makeRecorder()
        recorder.handle(.press(at: epoch))
        _ = feedMotion(&recorder)
        recorder.handle(.press(at: epoch.addingTimeInterval(2)))
        guard case .saved = recorder.stage else { return XCTFail("not saved") }
        XCTAssertEqual(recorder.handle(.press(at: epoch.addingTimeInterval(4))), .started)
    }

    // MARK: The context snapshot

    /// The surroundings are snapshotted when the attitude is determined, not when the
    /// geologist gets round to confirming. A position recorded thirty metres further
    /// along the exposure belongs to a different joint.
    func testTheContextIsSnapshottedWhenTheBurstFinishesNotAtConfirmation() {
        var recorder = makeRecorder()
        recorder.handle(.press(at: epoch))
        _ = feedMotion(&recorder)

        // The geologist walks on before confirming, and the position updates.
        recorder.handle(.contextUpdate(MeasurementContext(
            location: MeasurementLocation(latitude: 25.9, longitude: 122.1, horizontalAccuracy: 5)
        )))

        guard case .saved(let record) = recorder.handle(.confirmOnScreen)
        else { return XCTFail("not saved") }
        XCTAssertEqual(record.location?.latitude, 24.9, "the position moved after the measurement")
        XCTAssertNotNil(record.magneticEnvironment, "the later update must not have erased it")
    }

    func testMissingPositionIsWarnedButDoesNotWithdrawTheBlindPath() {
        var recorder = makeRecorder(context: MeasurementContext())
        recorder.handle(.press(at: epoch))
        let outcomes = feedMotion(&recorder)
        guard case .readyForReview(let pending) = outcomes.last else {
            return XCTFail("should be ready for review")
        }
        XCTAssertTrue(pending.warnings.contains(.positionUnavailable))
        XCTAssertFalse(pending.requiresALook, "no fix is normal in a gorge")
        guard case .saved = recorder.handle(.press(at: epoch.addingTimeInterval(2)))
        else { return XCTFail("a press should still accept it") }
    }

    func testAnInvalidAccuracyCountsAsNoPosition() {
        var recorder = makeRecorder(context: MeasurementContext(
            location: MeasurementLocation(latitude: 24.9, longitude: 121.1, horizontalAccuracy: -1)
        ))
        recorder.handle(.press(at: epoch))
        let outcomes = feedMotion(&recorder)
        guard case .readyForReview(let pending) = outcomes.last else { return XCTFail("no review") }
        XCTAssertTrue(pending.warnings.contains(.positionUnavailable))
    }

    // MARK: Scatter

    func testExcessiveScatterWithdrawsTheBlindPath() {
        var recorder = makeRecorder()
        recorder.handle(.press(at: epoch))

        // Wobble the attitude by several degrees through the burst.
        var index = 0
        var sawReview = false
        while index < 400 {
            let wobble = 6.0 * sin(Double(index) * 0.4)
            let sample = MotionSample(
                timestamp: Double(index) / 64,
                attitude: attitude(dip: 42 + wobble, dipDirection: 137)
            )
            if case .readyForReview(let pending) = recorder.handle(.motion(sample)) {
                sawReview = true
                XCTAssertTrue(pending.requiresALook)
                XCTAssertTrue(pending.warnings.contains {
                    if case .excessiveScatter = $0 { true } else { false }
                })
                break
            }
            index += 1
        }
        XCTAssertTrue(sawReview, "the burst never finished")
    }

    // MARK: Policies

    func testAutoConfirmSavesACleanMeasurementWithoutReview() {
        var recorder = makeRecorder(policy: ReviewPolicy(autoConfirmWhenClean: true))
        recorder.handle(.press(at: epoch))
        let outcomes = feedMotion(&recorder)
        guard case .saved(let record) = outcomes.last else {
            return XCTFail("auto-confirm should have saved it outright")
        }
        XCTAssertEqual(record.plane!.dip, 42, accuracy: 0.01)
        XCTAssertEqual(recorder.session.lastRecord?.id, record.id)
    }

    /// Auto-confirm must still stop for something flagged, or the one setting that makes
    /// recording fastest becomes the one that fills a project with unexamined data.
    func testAutoConfirmStillStopsForAFlaggedMeasurement() {
        var recorder = makeRecorder(
            policy: ReviewPolicy(autoConfirmWhenClean: true),
            context: MeasurementContext(
                location: MeasurementLocation(latitude: 24.9, longitude: 121.1, horizontalAccuracy: 5),
                magneticEnvironment: MagneticEnvironment(fieldStrength: 140, accuracy: .low)
            )
        )
        recorder.handle(.press(at: epoch))
        let outcomes = feedMotion(&recorder)
        guard case .readyForReview(let pending) = outcomes.last else {
            return XCTFail("should have stopped for review")
        }
        XCTAssertTrue(pending.requiresALook)
    }

    /// For a geologist who has decided to review everything at the desk.
    func testUnattendedPolicyNeverWithdrawsTheBlindPath() {
        var recorder = makeRecorder(
            policy: .unattended,
            context: MeasurementContext(
                magneticEnvironment: MagneticEnvironment(fieldStrength: 140, accuracy: .uncalibrated)
            )
        )
        recorder.handle(.press(at: epoch))
        let outcomes = feedMotion(&recorder)
        guard case .saved(let record) = outcomes.last else {
            return XCTFail("the unattended policy should save regardless")
        }
        XCTAssertTrue(record.hasSuspectAzimuth, "the flag is still on the record")
    }

    // MARK: Lineations

    func testALineationBurstProducesALineation() {
        var recorder = MeasurementRecorder(
            session: FieldSessionState(projectID: UUID(), stationID: UUID(), target: .lineation),
            now: { epoch }
        )
        recorder.handle(.press(at: epoch))

        let device = attitude(dip: 30, dipDirection: 90)
        var saved: MeasurementRecord?
        for index in 0..<200 {
            let sample = MotionSample(timestamp: Double(index) / 64, attitude: device)
            if case .readyForReview = recorder.handle(.motion(sample)) {
                if case .saved(let record) = recorder.handle(.press(at: epoch.addingTimeInterval(5))) {
                    saved = record
                }
                break
            }
        }
        let record = try! XCTUnwrap(saved)
        XCTAssertNotNil(record.lineation)
        XCTAssertNil(record.plane)
        XCTAssertNil(record.measuredFaceAzimuth, "a lineation has no face")
    }

    // MARK: Housekeeping

    func testMotionWhileIdleDoesNotStartAnything() {
        var recorder = makeRecorder()
        _ = feedMotion(&recorder, count: 100)
        XCTAssertEqual(recorder.stage, .idle)
        XCTAssertNil(recorder.session.lastRecord)
    }

    func testResetKeepsTheSettingsAndThePreviousRecord() {
        var recorder = makeRecorder()
        recorder.handle(.press(at: epoch))
        _ = feedMotion(&recorder)
        recorder.handle(.press(at: epoch.addingTimeInterval(2)))
        let saved = recorder.session.lastRecord

        recorder.handle(.press(at: epoch.addingTimeInterval(4)))
        recorder.reset()
        XCTAssertEqual(recorder.stage, .idle)
        XCTAssertEqual(recorder.session.lastRecord?.id, saved?.id)
    }

    func testTheMeasuredFaceAzimuthIsRecorded() {
        var recorder = makeRecorder()
        recorder.handle(.press(at: epoch))
        _ = feedMotion(&recorder, dip: 62, dipDirection: 148)
        guard case .saved(let record) = recorder.handle(.press(at: epoch.addingTimeInterval(2)))
        else { return XCTFail("not saved") }
        XCTAssertEqual(record.measuredFaceAzimuth!, 148, accuracy: 0.01)
    }
}

final class ControlSizingTests: XCTestCase {

    /// Apple's published minimum is 44 points for a bare fingertip; a glove needs more.
    func testGlovedControlsAreLargerThanTheBareFingerMinimum() {
        XCTAssertEqual(ControlSizing.standard.minimumTouchTargetPoints, 44)
        XCTAssertGreaterThan(
            ControlSizing.gloved.minimumTouchTargetPoints,
            ControlSizing.standard.minimumTouchTargetPoints
        )
        XCTAssertGreaterThanOrEqual(ControlSizing.gloved.minimumTouchTargetPoints, 60)
    }

    /// Spacing matters as much as size: two large buttons with no gap are one ambiguous
    /// region to a glove.
    func testGlovedSpacingGrowsWithTheTargets() {
        XCTAssertGreaterThan(ControlSizing.gloved.spacingPoints, ControlSizing.standard.spacingPoints)
        XCTAssertGreaterThan(
            ControlSizing.gloved.primaryActionHeightPoints,
            ControlSizing.gloved.minimumTouchTargetPoints
        )
    }

    func testEveryModeHasSizing() {
        for mode in ControlSizing.Mode.allCases {
            let sizing = ControlSizing.sizing(for: mode)
            XCTAssertEqual(sizing.mode, mode)
            XCTAssertGreaterThan(sizing.minimumTouchTargetPoints, 0)
            XCTAssertGreaterThan(sizing.textScale, 0)
        }
    }

    /// The primary action has to sit where a thumb can reach it one-handed. A control at
    /// the top of the screen is a two-handed control, and on a slope with a hammer in the
    /// other hand it will not be used.
    func testThumbReachBand() {
        let sizing = ControlSizing.gloved
        let screen = 850.0
        // Sitting on the bottom edge: reachable.
        XCTAssertTrue(sizing.isWithinThumbReach(
            topPoints: screen - sizing.primaryActionHeightPoints,
            heightPoints: sizing.primaryActionHeightPoints,
            screenHeightPoints: screen
        ))
        // At the top: not.
        XCTAssertFalse(sizing.isWithinThumbReach(
            topPoints: 40, heightPoints: sizing.primaryActionHeightPoints, screenHeightPoints: screen
        ))
        // Hanging off the bottom: not, either.
        XCTAssertFalse(sizing.isWithinThumbReach(
            topPoints: screen - 20, heightPoints: 110, screenHeightPoints: screen
        ))
        XCTAssertFalse(sizing.isWithinThumbReach(
            topPoints: 0, heightPoints: 10, screenHeightPoints: 0
        ))
    }

    func testSizingSurvivesStorage() throws {
        for sizing in [ControlSizing.standard, .gloved] {
            let data = try JSONEncoder().encode(sizing)
            XCTAssertEqual(try JSONDecoder().decode(ControlSizing.self, from: data), sizing)
        }
    }
}
