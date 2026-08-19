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
        HStack(spacing: 2) {
            ForEach(DefaultDuration.allCases, id: \.self) { preset in
                durationSegment(preset)
            }
            indefiniteSegment
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: NativeTheme.segmentedCornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.6 : 0.8))
        }
        .overlay {
            RoundedRectangle(cornerRadius: NativeTheme.segmentedCornerRadius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.3 : 0.15), lineWidth: 0.5)
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
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.85))
                .frame(maxWidth: .infinity, minHeight: NativeTheme.segmentedHeight - 4)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: NativeTheme.innerSegmentCornerRadius, style: .continuous)
                            .fill(manager.isActive ? eyeColor : Color.accentColor)
                            .shadow(color: Color.black.opacity(0.12), radius: 1, y: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.85))
                .frame(maxWidth: .infinity, minHeight: NativeTheme.segmentedHeight - 4)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: NativeTheme.innerSegmentCornerRadius, style: .continuous)
                            .fill(manager.isActive ? eyeColor : Color.accentColor)
                            .shadow(color: Color.black.opacity(0.12), radius: 1, y: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Keep awake indefinitely without time limit")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}
