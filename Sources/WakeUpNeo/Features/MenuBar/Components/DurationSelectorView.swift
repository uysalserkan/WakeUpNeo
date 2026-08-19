import SwiftUI
import WakeUpNeoCore

// MARK: - DurationSelectorView

/// A single unified segmented duration control (`15m`, `30m`, `1h`, `2h`, `∞`).
/// Implements native macOS segmented control behavior without nested floating cards.
struct DurationSelectorView: View {

    let manager: SleepManager
    let eyeColor: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(DefaultDuration.allCases, id: \.self) { preset in
                durationSegment(preset)
            }
            indefiniteSegment
        }
    }

    // MARK: - Preset Segment

    @ViewBuilder
    private func durationSegment(_ preset: DefaultDuration) -> some View {
        let isSelected = manager.mode.isTimed && (
            manager.sessionDuration == preset.rawValue ||
            abs((manager.mode.endDate?.timeIntervalSinceNow ?? 0) - preset.rawValue) < 2
        )

        Button {
            manager.start(for: preset.rawValue)
        } label: {
            Text(preset.shortLabel)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.85))
                .frame(maxWidth: .infinity)
                .frame(height: NativeTheme.pillHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .liquidGlassPill(isSelected: isSelected, activeColor: eyeColor)
        .accessibilityLabel(preset.accessibilityLabel)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    // MARK: - Indefinite Segment (∞)

    @ViewBuilder
    private var indefiniteSegment: some View {
        let isSelected = manager.mode.isIndefinite

        Button {
            manager.startIndefinitely()
        } label: {
            Image(systemName: "infinity")
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.85))
                .frame(maxWidth: .infinity)
                .frame(height: NativeTheme.pillHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .liquidGlassPill(isSelected: isSelected, activeColor: eyeColor)
        .accessibilityLabel("Keep awake indefinitely without time limit")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}
