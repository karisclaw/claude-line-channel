#if canImport(SwiftUI)
import SwiftUI
import OrientationCore
import FieldRecord
import FieldSession

// The recording screen. One large control at the bottom, a live readout above it, and
// nothing else competing for a gloved thumb.
//
// **Not run, not screenshotted.** Everything decidable has been moved into
// `FieldSession`; this is layout. Read it as a proposal for the arrangement, not as
// finished work, and expect to move things once it has been held in a real hand.

/// Carries the current sizing down the view tree, so no view hard-codes a size.
public struct ControlSizingKey: EnvironmentKey {
    public static let defaultValue = ControlSizing.standard
}

public extension EnvironmentValues {
    var controlSizing: ControlSizing {
        get { self[ControlSizingKey.self] }
        set { self[ControlSizingKey.self] = newValue }
    }
}

/// What the recorder is doing, in one line, large enough to read at arm's length.
public struct StageBanner: View {

    @Environment(\.controlSizing) private var sizing

    public let stage: MeasurementRecorder.Stage

    public init(stage: MeasurementRecorder.Stage) {
        self.stage = stage
    }

    public var body: some View {
        VStack(spacing: sizing.spacingPoints / 2) {
            Text(title)
                .font(.system(size: 22 * sizing.textScale, weight: .semibold))
            if let detail {
                Text(detail)
                    .font(.system(size: 17 * sizing.textScale))
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch stage {
        case .idle: "準備量測"
        case .settling: "請保持靜止"
        case .collecting: "取樣中"
        case .review: "請確認"
        case .saved: "已儲存"
        }
    }

    private var detail: String? {
        switch stage {
        case .idle:
            nil
        case .settling(let assessment):
            assessment.hasVerdict ? nil : "偵測中"
        case .collecting(let progress, _):
            "\(Int(progress * 100))%"
        case .review(let pending):
            pending.burst.plane.map { "\($0)  ±\(String(format: "%.1f", pending.burst.angularStandardDeviation))°" }
                ?? pending.burst.line.map { "\($0)" }
        case .saved(let record):
            record.plane.map { "\($0)" } ?? record.lineation.map { "\($0)" }
        }
    }
}

/// The one control that takes a measurement.
///
/// Its label changes with the stage, because the same press means different things and
/// the geologist should not have to remember which. It sits at the bottom so a thumb can
/// reach it without the other hand — see ``ControlSizing/thumbReachFraction``.
public struct PrimaryActionButton: View {

    @Environment(\.controlSizing) private var sizing

    public let stage: MeasurementRecorder.Stage
    public let action: () -> Void

    public init(stage: MeasurementRecorder.Stage, action: @escaping () -> Void) {
        self.stage = stage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 24 * sizing.textScale, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: sizing.primaryActionHeightPoints)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch stage {
        case .idle, .saved: "量測"
        case .settling, .collecting: "取消"
        case .review(let pending): pending.requiresALook ? "需確認" : "接受"
        }
    }

    private var tint: Color {
        switch stage {
        case .idle, .saved: .accentColor
        case .settling, .collecting: .orange
        case .review(let pending): pending.requiresALook ? .yellow : .green
        }
    }
}

/// One warning, stated as what it costs rather than as a code.
public struct WarningRow: View {

    @Environment(\.controlSizing) private var sizing

    public let warning: MeasurementWarning

    public init(warning: MeasurementWarning) {
        self.warning = warning
    }

    public var body: some View {
        HStack(spacing: sizing.spacingPoints) {
            Image(systemName: symbol)
            Text(message)
                .font(.system(size: 17 * sizing.textScale))
            Spacer(minLength: 0)
        }
        .frame(minHeight: sizing.minimumTouchTargetPoints)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch warning {
        case .magneticDisturbance: "dot.radiowaves.left.and.right"
        case .placementDisagreement: "iphone.gen3.radiowaves.left.and.right"
        case .excessiveScatter: "scribble.variable"
        case .sampleRateShortfall: "speedometer"
        case .positionUnavailable: "location.slash"
        case .descriptionInconsistency: "exclamationmark.triangle"
        }
    }

    /// Says what is affected, not what rule fired. "磁干擾" alone leaves the geologist
    /// guessing whether the dip is usable; it is, and that is the useful half.
    private var message: String {
        switch warning {
        case .magneticDisturbance:
            "磁干擾：傾向／走向不可信，傾角仍然有效"
        case .placementDisagreement(let selected, let implied):
            "貼合面可能有誤：選定 \(selected.rawValue) 軸，衝量指向 \(implied.rawValue) 軸"
        case .excessiveScatter(let degrees, let limit):
            String(format: "取樣分散 %.1f°，超過 %.1f°", degrees, limit)
        case .sampleRateShortfall(let effective, let requested):
            String(format: "取樣率 %.0f Hz，低於要求的 %.0f Hz（平均仍然有效）", effective, requested)
        case .positionUnavailable:
            "無定位：這筆無法放上地圖或匯出 KML"
        case .descriptionInconsistency:
            "描述欄位互相矛盾，請檢查"
        }
    }
}

/// The recording screen.
public struct MeasureScreen: View {

    @Environment(\.controlSizing) private var sizing

    public let stage: MeasurementRecorder.Stage
    public let onPress: () -> Void
    public let onDiscard: () -> Void
    public let onConfirmOnScreen: () -> Void

    public init(
        stage: MeasurementRecorder.Stage,
        onPress: @escaping () -> Void,
        onDiscard: @escaping () -> Void,
        onConfirmOnScreen: @escaping () -> Void
    ) {
        self.stage = stage
        self.onPress = onPress
        self.onDiscard = onDiscard
        self.onConfirmOnScreen = onConfirmOnScreen
    }

    public var body: some View {
        VStack(spacing: sizing.spacingPoints) {
            Spacer(minLength: 0)
            StageBanner(stage: stage)

            if case .review(let pending) = stage, !pending.warnings.isEmpty {
                VStack(alignment: .leading, spacing: sizing.spacingPoints) {
                    ForEach(Array(pending.warnings.enumerated()), id: \.offset) { item in
                        WarningRow(warning: item.element)
                    }
                }
                .padding(.horizontal)
            }

            Spacer(minLength: 0)

            // Everything tappable is in the bottom band, where one thumb can reach it.
            VStack(spacing: sizing.spacingPoints) {
                if case .review(let pending) = stage {
                    if pending.requiresALook {
                        Button("看過了，仍要儲存", action: onConfirmOnScreen)
                            .font(.system(size: 20 * sizing.textScale, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: sizing.minimumTouchTargetPoints)
                            .buttonStyle(.bordered)
                    }
                    Button("丟棄", action: onDiscard)
                        .font(.system(size: 20 * sizing.textScale))
                        .frame(maxWidth: .infinity)
                        .frame(height: sizing.minimumTouchTargetPoints)
                        .buttonStyle(.bordered)
                }
                PrimaryActionButton(stage: stage, action: onPress)
            }
            .padding(.horizontal)
            .padding(.bottom, sizing.spacingPoints)
        }
        .onExternalTrigger(perform: onPress)
    }
}
#endif
